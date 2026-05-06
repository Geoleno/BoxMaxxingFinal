import Foundation
import Combine
import AVFoundation
import CoreMedia
import SwiftUI

final class SessionManager: ObservableObject {

    // MARK: - Published State

    @Published var isRecording = false
    @Published var isAnalyzing = false
    @Published var elapsedSeconds = 0
    @Published var livePunches: [LivePunch] = []
    @Published var showStopConfirmation = false
    @Published var currentSkeleton: SkeletonFrame?
    @Published var videoBufferSize: CGSize = CGSize(width: 1080, height: 1920)
    @Published var currentTargetMove: Move? = nil
    @Published var lastWindowResult: WindowResult? = nil

    // MARK: - Session Config

    private(set) var selectedCombo: Combo?

    // MARK: - Timing Constants

    private let sessionDuration: TimeInterval = 120
    private let moveWindowDuration: TimeInterval = 3.0

    // MARK: - Internal State

    private var sessionStartDate: Date?
    private var sessionTimer: Timer?
    private var windowTimer: Timer?
    private var currentMoveIndex = 0
    private var globalWindowIndex = 0
    private var currentFramePredictions: [FramePrediction] = []
    private var currentWindowMoveId: String = ""

    // MARK: - Wrong Movement Detection

    private let detector = MovementDetector()
    private var liveWrongMovements: [WrongMovement] = []

    // MARK: - HUD Stabilization

    private let stabilizationDuration: TimeInterval = 0.4
    private var stabilizationTimer: Timer?
    private var pendingPunch: LivePunch?

    // MARK: - Services

    private let visionProcessor = VisionProcessor()
    private let mlEngine = MLInferenceEngine()
    private let audioCuePlayer = AudioCuePlayer()

    // MARK: - Configuration

    func configure(combo: Combo) {
        selectedCombo = combo
        currentMoveIndex = 0
        globalWindowIndex = 0
        elapsedSeconds = 0
        livePunches = []
        liveWrongMovements = []
        currentWindowMoveId = ""
        currentTargetMove = nil
        lastWindowResult = nil
        detector.reset()
    }

    // MARK: - Session Control

    func startSession() {
        guard let combo = selectedCombo, !combo.moveIds.isEmpty else { return }

        isRecording = true
        sessionStartDate = Date()
        currentMoveIndex = 0
        globalWindowIndex = 0
        elapsedSeconds = 0
        livePunches = []
        liveWrongMovements = []
        currentWindowMoveId = ""
        mlEngine.resetBuffer()
        detector.reset()

        mlEngine.loadModel()

        if !isCameraAvailable() {
            SessionRecorder.shared.allowRecordingWithoutCamera = true
        }

        if SessionRecorder.shared.debugVideoOverride == nil {
            SessionRecorder.shared.startRecording()
        }

        startSessionTimer()
        beginMoveWindow()
    }

    func requestStop() { showStopConfirmation = true }
    func confirmStop() { showStopConfirmation = false; finalizeSession() }
    func cancelStop()  { showStopConfirmation = false }

    func finalizeSession() {
        guard isRecording else { return }

        sessionTimer?.invalidate();       sessionTimer = nil
        windowTimer?.invalidate();        windowTimer = nil
        stabilizationTimer?.invalidate(); stabilizationTimer = nil
        pendingPunch = nil

        isRecording       = false
        currentSkeleton   = nil
        currentTargetMove = nil
        lastWindowResult  = nil
        isAnalyzing       = true

        let movementsSnapshot = liveWrongMovements
        let startDate = sessionStartDate ?? Date()
        let elapsed = elapsedSeconds

        Task { @MainActor in
            do {
                let videoURL: URL
                if let override = SessionRecorder.shared.debugVideoOverride {
                    videoURL = override
                } else {
                    videoURL = try await SessionRecorder.shared.stopRecording()
                }
                SessionStore.shared.save(movements: movementsSnapshot,
                                         videoURL: videoURL,
                                         startDate: startDate,
                                         duration: TimeInterval(elapsed))
            } catch {
                SessionStore.shared.save(movements: movementsSnapshot,
                                         videoURL: nil,
                                         startDate: startDate,
                                         duration: TimeInterval(elapsed))
            }
            isAnalyzing = false
        }
    }

    // MARK: - Camera Frame Input

    func processFrame(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        guard isRecording else { return }

        let bufferWidth  = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let bufferHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))

        visionProcessor.detectBodyPose(from: pixelBuffer) { [weak self] observations in
            guard let self else { return }
            let prediction = self.mlEngine.predictMove(from: observations)
            let skeleton   = self.visionProcessor.extractSkeleton(from: observations)
            DispatchQueue.main.async {
                guard self.isRecording else { return }
                let newSize = CGSize(width: bufferWidth, height: bufferHeight)
                if self.videoBufferSize != newSize { self.videoBufferSize = newSize }
                self.currentSkeleton = skeleton
                self.currentFramePredictions.append(prediction)
                if let wrong = self.detector.process(prediction: prediction,
                                                      timestamp: timestamp,
                                                      expectedMoveId: self.currentWindowMoveId) {
                    self.liveWrongMovements.append(wrong)
                }
                self.updateLivePunchIfNeeded(prediction: prediction)
            }
        }
    }

    // MARK: - Private Timers

    private func startSessionTimer() {
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.elapsedSeconds += 1
            if self.elapsedSeconds >= Int(self.sessionDuration) {
                self.showStopConfirmation = false
                self.finalizeSession()
            }
        }
    }

    private func beginMoveWindow() {
        guard isRecording, let combo = selectedCombo else { return }
        detector.reset()

        let moveId = combo.moveIds[currentMoveIndex % combo.moveIds.count]
        currentWindowMoveId = moveId
        currentTargetMove = findMove(moveId)
        audioCuePlayer.playAudioCue(for: moveId)
        currentFramePredictions = []

        windowTimer = Timer.scheduledTimer(withTimeInterval: moveWindowDuration, repeats: false) { [weak self] _ in
            self?.endMoveWindow()
        }
    }

    private func endMoveWindow() {
        guard isRecording else { return }
        currentFramePredictions = []
        globalWindowIndex += 1
        currentMoveIndex += 1
        beginMoveWindow()
    }

    // MARK: - Live Punch HUD

    private func updateLivePunchIfNeeded(prediction: FramePrediction) {
        guard let move = findMove(prediction.label),
              prediction.confidence > 0.5 else { return }

        pendingPunch = LivePunch(move: move, confidence: Double(prediction.confidence), timestamp: Date())

        stabilizationTimer?.invalidate()
        stabilizationTimer = Timer.scheduledTimer(withTimeInterval: stabilizationDuration, repeats: false) { [weak self] _ in
            guard let self, let punch = self.pendingPunch else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                self.livePunches = [punch] + Array(self.livePunches.prefix(1))
            }
            self.pendingPunch = nil
        }
    }

    // MARK: - Camera Availability

    private func isCameraAvailable() -> Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil
    }
}
