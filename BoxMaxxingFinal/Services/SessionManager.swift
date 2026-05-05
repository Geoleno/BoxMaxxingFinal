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
    @Published var currentSkeleton: SkeletonFrame?
    @Published var videoBufferSize: CGSize = CGSize(width: 1080, height: 1920)
    @Published var currentTargetMove: Move? = nil
    @Published var lastWindowResult: WindowResult? = nil

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
    private var liveSessionEvents: [SessionEvent] = []
    private var currentWindowMoveId: String = ""
    private var windowResultToken = UUID()

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
        liveSessionEvents = []
        currentWindowMoveId = ""
        currentTargetMove = nil
        lastWindowResult = nil
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
        liveSessionEvents = []
        currentWindowMoveId = ""
        mlEngine.resetBuffer()

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

        isRecording = false
        currentSkeleton = nil
        currentTargetMove = nil
        lastWindowResult = nil
        isAnalyzing = true

        if !liveSessionEvents.isEmpty {
            // Fast path: evaluation already completed during the session
            SessionStore.shared.save(
                events:    liveSessionEvents,
                startDate: sessionStartDate ?? Date(),
                duration:  TimeInterval(elapsedSeconds)
            )
            isAnalyzing = false   // ResultsView opens immediately

            // Background: finalize the video file and extract clips for wrong/unclear events
            let eventsSnapshot = liveSessionEvents
            Task {
                do {
                    let videoURL: URL
                    if let override = SessionRecorder.shared.debugVideoOverride {
                        videoURL = override
                    } else {
                        videoURL = try await SessionRecorder.shared.stopRecording()
                    }
                    await PostSessionAnalyzer.shared.extractClips(videoURL: videoURL, events: eventsSnapshot)
                } catch {
                    // Recording failed — accuracy data already saved, clips unavailable
                }
            }
        } else {
            // Fallback: no live events (no camera / all windows had no body detected)
            Task { @MainActor in
                do {
                    let videoURL: URL
                    if let override = SessionRecorder.shared.debugVideoOverride {
                        videoURL = override
                    } else {
                        videoURL = try await SessionRecorder.shared.stopRecording()
                    }

                    var events = await PostSessionAnalyzer.shared.analyze(videoURL: videoURL)

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
                    SessionStore.shared.save(
                        events:    fallbackEvents,
                        startDate: sessionStartDate ?? Date(),
                        duration:  TimeInterval(elapsedSeconds)
                    )
                }

                isAnalyzing = false
            }
        }
    }

    // MARK: - Camera Frame Input (called by CameraPreviewView on every frame)

    func processFrame(_ pixelBuffer: CVPixelBuffer) {
        guard isRecording else { return }

        // Read dimensions on the camera thread (safe for CVPixelBuffer metadata queries)
        let bufferWidth = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let bufferHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))

        visionProcessor.detectBodyPose(from: pixelBuffer) { [weak self] observations in
            guard let self else { return }
            let prediction = self.mlEngine.predictMove(from: observations)
            let skeleton = self.visionProcessor.extractSkeleton(from: observations)
            DispatchQueue.main.async {
                guard self.isRecording else { return }
                let newSize = CGSize(width: bufferWidth, height: bufferHeight)
                if self.videoBufferSize.width != newSize.width || self.videoBufferSize.height != newSize.height {
                    self.videoBufferSize = newSize
                }
                self.currentSkeleton = skeleton
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
        currentWindowMoveId = moveId
        currentTargetMove = findMove(moveId)
        audioCuePlayer.playAudioCue(for: moveId)
        currentFramePredictions = []

        windowTimer = Timer.scheduledTimer(withTimeInterval: moveWindowDuration, repeats: false) { [weak self] _ in
            self?.endMoveWindow()
        }
    }

    private func endMoveWindow() {
        guard isRecording, let combo = selectedCombo else { return }

        let predictions = currentFramePredictions
        let expectedMoveId = currentWindowMoveId
        let expectedMove = findMove(expectedMoveId)

        let (dominantLabel, avgConfidence) = MovementAggregator().aggregate(predictions: predictions)

        // Only emit a SessionEvent when a real move was detected (not no_body / no_movement)
        if let expectedMove, findMove(dominantLabel) != nil {
            let detectedMove = findMove(dominantLabel)!
            let matched = dominantLabel == expectedMoveId

            let status: SessionEvent.EventStatus
            if avgConfidence > 0.80 {
                status = .correct
            } else if avgConfidence > 0.50 {
                status = .unclear
            } else {
                status = .wrong
            }

            liveSessionEvents.append(SessionEvent(
                id:         UUID().uuidString,
                time:       elapsedSeconds,
                move:       expectedMove,
                status:     status,
                confidence: Double(avgConfidence),
                detectedAs: matched ? nil : detectedMove.name,
                note:       PerformanceFeedback.suggestion(for: expectedMoveId),
                clipURL:    nil
            ))

            // Publish HUD result — auto-clears after 1.5s using a token to avoid stale clears
            let token = UUID()
            windowResultToken = token
            lastWindowResult = WindowResult(
                expectedMoveId: expectedMoveId,
                detectedMoveId: dominantLabel,
                confidence:     Double(avgConfidence),
                matched:        matched
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, self.windowResultToken == token else { return }
                self.lastWindowResult = nil
            }
        }

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
