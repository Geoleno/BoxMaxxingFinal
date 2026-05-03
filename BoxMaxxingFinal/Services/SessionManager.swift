import Foundation
import Combine
import AVFoundation
import SwiftUI

// MARK: - Session Manager

final class SessionManager: ObservableObject {

    // MARK: - Published State (drives RecordingView UI)

    @Published var isRecording = false
    @Published var elapsedSeconds = 0
    @Published var livePunches: [LivePunch] = []
    @Published var showStopConfirmation = false

    // MARK: - Session Config

    private(set) var selectedCombo: Combo?

    // MARK: - Fixed Timing Constants

    private let sessionDuration: TimeInterval = 120  // 2 minutes — fixed
    private let moveWindowDuration: TimeInterval = 3.0

    // MARK: - Internal State

    private var sessionStartDate: Date?
    private var sessionTimer: Timer?
    private var windowTimer: Timer?
    private var currentMoveIndex = 0
    private var globalWindowIndex = 0
    private var currentFramePredictions: [FramePrediction] = []
    private var collectedEvents: [SessionEvent] = []

    // MARK: - Services

    private let visionProcessor = VisionProcessor()
    private let mlEngine = MLInferenceEngine()
    private let audioCuePlayer = AudioCuePlayer()
    private let aggregator = MovementAggregator()

    // MARK: - Thread Safety

    private let predictionsQueue = DispatchQueue(label: "shadowbox.predictions", qos: .userInteractive)

    // MARK: - Configuration

    func configure(combo: Combo) {
        selectedCombo = combo
        collectedEvents = []
        currentMoveIndex = 0
        globalWindowIndex = 0
        elapsedSeconds = 0
        livePunches = []
    }

    // MARK: - Session Control

    func startSession() {
        guard let combo = selectedCombo, !combo.moveIds.isEmpty else { return }

        isRecording = true
        sessionStartDate = Date()
        collectedEvents = []
        currentMoveIndex = 0
        globalWindowIndex = 0
        elapsedSeconds = 0
        livePunches = []

        mlEngine.loadModel()
        startSessionTimer()
        beginMoveWindow()
    }

    func requestStop() {
        showStopConfirmation = true
    }

    func confirmStop() {
        showStopConfirmation = false
        finalizeSession()
    }

    func cancelStop() {
        showStopConfirmation = false
        // Session continues — timer still running
    }

    func finalizeSession() {
        guard isRecording else { return }
        isRecording = false

        sessionTimer?.invalidate(); sessionTimer = nil
        windowTimer?.invalidate(); windowTimer = nil

        let start = sessionStartDate ?? Date()
        let duration = TimeInterval(elapsedSeconds)
        let events = collectedEvents

        SessionStore.shared.save(events: events, startDate: start, duration: duration)
    }

    // MARK: - Camera Frame Input (called by CameraPreviewView on every frame)

    func processFrame(_ pixelBuffer: CVPixelBuffer) {
        guard isRecording else { return }

        // Feed to clip recorder
        ClipRecorder.shared.appendFrame(pixelBuffer)

        // Run Vision + ML inference on background queue; dispatch prediction to main
        visionProcessor.detectBodyPose(from: pixelBuffer) { [weak self] observations in
            guard let self else { return }
            let prediction = self.mlEngine.predictMove(from: observations)
            DispatchQueue.main.async {
                guard self.isRecording else { return }
                self.currentFramePredictions.append(prediction)
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
                // Auto-finalize when 2-minute limit reached (even if stop dialog is open)
                self.showStopConfirmation = false
                self.finalizeSession()
            }
        }
    }

    private func beginMoveWindow() {
        guard isRecording, let combo = selectedCombo else { return }

        let moveId = combo.moveIds[currentMoveIndex % combo.moveIds.count]

        audioCuePlayer.playAudioCue(for: moveId)
        ClipRecorder.shared.startClip(for: moveId, windowIndex: globalWindowIndex)
        currentFramePredictions = []

        windowTimer = Timer.scheduledTimer(withTimeInterval: moveWindowDuration, repeats: false) { [weak self] _ in
            self?.endMoveWindow()
        }
    }

    private func endMoveWindow() {
        guard isRecording, let combo = selectedCombo else { return }

        let loopedIndex = currentMoveIndex % combo.moveIds.count
        let moveId = combo.moveIds[loopedIndex]
        guard let expectedMove = findMove(moveId) else { return }

        let predictions = currentFramePredictions
        currentFramePredictions = []

        let (predictedLabel, confidence) = aggregator.aggregate(predictions: predictions)
        let elapsedAtEnd = elapsedSeconds
        let windowIdx = globalWindowIndex

        ClipRecorder.shared.stopAndEvaluate(
            confidence: confidence,
            predictedLabel: predictedLabel,
            moveId: moveId,
            windowIndex: windowIdx
        ) { [weak self] clipURL in
            guard let self else { return }

            let isAccurate = (predictedLabel == moveId) && (confidence >= 0.85)

            let status: SessionEvent.EventStatus
            if isAccurate {
                status = .correct
            } else if predictedLabel == "no_body_detected" || predictedLabel == "no_movement_detected" {
                status = .unclear
            } else {
                status = .wrong
            }

            let detectedMoveName: String?
            switch predictedLabel {
            case "no_body_detected":    detectedMoveName = "body not detected"
            case "no_movement_detected": detectedMoveName = "no movement"
            case moveId:                detectedMoveName = nil
            default:                    detectedMoveName = findMove(predictedLabel)?.name ?? predictedLabel
            }

            let note: String
            switch predictedLabel {
            case "no_body_detected":    note = PerformanceFeedback.noScanFeedback()
            case "no_movement_detected": note = PerformanceFeedback.noMovementFeedback()
            default:                    note = PerformanceFeedback.suggestion(for: moveId)
            }

            let event = SessionEvent(
                id: UUID().uuidString,
                time: elapsedAtEnd,
                move: expectedMove,
                status: status,
                confidence: Double(confidence),
                detectedAs: detectedMoveName,
                note: note,
                clipURL: clipURL
            )

            DispatchQueue.main.async {
                self.collectedEvents.append(event)
            }
        }

        globalWindowIndex += 1
        currentMoveIndex += 1

        if isRecording {
            beginMoveWindow()
        }
    }

    // MARK: - Live Punch Chip Updates

    private func updateLivePunchIfNeeded(prediction: FramePrediction) {
        guard let move = findMove(prediction.label),
              prediction.confidence > 0.5 else { return }

        let punch = LivePunch(move: move, confidence: Double(prediction.confidence), timestamp: Date())
        withAnimation(.easeOut(duration: 0.3)) {
            livePunches = [punch] + Array(livePunches.prefix(1))
        }
    }
}
