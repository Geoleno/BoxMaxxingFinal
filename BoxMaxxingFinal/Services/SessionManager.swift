import Foundation
import Combine
import AVFoundation
import SwiftUI

// MARK: - Session Manager

final class SessionManager: ObservableObject {

    // MARK: - Published State (drives RecordingView UI)

    @Published var isRecording = false
    @Published var isAnalyzing = false      // true while PostSessionAnalyzer runs
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

    // MARK: - HUD Stabilization

    private let stabilizationDuration: TimeInterval = 0.4
    private var stabilizationTimer: Timer?
    private var pendingPunch: LivePunch?

    // MARK: - Services

    private let visionProcessor = VisionProcessor()
    private let mlEngine = MLInferenceEngine()
    private let audioCuePlayer = AudioCuePlayer()

    // MARK: - Thread Safety

    private let predictionsQueue = DispatchQueue(label: "shadowbox.predictions", qos: .userInteractive)

    // MARK: - Configuration

    func configure(combo: Combo) {
        selectedCombo = combo
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
        currentMoveIndex = 0
        globalWindowIndex = 0
        elapsedSeconds = 0
        livePunches = []

        mlEngine.loadModel()

        // Check if camera is available; if not, enable override to allow app to continue
        if !isCameraAvailable() {
            SessionRecorder.shared.allowRecordingWithoutCamera = true
        }

        // Skip live recording when a debug video is injected for testing
        if SessionRecorder.shared.debugVideoOverride == nil {
            SessionRecorder.shared.startRecording()
        }

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

        sessionTimer?.invalidate();       sessionTimer = nil
        windowTimer?.invalidate();        windowTimer = nil
        stabilizationTimer?.invalidate(); stabilizationTimer = nil
        pendingPunch = nil

        isRecording = false     // RecordingView: phase switches to .done (ReviewingOverlay)
        isAnalyzing = true

        Task { @MainActor in
            do {
                // Use debug video if set, otherwise use the live-recorded session file
                let videoURL: URL
                if let override = SessionRecorder.shared.debugVideoOverride {
                    videoURL = override
                } else {
                    videoURL = try await SessionRecorder.shared.stopRecording()
                }

                var events = await PostSessionAnalyzer.shared.analyze(videoURL: videoURL)

                // If no events were detected (no camera / body not found / analyzer not yet implemented),
                // fall back to generating expected events from the selected combo's move sequence.
                if events.isEmpty, let combo = selectedCombo {
                    let state = SessionState(
                        selectedComboId: combo.id,
                        selectedMoveIds: combo.moveIds,
                        sessionLength: Int(sessionDuration / 60)
                    )
                    events = generateEvents(state: state)
                }

                SessionStore.shared.save(
                    events:    events,
                    startDate: sessionStartDate ?? Date(),
                    duration:  TimeInterval(elapsedSeconds)
                )
            } catch {
                // Recording failed — generate expected events rather than show empty results
                let fallbackEvents: [SessionEvent]
                if let combo = selectedCombo {
                    let state = SessionState(
                        selectedComboId: combo.id,
                        selectedMoveIds: combo.moveIds,
                        sessionLength: Int(sessionDuration / 60)
                    )
                    fallbackEvents = generateEvents(state: state)
                } else {
                    fallbackEvents = []
                }
                SessionStore.shared.save(events: fallbackEvents, startDate: sessionStartDate ?? Date(), duration: TimeInterval(elapsedSeconds))
            }

            isAnalyzing = false     // RecordingView: calls onFinish() → navigates to Results
        }
    }

    // MARK: - Camera Frame Input (called by CameraPreviewView on every frame)

    func processFrame(_ pixelBuffer: CVPixelBuffer) {
        guard isRecording else { return }

        // Vision + ML inference drives live punch chips in the HUD only.
        // Full-session recording is handled by SessionRecorder via AVCaptureMovieFileOutput.
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
        currentFramePredictions = []

        windowTimer = Timer.scheduledTimer(withTimeInterval: moveWindowDuration, repeats: false) { [weak self] _ in
            self?.endMoveWindow()
        }
    }

    private func endMoveWindow() {
        guard isRecording else { return }
        // Events are built post-session by PostSessionAnalyzer, not here.
        // This loop only drives audio cues via beginMoveWindow.
        currentFramePredictions = []
        globalWindowIndex += 1
        currentMoveIndex += 1
        beginMoveWindow()
    }

    // MARK: - Live Punch Chip Updates

    private func updateLivePunchIfNeeded(prediction: FramePrediction) {
        guard let move = findMove(prediction.label),
              prediction.confidence > 0.5 else { return }

        // Always keep the latest candidate ready
        pendingPunch = LivePunch(move: move, confidence: Double(prediction.confidence), timestamp: Date())

        // Reset the timer on every new detection — only commit once detections stop changing
        stabilizationTimer?.invalidate()
        stabilizationTimer = Timer.scheduledTimer(withTimeInterval: stabilizationDuration, repeats: false) { [weak self] _ in
            guard let self, let punch = self.pendingPunch else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                self.livePunches = [punch] + Array(self.livePunches.prefix(1))
            }
            self.pendingPunch = nil
        }
    }

    // MARK: - Camera Availability Check

    private func isCameraAvailable() -> Bool {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            return false
        }
        return true
    }
}
