# Session Recorder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace per-window `ClipRecorder` with a single continuous session recording, add post-session sliding-window analysis via `PostSessionAnalyzer`, and wire `VideoPlayerView` into `DetailSheetView` for timestamp-seeked playback.

**Architecture:** `SessionRecorder` records the full 2-minute session as one `.mov` file using `AVCaptureMovieFileOutput` added to the existing `AVCaptureSession`. After recording ends, `SessionManager.finalizeSession()` calls `PostSessionAnalyzer.analyze(videoURL:)` via async/await, which runs a 60-frame sliding window to produce `[SessionEvent]`. `VideoPlayerView` (a `UIViewRepresentable`) seeks `AVPlayer` to `event.time` for inline clip playback in `DetailSheetView`.

**Tech Stack:** Swift 5.9, SwiftUI, AVFoundation (`AVCaptureMovieFileOutput`, `AVPlayer`, `AVAssetReader`), Vision, CoreML (placeholder), XCTest

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `BoxMaxxingFinal/Services/SessionRecorder.swift` | **Create** | Owns `AVCaptureMovieFileOutput`, manages session `.mov` file |
| `BoxMaxxingFinal/Services/PostSessionAnalyzer.swift` | **Create** | Sliding-window analysis → `[SessionEvent]` |
| `BoxMaxxingFinal/VideoPlayerView.swift` | **Create** | `UIViewRepresentable` wrapping `AVPlayer` with seek |
| `BoxMaxxingFinalTests/PostSessionAnalyzerTests.swift` | **Create** | Unit tests for pure grouping/selection/build logic |
| `BoxMaxxingFinal/Services/SessionManager.swift` | **Modify** | Remove `ClipRecorder`, add `isAnalyzing`, new `finalizeSession` |
| `BoxMaxxingFinal/RecordingView.swift` | **Modify** | Wire `movieFileOutput` into `CameraView`; fix `onChange` watchers |
| `BoxMaxxingFinal/ResultsView.swift` | **Modify** | Replace `VideoPanel` placeholder with `VideoPlayerView` (one line) |
| `BoxMaxxingFinal/ContentView.swift` | **Modify** | Swap `ClipRecorder.deleteAllClips()` → `SessionRecorder.deleteSessionFile()` |
| `BoxMaxxingFinal/Services/ClipRecorder.swift` | **Delete** | Entirely replaced — no logic carried forward |

> **Xcode note:** After creating any new `.swift` file with a tool, open Xcode, right-click the correct group in the Project Navigator, choose **"Add Files to 'BoxMaxxingFinal'…"**, select the file, and confirm it is checked under the correct target. Files not added to the Xcode target will not compile.

---

## Task 1: Create SessionRecorder.swift

**Files:**
- Create: `BoxMaxxingFinal/Services/SessionRecorder.swift`

`SessionRecorder` is a singleton that owns `AVCaptureMovieFileOutput`. It is added to `CameraView`'s `AVCaptureSession` once at camera setup (Task 5). `startRecording()` / `stopRecording()` are called by `SessionManager`. `debugVideoOverride` bypasses live recording for testing.

**Why `NSObject`:** `AVCaptureFileOutputRecordingDelegate` is an Objective-C protocol. Swift classes conforming to it must inherit from `NSObject` — this is a framework requirement.

**Why `withCheckedThrowingContinuation`:** `AVCaptureMovieFileOutput.stopRecording()` doesn't return a URL directly. It calls a delegate method later when the file is done. `withCheckedThrowingContinuation` bridges that callback into an `async throws` function — it suspends until the delegate fires, then resumes with the URL (or throws if writing failed).

- [ ] **Step 1: Create the file**

Create `BoxMaxxingFinal/Services/SessionRecorder.swift` with this exact content:

```swift
import AVFoundation
import Foundation

final class SessionRecorder: NSObject, AVCaptureFileOutputRecordingDelegate {

    static let shared = SessionRecorder()
    private override init() {}

    // Added to CameraView's AVCaptureSession in Task 5
    let movieFileOutput = AVCaptureMovieFileOutput()

    // Set to a bundle URL to skip live recording and test the analysis pipeline directly.
    // Set to nil for production.
    var debugVideoOverride: URL? = nil

    private(set) var lastRecordedURL: URL?
    private var recordingContinuation: CheckedContinuation<URL, Error>?

    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // MARK: - Recording Control

    func startRecording() {
        let filename = "session_\(Int(Date().timeIntervalSince1970)).mov"
        let outputURL = documentsDirectory.appendingPathComponent(filename)
        movieFileOutput.startRecording(to: outputURL, recordingDelegate: self)
    }

    func stopRecording() async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            recordingContinuation = continuation
            movieFileOutput.stopRecording()
        }
    }

    // MARK: - Cleanup

    func deleteSessionFile() {
        guard let url = lastRecordedURL else { return }
        try? FileManager.default.removeItem(at: url)
        lastRecordedURL = nil
    }

    // MARK: - AVCaptureFileOutputRecordingDelegate

    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        if let error = error {
            recordingContinuation?.resume(throwing: error)
        } else {
            lastRecordedURL = outputFileURL
            recordingContinuation?.resume(returning: outputFileURL)
        }
        recordingContinuation = nil
    }
}
```

- [ ] **Step 2: Add to Xcode target**

In Xcode: right-click `Services` group → **Add Files to 'BoxMaxxingFinal'…** → select `SessionRecorder.swift` → confirm target is `BoxMaxxingFinal` → Add.

- [ ] **Step 3: Verify it compiles**

Build the project (`⌘B`). Expected: build succeeds with no errors.

- [ ] **Step 4: Commit**

```bash
git add BoxMaxxingFinal/Services/SessionRecorder.swift
git commit -m "feat: add SessionRecorder singleton with AVCaptureMovieFileOutput"
```

---

## Task 2: Create PostSessionAnalyzer.swift (pure functions only)

**Files:**
- Create: `BoxMaxxingFinal/Services/PostSessionAnalyzer.swift`

The `analyze(videoURL:)` method is a placeholder returning `[]` — it requires the CoreML `.mlmodel` file which is not yet available. The three helper functions (`groupWindows`, `selectRepresentative`, `buildEvent`) contain no framework dependencies and are fully implementable now. They are tested in Task 3.

**Why `WindowPrediction` is outside the class:** Swift test files use `@testable import BoxMaxxingFinal` to access types. Types nested inside a class are harder to reference from tests. Defining `WindowPrediction` at module level makes it directly accessible as `WindowPrediction(...)` in tests.

- [ ] **Step 1: Create the file**

Create `BoxMaxxingFinal/Services/PostSessionAnalyzer.swift` with this exact content:

```swift
import AVFoundation
import Vision
import Foundation

// MARK: - Supporting Type

struct WindowPrediction: Equatable {
    let label: String       // e.g. "lj" — must match Move.id in Models.swift
    let confidence: Float   // 0.0–1.0
    let startTime: Double   // seconds from video start (first frame of window)
    let endTime: Double     // seconds from video start (last frame of window)
}

// MARK: - Post Session Analyzer

final class PostSessionAnalyzer {

    static let shared = PostSessionAnalyzer()
    private init() {}

    // MARK: - Constants

    let clipPaddingSeconds: Double = 0.5
    let windowSize = 60     // frames — must match Create ML training config
    let strideSize  = 15    // frames to advance after each prediction

    // MARK: - Main Entry Point

    func analyze(videoURL: URL) async -> [SessionEvent] {
        // TODO: Implement full pipeline when CoreML .mlmodel is available
        // Step 1: Extract frames via AVAssetReader
        // Step 2: Vision pose detection per frame (VNDetectHumanBodyPoseRequest)
        // Step 3: Buffer windowSize frames → run MLInferenceEngine → WindowPrediction
        // Step 4: Filter confidence ≤ 0.20 (undetected) and > 0.80 (correct)
        // Steps 5–8 below are ready — wire in after Steps 1–4 are implemented
        return []
    }

    // MARK: - Step 5: Group consecutive same-label windows

    // Two predictions belong to the same group when:
    // - They share the same label, AND
    // - The gap between them (prediction.startTime - last.endTime) is < 0.5 seconds
    // A new group starts when the label changes or the gap exceeds 0.5s.
    func groupWindows(_ predictions: [WindowPrediction]) -> [[WindowPrediction]] {
        var groups: [[WindowPrediction]] = []
        var current: [WindowPrediction] = []

        for prediction in predictions {
            if current.isEmpty {
                current.append(prediction)
            } else if let last = current.last,
                      last.label == prediction.label,
                      (prediction.startTime - last.endTime) < 0.5 {
                current.append(prediction)
            } else {
                groups.append(current)
                current = [prediction]
            }
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }

    // MARK: - Step 6: Select highest-confidence window per group

    func selectRepresentative(from group: [WindowPrediction]) -> WindowPrediction {
        group.max(by: { $0.confidence < $1.confidence })!
    }

    // MARK: - Step 7: Build SessionEvent from representative window

    // Confidence tiers:
    //   ≤ 0.20  → filtered before reaching here (Step 4)
    //   0.21–0.50 → .wrong   (Red)
    //   0.51–0.80 → .unclear (Yellow)
    //   > 0.80  → .correct  (Green) — clipURL set to nil
    func buildEvent(from window: WindowPrediction,
                    videoDuration: Double,
                    sessionURL: URL) -> SessionEvent {
        let isGreen = window.confidence > 0.80

        let status: SessionEvent.EventStatus
        if window.confidence > 0.80 {
            status = .correct
        } else if window.confidence <= 0.50 {
            status = .wrong
        } else {
            status = .unclear
        }

        return SessionEvent(
            id:         UUID().uuidString,
            time:       Int(window.startTime),
            move:       findMove(window.label) ?? allMoves[0],
            status:     status,
            confidence: Double(window.confidence),
            detectedAs: nil,
            note:       PerformanceFeedback.suggestion(for: window.label),
            clipURL:    isGreen ? nil : sessionURL
        )
    }
}
```

- [ ] **Step 2: Add to Xcode target**

In Xcode: right-click `Services` group → **Add Files to 'BoxMaxxingFinal'…** → select `PostSessionAnalyzer.swift` → confirm target is `BoxMaxxingFinal` → Add.

- [ ] **Step 3: Verify it compiles**

Build (`⌘B`). Expected: build succeeds with no errors.

- [ ] **Step 4: Commit**

```bash
git add BoxMaxxingFinal/Services/PostSessionAnalyzer.swift
git commit -m "feat: add PostSessionAnalyzer with grouping, selection, and buildEvent helpers"
```

---

## Task 3: Write and run unit tests for PostSessionAnalyzer

**Files:**
- Create: `BoxMaxxingFinalTests/PostSessionAnalyzerTests.swift`

These tests cover all three pure functions. They run without a device or camera — just pure Swift logic. Running them often is free.

- [ ] **Step 1: Create the test file**

Create `BoxMaxxingFinalTests/PostSessionAnalyzerTests.swift` with this exact content:

```swift
import XCTest
@testable import BoxMaxxingFinal

final class PostSessionAnalyzerTests: XCTestCase {

    let analyzer = PostSessionAnalyzer.shared
    let sampleURL = URL(fileURLWithPath: "/tmp/test_session.mov")

    // MARK: - groupWindows

    func test_groupWindows_emptyInput_returnsEmpty() {
        XCTAssertTrue(analyzer.groupWindows([]).isEmpty)
    }

    func test_groupWindows_singlePrediction_returnsSingleGroup() {
        let p = WindowPrediction(label: "lj", confidence: 0.6, startTime: 0.0, endTime: 2.0)
        let groups = analyzer.groupWindows([p])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].count, 1)
    }

    func test_groupWindows_sameLabelSmallGap_groupedTogether() {
        // Gap between p1.endTime (2.0) and p2.startTime (2.3) = 0.3s < 0.5 → same group
        let p1 = WindowPrediction(label: "lj", confidence: 0.6, startTime: 0.0, endTime: 2.0)
        let p2 = WindowPrediction(label: "lj", confidence: 0.7, startTime: 2.3, endTime: 4.3)
        let groups = analyzer.groupWindows([p1, p2])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].count, 2)
    }

    func test_groupWindows_sameLabelLargeGap_splitIntoTwoGroups() {
        // Gap between p1.endTime (2.0) and p2.startTime (3.0) = 1.0s > 0.5 → new group
        let p1 = WindowPrediction(label: "lj", confidence: 0.6, startTime: 0.0, endTime: 2.0)
        let p2 = WindowPrediction(label: "lj", confidence: 0.7, startTime: 3.0, endTime: 5.0)
        let groups = analyzer.groupWindows([p1, p2])
        XCTAssertEqual(groups.count, 2)
    }

    func test_groupWindows_differentLabels_splitIntoTwoGroups() {
        let p1 = WindowPrediction(label: "lj", confidence: 0.6, startTime: 0.0, endTime: 2.0)
        let p2 = WindowPrediction(label: "rj", confidence: 0.7, startTime: 2.3, endTime: 4.3)
        let groups = analyzer.groupWindows([p1, p2])
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0][0].label, "lj")
        XCTAssertEqual(groups[1][0].label, "rj")
    }

    func test_groupWindows_threeWindowsSameLabel_oneGroup() {
        let p1 = WindowPrediction(label: "lh", confidence: 0.4, startTime: 0.0, endTime: 2.0)
        let p2 = WindowPrediction(label: "lh", confidence: 0.6, startTime: 2.1, endTime: 4.1)
        let p3 = WindowPrediction(label: "lh", confidence: 0.5, startTime: 4.2, endTime: 6.2)
        let groups = analyzer.groupWindows([p1, p2, p3])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].count, 3)
    }

    // MARK: - selectRepresentative

    func test_selectRepresentative_returnsHighestConfidence() {
        let p1 = WindowPrediction(label: "lj", confidence: 0.40, startTime: 0.0, endTime: 2.0)
        let p2 = WindowPrediction(label: "lj", confidence: 0.71, startTime: 2.0, endTime: 4.0)
        let p3 = WindowPrediction(label: "lj", confidence: 0.55, startTime: 4.0, endTime: 6.0)
        let rep = analyzer.selectRepresentative(from: [p1, p2, p3])
        XCTAssertEqual(rep.confidence, 0.71, accuracy: 0.001)
    }

    func test_selectRepresentative_singleElement_returnsThatElement() {
        let p = WindowPrediction(label: "rj", confidence: 0.65, startTime: 5.0, endTime: 7.0)
        let rep = analyzer.selectRepresentative(from: [p])
        XCTAssertEqual(rep, p)
    }

    // MARK: - buildEvent

    func test_buildEvent_yellowConfidence_statusIsUnclear_clipURLSet() {
        let p = WindowPrediction(label: "lj", confidence: 0.65, startTime: 10.0, endTime: 12.0)
        let event = analyzer.buildEvent(from: p, videoDuration: 120.0, sessionURL: sampleURL)
        XCTAssertEqual(event.status, .unclear)
        XCTAssertEqual(event.time, 10)
        XCTAssertEqual(event.clipURL, sampleURL)
    }

    func test_buildEvent_redConfidence_statusIsWrong_clipURLSet() {
        let p = WindowPrediction(label: "rj", confidence: 0.35, startTime: 5.0, endTime: 7.0)
        let event = analyzer.buildEvent(from: p, videoDuration: 120.0, sessionURL: sampleURL)
        XCTAssertEqual(event.status, .wrong)
        XCTAssertEqual(event.clipURL, sampleURL)
    }

    func test_buildEvent_greenConfidence_statusIsCorrect_clipURLIsNil() {
        let p = WindowPrediction(label: "lh", confidence: 0.90, startTime: 30.0, endTime: 32.0)
        let event = analyzer.buildEvent(from: p, videoDuration: 120.0, sessionURL: sampleURL)
        XCTAssertEqual(event.status, .correct)
        XCTAssertNil(event.clipURL)
    }

    func test_buildEvent_usesWindowStartTimeAsEventTime() {
        let p = WindowPrediction(label: "lu", confidence: 0.55, startTime: 47.5, endTime: 49.5)
        let event = analyzer.buildEvent(from: p, videoDuration: 120.0, sessionURL: sampleURL)
        XCTAssertEqual(event.time, 47)   // Int(47.5) = 47
    }

    func test_buildEvent_unknownMoveId_fallsBackToFirstMove() {
        let p = WindowPrediction(label: "unknown_move", confidence: 0.55, startTime: 5.0, endTime: 7.0)
        let event = analyzer.buildEvent(from: p, videoDuration: 120.0, sessionURL: sampleURL)
        XCTAssertEqual(event.move.id, allMoves[0].id)
    }
}
```

- [ ] **Step 2: Add to Xcode test target**

In Xcode: right-click `BoxMaxxingFinalTests` group → **Add Files to 'BoxMaxxingFinal'…** → select `PostSessionAnalyzerTests.swift` → confirm target is **`BoxMaxxingFinalTests`** (not `BoxMaxxingFinal`) → Add.

- [ ] **Step 3: Run the tests and verify they all pass**

In Xcode: `⌘U` to run all tests.
Expected: all 12 tests pass with green checkmarks.

If any test fails, read the failure message — it will tell you exactly which assertion failed and what the actual vs expected values were.

- [ ] **Step 4: Commit**

```bash
git add BoxMaxxingFinalTests/PostSessionAnalyzerTests.swift
git commit -m "test: add unit tests for PostSessionAnalyzer grouping and build logic"
```

---

## Task 4: Create VideoPlayerView.swift

**Files:**
- Create: `BoxMaxxingFinal/VideoPlayerView.swift`

`UIViewRepresentable` lets you use a UIKit view inside SwiftUI. `AVPlayerLayer` (which gives us direct control over video rendering) is UIKit-only — SwiftUI's built-in `VideoPlayer` exists but doesn't expose the layer directly. We need the layer to control `videoGravity` (how the video fills the frame).

**Why `toleranceBefore: .zero, toleranceAfter: .zero`:** Default seek snaps to the nearest video keyframe (up to ~1 second off). Zero tolerance forces frame-accurate seeking. It's marginally slower but essential when events are only 3 seconds apart.

**Why `Coordinator.deinit` pauses:** When the sheet is dismissed, SwiftUI destroys the view hierarchy. `deinit` fires on the `Coordinator` — the last point at which we can stop the player before it's deallocated.

- [ ] **Step 1: Create the file**

Create `BoxMaxxingFinal/VideoPlayerView.swift` with this exact content:

```swift
import SwiftUI
import AVFoundation

struct VideoPlayerView: UIViewRepresentable {
    let url: URL
    let startSeconds: Int

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black

        let player = AVPlayer(url: url)
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.frame = view.bounds
        view.layer.addSublayer(playerLayer)

        let seekTime = CMTime(seconds: Double(startSeconds), preferredTimescale: 600)
        player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            player.play()
        }

        context.coordinator.player      = player
        context.coordinator.playerLayer = playerLayer
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.playerLayer?.frame = uiView.bounds
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var player: AVPlayer?
        var playerLayer: AVPlayerLayer?
        deinit { player?.pause() }
    }
}
```

- [ ] **Step 2: Add to Xcode target**

In Xcode: right-click the `BoxMaxxingFinal` group (root level, next to `ContentView.swift`) → **Add Files to 'BoxMaxxingFinal'…** → select `VideoPlayerView.swift` → confirm target is `BoxMaxxingFinal` → Add.

- [ ] **Step 3: Verify it compiles**

Build (`⌘B`). Expected: build succeeds with no errors.

- [ ] **Step 4: Smoke-test with a hardcoded video (optional but recommended)**

Temporarily add `VideoPlayerView` to `ContentView.swift`'s `.menu` case to verify seek works before wiring it into `DetailSheetView`. In `ContentView.swift`, inside the `case .menu:` block, add below `MenuView`:

```swift
// Temporary smoke test — remove after verifying
if let url = Bundle.main.url(forResource: "sample_session", withExtension: "mov") {
    VideoPlayerView(url: url, startSeconds: 5)
        .frame(height: 200)
}
```

Add a `sample_session.mov` to the bundle (any short video renamed to that), run on device, and confirm the video starts at the 5-second mark. Remove this test code before committing.

- [ ] **Step 5: Commit**

```bash
git add BoxMaxxingFinal/VideoPlayerView.swift
git commit -m "feat: add VideoPlayerView UIViewRepresentable with frame-accurate seek"
```

---

## Task 5: Wire AVCaptureMovieFileOutput into CameraView

**Files:**
- Modify: `BoxMaxxingFinal/RecordingView.swift:153-177` (`CameraView.startSession()`)

`SessionRecorder.shared.movieFileOutput` must be added to `CameraView`'s `AVCaptureSession` before the session starts running. Once added, it stays for the lifetime of the view. `startRecording()` and `stopRecording()` are called later by `SessionManager` — they control when the file is being written, not whether the output is attached to the session.

**Note on dual outputs:** `AVCaptureVideoDataOutput` (for per-frame ML inference) and `AVCaptureMovieFileOutput` (for file recording) can coexist on the same `AVCaptureSession`. The camera hardware delivers frames to both simultaneously.

- [ ] **Step 1: Open RecordingView.swift and locate CameraView.startSession()**

The method starts at line 153. The block that adds `videoOutput` ends at line 166 (`if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }`).

- [ ] **Step 2: Add movieFileOutput after the existing videoOutput block**

Replace lines 153–177 (`private func startSession()`) with:

```swift
private func startSession() {
    session.sessionPreset = .high
    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
          let input = try? AVCaptureDeviceInput(device: device) else { return }
    session.addInput(input)

    // Video output for ML inference (live punch chips in HUD)
    let videoOutput = AVCaptureVideoDataOutput()
    videoOutput.videoSettings = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]
    videoOutput.setSampleBufferDelegate(self, queue: frameQueue)
    videoOutput.alwaysDiscardsLateVideoFrames = true
    if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }

    // Movie file output for full-session recording
    let movieOutput = SessionRecorder.shared.movieFileOutput
    if session.canAddOutput(movieOutput) { session.addOutput(movieOutput) }

    let layer = AVCaptureVideoPreviewLayer(session: session)
    layer.videoGravity = .resizeAspectFill
    layer.frame = bounds
    self.layer.insertSublayer(layer, at: 0)
    previewLayer = layer

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        self?.session.startRunning()
    }
}
```

- [ ] **Step 3: Verify it compiles**

Build (`⌘B`). Expected: build succeeds with no errors.

- [ ] **Step 4: Commit**

```bash
git add BoxMaxxingFinal/RecordingView.swift
git commit -m "feat: wire SessionRecorder.movieFileOutput into CameraView AVCaptureSession"
```

---

## Task 6: Modify SessionManager.swift

**Files:**
- Modify: `BoxMaxxingFinal/Services/SessionManager.swift`

Four changes in this file:

1. Add `@Published var isAnalyzing = false`
2. Modify `startSession()` to call `SessionRecorder.startRecording()` only when no debug override is set
3. Remove all three `ClipRecorder` call sites (`appendFrame`, `startClip`, `stopAndEvaluate`)
4. Replace `finalizeSession()` with the async/await pipeline

- [ ] **Step 1: Add isAnalyzing published property**

In `SessionManager`, after `@Published var showStopConfirmation = false` (line 15), add:

```swift
@Published var isAnalyzing = false
```

- [ ] **Step 2: Replace startSession() — add conditional recording start**

Replace the entire `startSession()` method (lines 60–74) with:

```swift
func startSession() {
    guard let combo = selectedCombo, !combo.moveIds.isEmpty else { return }

    isRecording = true
    sessionStartDate = Date()
    currentMoveIndex = 0
    globalWindowIndex = 0
    elapsedSeconds = 0
    livePunches = []

    mlEngine.loadModel()

    // Skip live recording when testing with a debug video
    if SessionRecorder.shared.debugVideoOverride == nil {
        SessionRecorder.shared.startRecording()
    }

    startSessionTimer()
    beginMoveWindow()
}
```

- [ ] **Step 3: Replace finalizeSession() with async/await pipeline**

Replace the entire `finalizeSession()` method (lines 90–102) with:

```swift
func finalizeSession() {
    guard isRecording else { return }

    sessionTimer?.invalidate(); sessionTimer = nil
    windowTimer?.invalidate();  windowTimer = nil

    isRecording = false    // RecordingView: phase switches to .done (ReviewingOverlay)
    isAnalyzing = true

    Task { @MainActor in
        do {
            let videoURL: URL
            if let override = SessionRecorder.shared.debugVideoOverride {
                videoURL = override
            } else {
                videoURL = try await SessionRecorder.shared.stopRecording()
            }
            let events = await PostSessionAnalyzer.shared.analyze(videoURL: videoURL)
            SessionStore.shared.save(
                events:    events,
                startDate: sessionStartDate ?? Date(),
                duration:  TimeInterval(elapsedSeconds)
            )
        } catch {
            // Recording failed — navigate to Results with empty timeline
            SessionStore.shared.save(events: [], startDate: Date(), duration: 0)
        }
        isAnalyzing = false    // RecordingView: calls onFinish() → navigates to Results
    }
}
```

- [ ] **Step 4: Remove ClipRecorder call from processFrame()**

In `processFrame(_:)` (around line 106), remove this line:

```swift
ClipRecorder.shared.appendFrame(pixelBuffer)
```

The full method after removal:

```swift
func processFrame(_ pixelBuffer: CVPixelBuffer) {
    guard isRecording else { return }

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
```

- [ ] **Step 5: Remove ClipRecorder call from beginMoveWindow()**

In `beginMoveWindow()` (around line 138), remove this line:

```swift
ClipRecorder.shared.startClip(for: moveId, windowIndex: globalWindowIndex)
```

The full method after removal:

```swift
private func beginMoveWindow() {
    guard isRecording, let combo = selectedCombo else { return }

    let moveId = combo.moveIds[currentMoveIndex % combo.moveIds.count]

    audioCuePlayer.playAudioCue(for: moveId)
    currentFramePredictions = []

    windowTimer = Timer.scheduledTimer(withTimeInterval: moveWindowDuration, repeats: false) { [weak self] _ in
        self?.endMoveWindow()
    }
}
```

- [ ] **Step 6: Replace endMoveWindow() — remove all event building**

Replace the entire `endMoveWindow()` method (lines 152–222) with:

```swift
private func endMoveWindow() {
    guard isRecording else { return }
    currentFramePredictions = []
    globalWindowIndex += 1
    currentMoveIndex += 1
    beginMoveWindow()
}
```

**Why remove event building:** Events are now produced by `PostSessionAnalyzer` after the session ends. The per-window aggregation and `ClipRecorder.stopAndEvaluate` loop is replaced entirely by the sliding-window post-processing pipeline.

- [ ] **Step 7: Remove collectedEvents from properties and configure()**

Remove this line from the properties block (around line 33):

```swift
private var collectedEvents: [SessionEvent] = []
```

Also remove `collectedEvents = []` from `configure(combo:)`. The full method after removal:

```swift
func configure(combo: Combo) {
    selectedCombo = combo
    currentMoveIndex = 0
    globalWindowIndex = 0
    elapsedSeconds = 0
    livePunches = []
}
```

- [ ] **Step 8: Verify it compiles**

Build (`⌘B`). Expected: build succeeds. If there are `ClipRecorder` references remaining, Xcode will show "use of unresolved identifier 'ClipRecorder'" — search (`⌘⇧F`) for `ClipRecorder` to find any remaining call sites and remove them.

- [ ] **Step 9: Run tests**

`⌘U`. Expected: all PostSessionAnalyzerTests still pass.

- [ ] **Step 10: Commit**

```bash
git add BoxMaxxingFinal/Services/SessionManager.swift
git commit -m "feat: wire SessionRecorder and PostSessionAnalyzer into SessionManager via async/await"
```

---

## Task 7: Fix RecordingView.swift onChange watchers

**Files:**
- Modify: `BoxMaxxingFinal/RecordingView.swift:70-76`

The existing `onChange(of: sessionManager.isRecording)` watcher hardcodes a 0.6s delay before navigating to Results. That delay must be replaced with a watcher on `isAnalyzing` so navigation waits for the actual analysis to complete — which can take 5–15 seconds on a real device.

- [ ] **Step 1: Replace the onChange block**

In `RecordingView.body`, replace lines 70–76:

```swift
// BEFORE
.onChange(of: sessionManager.isRecording) { oldValue, newValue in
    if !newValue && phase == .recording {
        phase = .done
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { onFinish() }
    }
}
```

with:

```swift
// AFTER
.onChange(of: sessionManager.isRecording) { _, newValue in
    if !newValue && phase == .recording {
        phase = .done   // shows ReviewingOverlay immediately
    }
}
.onChange(of: sessionManager.isAnalyzing) { _, analyzing in
    if !analyzing && phase == .done {
        onFinish()      // navigate to Results only when analysis is complete
    }
}
```

- [ ] **Step 2: Verify it compiles**

Build (`⌘B`). Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add BoxMaxxingFinal/RecordingView.swift
git commit -m "fix: wait for PostSessionAnalyzer to complete before navigating to Results"
```

---

## Task 8: Wire VideoPlayerView into DetailSheetView

**Files:**
- Modify: `BoxMaxxingFinal/ResultsView.swift:389`

This is a one-line change. The existing `VideoPanel` placeholder is replaced with `VideoPlayerView`. The surrounding `if event.clipURL != nil` guard already exists — the force-unwrap is safe inside it.

- [ ] **Step 1: Replace the VideoPanel placeholder**

In `DetailSheetView.body` (around line 388), replace:

```swift
// TODO: Replace VideoPanel placeholder with AVPlayer(url: event.clipURL!)
VideoPanel(label: "Recorded · 0:03", playing: $clipPlaying, annotated: false)
    .padding(.bottom, 22)
```

with:

```swift
VideoPlayerView(url: event.clipURL!, startSeconds: event.time)
    .frame(height: 220)
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .padding(.bottom, 22)
```

- [ ] **Step 2: Remove the now-unused clipPlaying state**

`@State private var clipPlaying = false` on line 296 is only used by the old `VideoPanel`. Remove it.

- [ ] **Step 3: Verify it compiles**

Build (`⌘B`). Expected: build succeeds. If `clipPlaying` is used elsewhere in `DetailSheetView`, keep it — check with `⌘F` for remaining uses.

- [ ] **Step 4: Commit**

```bash
git add BoxMaxxingFinal/ResultsView.swift
git commit -m "feat: replace VideoPanel placeholder with VideoPlayerView in DetailSheetView"
```

---

## Task 9: Update ContentView.swift cleanup calls

**Files:**
- Modify: `BoxMaxxingFinal/ContentView.swift:43,54`

Two `ClipRecorder.shared.deleteAllClips()` calls are replaced with `SessionRecorder.shared.deleteSessionFile()`.

- [ ] **Step 1: Replace onBack cleanup call (line 43)**

Replace:

```swift
ClipRecorder.shared.deleteAllClips()
```

with:

```swift
SessionRecorder.shared.deleteSessionFile()
```

- [ ] **Step 2: Replace onAppear startup cleanup call (line 54)**

Replace:

```swift
ClipRecorder.shared.deleteAllClips()
```

with:

```swift
SessionRecorder.shared.deleteSessionFile()
```

- [ ] **Step 3: Verify it compiles**

Build (`⌘B`). Expected: build succeeds. `ClipRecorder` should now have zero references in the project.

- [ ] **Step 4: Verify zero ClipRecorder references remain**

In Xcode, use `⌘⇧F` to search for `ClipRecorder` across the project. Expected: zero results (only the file itself).

- [ ] **Step 5: Commit**

```bash
git add BoxMaxxingFinal/ContentView.swift
git commit -m "chore: replace ClipRecorder cleanup calls with SessionRecorder.deleteSessionFile"
```

---

## Task 10: Delete ClipRecorder.swift and final verification

**Files:**
- Delete: `BoxMaxxingFinal/Services/ClipRecorder.swift`

- [ ] **Step 1: Delete the file from disk**

```bash
rm BoxMaxxingFinal/Services/ClipRecorder.swift
```

- [ ] **Step 2: Remove from Xcode project**

In Xcode, the `ClipRecorder.swift` file in the Project Navigator will show with a red tint (missing from disk). Right-click it → **Delete** → **Remove Reference**. This removes it from the `.xcodeproj` without trying to move it to trash.

- [ ] **Step 3: Verify build succeeds**

Build (`⌘B`). Expected: build succeeds. If there are any remaining `ClipRecorder` references, Xcode will show "use of unresolved identifier" — find and remove them.

- [ ] **Step 4: Run all tests**

`⌘U`. Expected: all PostSessionAnalyzerTests pass.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: delete ClipRecorder.swift — replaced entirely by SessionRecorder"
```

---

## Task 11: End-to-end verification

Manual verification steps (on a physical device — camera doesn't work on Simulator).

- [ ] **Step 1: Verify the session file is written to disk**

Add a temporary print after `isAnalyzing = false` in `SessionManager.finalizeSession()`:
```swift
print("SESSION FILE: \(SessionRecorder.shared.lastRecordedURL?.path ?? "nil")")
```
Run a session on device. In Xcode Console, confirm a path like `.../Documents/session_1746360000.mov` appears.

- [ ] **Step 2: Verify the file exists using Device File Browser**

In Xcode: `Window → Devices and Simulators → your device → your app → Download Container`. Open the `.xcappdata` bundle, navigate to `AppData/Documents/`. Confirm `session_<timestamp>.mov` exists and has a non-zero file size.

- [ ] **Step 3: Verify VideoPlayerView seeks correctly**

Temporarily hardcode `startSeconds: 5` in the `VideoPlayerView` call in `DetailSheetView`:
```swift
VideoPlayerView(url: event.clipURL!, startSeconds: 5)
```
Run a session using `generateEvents()` mock data (set `debugVideoOverride` to any test video). Tap an event in Results. Confirm the video starts at the 5-second mark.

- [ ] **Step 4: Verify event timestamps seek correctly**

Remove the hardcoded `5` and restore `startSeconds: event.time`. Tap a Yellow or Red event. Confirm the video seeks to that event's elapsed timestamp.

- [ ] **Step 5: Verify session file is deleted on back navigation**

Navigate from Results back to Menu. Use Device File Browser again (re-download container). Confirm `session_<timestamp>.mov` is gone from Documents.

- [ ] **Step 6: Verify Green events show no video**

With real or mock events, tap a Green (`.correct`) event. Confirm `DetailSheetView` shows "No clip — movement was rated Excellent ✅" and no `VideoPlayerView` appears.

- [ ] **Step 7: Verify debug override path**

Set `SessionRecorder.shared.debugVideoOverride = Bundle.main.url(forResource: "sample_session", withExtension: "mov")`. Run the app. Confirm no live recording starts, the analyzer receives the sample URL, and the pipeline completes without error.

- [ ] **Step 8: Remove temporary print statement and commit**

```bash
git add BoxMaxxingFinal/Services/SessionManager.swift
git commit -m "chore: remove debug print from finalizeSession"
```

---

## Remaining TODOs (out of scope — tracked for future)

| Gap | File | Unblocked by |
|---|---|---|
| Sliding window frame extraction + inference (Steps 1–4) | `PostSessionAnalyzer.analyze()` | CoreML `.mlmodel` from dev team |
| Audio cue `.mp3` files | `AudioCuePlayer` | Asset files from developer |
| Correct form reference videos | `DetailSheetView` second `VideoPanel` | Reference `.mp4` files |
