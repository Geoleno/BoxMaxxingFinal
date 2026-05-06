# Wrong Movement Detection & Video Seek Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace SessionEvent-based analysis with a per-frame MovementDetector state machine that stamps CMTime timestamps as WrongMovement values; replace AVAssetExportSession clip files with AVPlayer.seek() on the full session video.

**Architecture:** A new MovementDetector (3-state machine: idle → confirming → cooldown) runs on every camera frame during recording and emits WrongMovement values when a wrong technique or low-confidence movement is confirmed. At session end, finalizeSession() awaits stopRecording() to get the video URL, saves wrongMovements + videoURL once, then ResultsView reads them directly and DetailSheetView uses AVPlayer.seek() to jump to each movement's timestamp.

**Tech Stack:** Swift, SwiftUI, CoreMedia (CMTime), AVFoundation (AVPlayer, AVPlayerItem), AVKit (VideoPlayer)

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `BoxMaxxingFinal/Models.swift` | Add WrongMovement, add CoreMedia import |
| Create | `BoxMaxxingFinal/Services/MovementDetector.swift` | 3-state machine |
| Create | `BoxMaxxingFinalTests/MovementDetectorTests.swift` | Unit tests for detector |
| Modify | `BoxMaxxingFinal/Services/SessionStore.swift` | Add wrongMovements + videoURL (keep old API temporarily) |
| Modify | `BoxMaxxingFinalTests/SessionStoreTests.swift` | New tests for wrongMovements + videoURL |
| Modify | `BoxMaxxingFinal/Services/MLInferenceEngine.swift` | Fix resource name + extension |
| Modify | `BoxMaxxingFinal/RecordingView.swift` | Pass (CVPixelBuffer, CMTime) through onFrame |
| Modify | `BoxMaxxingFinal/Services/SessionManager.swift` | MovementDetector, liveWrongMovements, new finalizeSession |
| Modify | `BoxMaxxingFinal/Services/PostSessionAnalyzer.swift` | Remove extractClips, update analyze stub |
| Modify | `BoxMaxxingFinalTests/PostSessionAnalyzerTests.swift` | Remove buildEvent tests |
| Modify | `BoxMaxxingFinal/ResultsView.swift` | WrongMovement-based stats, AVPlayer detail sheet |
| Modify | `BoxMaxxingFinal/ContentView.swift` | Remove @ObservedObject, pass wrongMovements + videoURL |
| Modify | `BoxMaxxingFinal/Models.swift` (cleanup) | Remove SessionEvent, generateEvents, SessionState extension |
| Modify | `BoxMaxxingFinal/Services/SessionStore.swift` (cleanup) | Remove currentEvents + updateClip + old save |
| Modify | `BoxMaxxingFinal/Services/PostSessionAnalyzer.swift` (cleanup) | Remove buildEvent, update analyze return type |
| Modify | `BoxMaxxingFinal/Utilities/ColorExtensions.swift` (cleanup) | Remove MovementState enum |
| Delete | `BoxMaxxingFinal/Services/MovementAggregator.swift` | No longer used |

---

## Task 1: WrongMovement struct + MovementDetector

**Files:**
- Modify: `BoxMaxxingFinal/Models.swift`
- Create: `BoxMaxxingFinal/Services/MovementDetector.swift`
- Create: `BoxMaxxingFinalTests/MovementDetectorTests.swift`

- [ ] **Step 1: Write the failing tests for MovementDetector**

Create `BoxMaxxingFinalTests/MovementDetectorTests.swift`:

```swift
import XCTest
import CoreMedia
@testable import BoxMaxxingFinal

final class MovementDetectorTests: XCTestCase {

    var detector: MovementDetector!

    override func setUp() {
        super.setUp()
        detector = MovementDetector()
    }

    // MARK: - Helpers

    private func ts(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 600)
    }

    private func pred(_ label: String, _ confidence: Float) -> FramePrediction {
        FramePrediction(label: label, confidence: confidence)
    }

    // MARK: - Idle → Confirming → nil (not yet confirmed)

    func test_idle_validMove_returnsNil() {
        let result = detector.process(prediction: pred("lj", 0.9), timestamp: ts(0.0), expectedMoveId: "rj")
        XCTAssertNil(result)
    }

    func test_idle_invalidLabel_returnsNil() {
        let result = detector.process(prediction: pred("no_body_detected", 0.9), timestamp: ts(0.0), expectedMoveId: "lj")
        XCTAssertNil(result)
    }

    func test_twoFramesSameLabel_returnsNil() {
        _ = detector.process(prediction: pred("rj", 0.9), timestamp: ts(0.0), expectedMoveId: "lj")
        let result = detector.process(prediction: pred("rj", 0.9), timestamp: ts(0.1), expectedMoveId: "lj")
        XCTAssertNil(result)
    }

    // MARK: - Confirmation

    func test_threeFramesWrongTechnique_returnsWrongMovement() {
        _ = detector.process(prediction: pred("rj", 0.9), timestamp: ts(0.0), expectedMoveId: "lj")
        _ = detector.process(prediction: pred("rj", 0.9), timestamp: ts(0.1), expectedMoveId: "lj")
        let result = detector.process(prediction: pred("rj", 0.9), timestamp: ts(0.2), expectedMoveId: "lj")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.detectedMoveId, "rj")
        XCTAssertEqual(result?.expectedMove.id, "lj")
        XCTAssertTrue(result?.isWrongTechnique ?? false)
    }

    func test_threeFramesLowConfidenceCorrectMove_returnsWrongMovement() {
        // detectedMoveId == expectedMoveId but confidence < 0.80 → wrong movement
        _ = detector.process(prediction: pred("lj", 0.5), timestamp: ts(0.0), expectedMoveId: "lj")
        _ = detector.process(prediction: pred("lj", 0.5), timestamp: ts(0.1), expectedMoveId: "lj")
        let result = detector.process(prediction: pred("lj", 0.5), timestamp: ts(0.2), expectedMoveId: "lj")
        XCTAssertNotNil(result)
        XCTAssertFalse(result?.isWrongTechnique ?? true)
        XCTAssertLessThan(result?.confidence ?? 1.0, 0.80)
    }

    func test_threeFramesHighConfidenceCorrectMove_returnsNil() {
        // detectedMoveId == expectedMoveId AND confidence ≥ 0.80 → correct, no emission
        _ = detector.process(prediction: pred("lj", 0.85), timestamp: ts(0.0), expectedMoveId: "lj")
        _ = detector.process(prediction: pred("lj", 0.85), timestamp: ts(0.1), expectedMoveId: "lj")
        let result = detector.process(prediction: pred("lj", 0.85), timestamp: ts(0.2), expectedMoveId: "lj")
        XCTAssertNil(result)
    }

    func test_confirmedMovement_timestampIsFirstFrame() {
        _ = detector.process(prediction: pred("rj", 0.9), timestamp: ts(1.0), expectedMoveId: "lj")
        _ = detector.process(prediction: pred("rj", 0.9), timestamp: ts(1.1), expectedMoveId: "lj")
        let result = detector.process(prediction: pred("rj", 0.9), timestamp: ts(1.2), expectedMoveId: "lj")
        XCTAssertEqual(CMTimeGetSeconds(result?.timestamp ?? .zero), 1.0, accuracy: 0.001)
    }

    func test_confirmedMovement_averagesConfidence() {
        _ = detector.process(prediction: pred("rj", 0.6), timestamp: ts(0.0), expectedMoveId: "lj")
        _ = detector.process(prediction: pred("rj", 0.8), timestamp: ts(0.1), expectedMoveId: "lj")
        let result = detector.process(prediction: pred("rj", 1.0), timestamp: ts(0.2), expectedMoveId: "lj")
        XCTAssertEqual(result?.confidence ?? 0, (0.6 + 0.8 + 1.0) / 3.0, accuracy: 0.001)
    }

    // MARK: - Label change resets to idle

    func test_labelChangeDuringConfirming_resetsToIdle() {
        _ = detector.process(prediction: pred("rj", 0.9), timestamp: ts(0.0), expectedMoveId: "lj")
        _ = detector.process(prediction: pred("lh", 0.9), timestamp: ts(0.1), expectedMoveId: "lj") // different label
        let result = detector.process(prediction: pred("rj", 0.9), timestamp: ts(0.2), expectedMoveId: "lj")
        XCTAssertNil(result) // Only 1 frame with "rj" after reset, not 3
    }

    // MARK: - Cooldown

    func test_cooldown_blocksNextEmissionImmediately() {
        // Confirm a wrong movement
        _ = detector.process(prediction: pred("rj", 0.9), timestamp: ts(0.0), expectedMoveId: "lj")
        _ = detector.process(prediction: pred("rj", 0.9), timestamp: ts(0.1), expectedMoveId: "lj")
        _ = detector.process(prediction: pred("rj", 0.9), timestamp: ts(0.2), expectedMoveId: "lj") // emits

        // Immediately after: 3 more frames should not emit (cooldown active, ~1.5s)
        _ = detector.process(prediction: pred("rh", 0.9), timestamp: ts(0.3), expectedMoveId: "lj")
        _ = detector.process(prediction: pred("rh", 0.9), timestamp: ts(0.4), expectedMoveId: "lj")
        let result = detector.process(prediction: pred("rh", 0.9), timestamp: ts(0.5), expectedMoveId: "lj")
        XCTAssertNil(result)
    }

    func test_cooldown_resumesAfterDuration() {
        // Confirm once at t=0
        _ = detector.process(prediction: pred("rj", 0.9), timestamp: ts(0.0), expectedMoveId: "lj")
        _ = detector.process(prediction: pred("rj", 0.9), timestamp: ts(0.1), expectedMoveId: "lj")
        _ = detector.process(prediction: pred("rj", 0.9), timestamp: ts(0.2), expectedMoveId: "lj") // emits

        // Frames during cooldown (< 1.5s from t=0.2) return nil
        _ = detector.process(prediction: pred("lh", 0.9), timestamp: ts(1.0), expectedMoveId: "lj")

        // After cooldown ends (t=0.2+1.5 = 1.7), a fresh 3-frame confirmation should emit
        _ = detector.process(prediction: pred("lh", 0.9), timestamp: ts(1.8), expectedMoveId: "lj") // cooldown expired
        _ = detector.process(prediction: pred("lh", 0.9), timestamp: ts(1.9), expectedMoveId: "lj")
        let result = detector.process(prediction: pred("lh", 0.9), timestamp: ts(2.0), expectedMoveId: "lj")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.detectedMoveId, "lh")
    }

    // MARK: - Reset

    func test_reset_clearsState() {
        _ = detector.process(prediction: pred("rj", 0.9), timestamp: ts(0.0), expectedMoveId: "lj")
        _ = detector.process(prediction: pred("rj", 0.9), timestamp: ts(0.1), expectedMoveId: "lj")
        detector.reset()
        // After reset, needs 3 fresh frames
        _ = detector.process(prediction: pred("rj", 0.9), timestamp: ts(0.2), expectedMoveId: "lj")
        _ = detector.process(prediction: pred("rj", 0.9), timestamp: ts(0.3), expectedMoveId: "lj")
        let result = detector.process(prediction: pred("rj", 0.9), timestamp: ts(0.4), expectedMoveId: "lj")
        XCTAssertNotNil(result) // Still emits after 3 fresh frames
    }
}
```

- [ ] **Step 2: Run tests — expect build failure (types not defined yet)**

```bash
xcodebuild test \
  -project /Users/michael/Projects/BoxMaxxingFinal/BoxMaxxingFinal.xcodeproj \
  -scheme BoxMaxxingFinal \
  -destination 'platform=iOS Simulator,name=iPhone 16e' \
  -only-testing:BoxMaxxingFinalTests/MovementDetectorTests \
  2>&1 | grep -E '(error:|Build FAILED|No such module)'
```

Expected: Build error — `MovementDetector`, `WrongMovement` not found.

- [ ] **Step 3: Add WrongMovement to Models.swift**

In `BoxMaxxingFinal/Models.swift`, add `import CoreMedia` at the top (after `import Foundation`) and add the `WrongMovement` struct after the `LivePunch` struct:

```swift
import Foundation
import CoreMedia
import Vision
```

After the `LivePunch` struct (after line 85, before `// MARK: - Window Result`):

```swift
// MARK: - Wrong Movement

struct WrongMovement: Identifiable {
    let id = UUID()
    let timestamp: CMTime
    let expectedMove: Move
    let detectedMoveId: String
    let confidence: Float

    var isWrongTechnique: Bool { detectedMoveId != expectedMove.id }
}
```

- [ ] **Step 4: Create MovementDetector.swift**

Create `BoxMaxxingFinal/Services/MovementDetector.swift`:

```swift
import CoreMedia

final class MovementDetector {

    private enum State {
        case idle
        case confirming(label: String, frames: Int, firstTimestamp: CMTime, confidenceSum: Float)
        case cooldown(until: CMTime)
    }

    private var state: State = .idle
    private let confirmFrames = 3
    private let cooldownSeconds: Double = 1.5
    private let correctThreshold: Float = 0.80

    func reset() { state = .idle }

    func process(prediction: FramePrediction,
                 timestamp: CMTime,
                 expectedMoveId: String) -> WrongMovement? {

        let isValidMove = findMove(prediction.label) != nil

        switch state {
        case .idle:
            guard isValidMove else { return nil }
            state = .confirming(label: prediction.label, frames: 1,
                                firstTimestamp: timestamp,
                                confidenceSum: prediction.confidence)
            return nil

        case .confirming(let label, let frames, let firstTimestamp, let confidenceSum):
            guard isValidMove, prediction.label == label else {
                state = .idle
                return nil
            }
            let newFrames = frames + 1
            let newSum    = confidenceSum + prediction.confidence
            guard newFrames >= confirmFrames else {
                state = .confirming(label: label, frames: newFrames,
                                    firstTimestamp: firstTimestamp,
                                    confidenceSum: newSum)
                return nil
            }
            let avgConfidence = newSum / Float(newFrames)
            let cooldownEnd   = CMTimeAdd(timestamp,
                                          CMTime(seconds: cooldownSeconds, preferredTimescale: 600))
            state = .cooldown(until: cooldownEnd)
            let matched = (label == expectedMoveId) && avgConfidence >= correctThreshold
            guard !matched, let expectedMove = findMove(expectedMoveId) else { return nil }
            return WrongMovement(timestamp: firstTimestamp,
                                 expectedMove: expectedMove,
                                 detectedMoveId: label,
                                 confidence: avgConfidence)

        case .cooldown(let until):
            if CMTimeCompare(timestamp, until) >= 0 {
                state = .idle
                if isValidMove {
                    state = .confirming(label: prediction.label, frames: 1,
                                        firstTimestamp: timestamp,
                                        confidenceSum: prediction.confidence)
                }
            }
            return nil
        }
    }
}
```

- [ ] **Step 5: Run tests — expect all pass**

```bash
xcodebuild test \
  -project /Users/michael/Projects/BoxMaxxingFinal/BoxMaxxingFinal.xcodeproj \
  -scheme BoxMaxxingFinal \
  -destination 'platform=iOS Simulator,name=iPhone 16e' \
  -only-testing:BoxMaxxingFinalTests/MovementDetectorTests \
  2>&1 | grep -E '(Test Case|passed|failed|error:|Build FAILED|Executed)'
```

Expected: All 14 tests pass.

- [ ] **Step 6: Verify the full build still compiles**

```bash
xcodebuild build \
  -project /Users/michael/Projects/BoxMaxxingFinal/BoxMaxxingFinal.xcodeproj \
  -scheme BoxMaxxingFinal \
  -destination 'platform=iOS Simulator,name=iPhone 16e' \
  2>&1 | grep -E '(error:|Build FAILED|Build SUCCEEDED)'
```

Expected: `Build SUCCEEDED`.

- [ ] **Step 7: Commit**

```bash
git add BoxMaxxingFinal/Models.swift \
        BoxMaxxingFinal/Services/MovementDetector.swift \
        BoxMaxxingFinalTests/MovementDetectorTests.swift
git commit -m "feat: add WrongMovement struct and MovementDetector state machine"
```

---

## Task 2: Add new SessionStore API

**Files:**
- Modify: `BoxMaxxingFinal/Services/SessionStore.swift`
- Modify: `BoxMaxxingFinalTests/SessionStoreTests.swift`

This task adds `wrongMovements: [WrongMovement]` and `videoURL: URL?` to SessionStore alongside the existing API. The old API (`currentEvents`, `updateClip`, old `save`) is **not removed yet** — that happens in Task 7. This keeps the build green while downstream consumers are migrated one at a time.

- [ ] **Step 1: Write failing tests for new SessionStore API**

Replace `BoxMaxxingFinalTests/SessionStoreTests.swift` entirely:

```swift
import XCTest
import CoreMedia
@testable import BoxMaxxingFinal

@MainActor
final class SessionStoreTests: XCTestCase {

    override func setUp() {
        super.setUp()
        SessionStore.shared.clear()
    }

    // MARK: - New API: wrongMovements + videoURL

    func test_saveMovements_storesWrongMovements() {
        let m = WrongMovement(timestamp: CMTime(seconds: 5, preferredTimescale: 600),
                              expectedMove: allMoves[0],
                              detectedMoveId: "rj",
                              confidence: 0.9)
        SessionStore.shared.save(movements: [m], videoURL: nil, startDate: Date(), duration: 60)
        XCTAssertEqual(SessionStore.shared.wrongMovements.count, 1)
        XCTAssertEqual(SessionStore.shared.wrongMovements[0].detectedMoveId, "rj")
    }

    func test_saveMovements_storesVideoURL() {
        let url = URL(fileURLWithPath: "/tmp/session.mov")
        SessionStore.shared.save(movements: [], videoURL: url, startDate: Date(), duration: 60)
        XCTAssertEqual(SessionStore.shared.videoURL, url)
    }

    func test_saveMovements_nilVideoURL_storesNil() {
        SessionStore.shared.save(movements: [], videoURL: nil, startDate: Date(), duration: 60)
        XCTAssertNil(SessionStore.shared.videoURL)
    }

    func test_clear_resetsWrongMovementsAndVideoURL() {
        let url = URL(fileURLWithPath: "/tmp/session.mov")
        let m = WrongMovement(timestamp: CMTime(seconds: 1, preferredTimescale: 600),
                              expectedMove: allMoves[0],
                              detectedMoveId: "lj",
                              confidence: 0.5)
        SessionStore.shared.save(movements: [m], videoURL: url, startDate: Date(), duration: 60)
        SessionStore.shared.clear()
        XCTAssertTrue(SessionStore.shared.wrongMovements.isEmpty)
        XCTAssertNil(SessionStore.shared.videoURL)
    }

    func test_saveMovements_multipleMovements_preservesOrder() {
        let m1 = WrongMovement(timestamp: CMTime(seconds: 1, preferredTimescale: 600),
                               expectedMove: allMoves[0], detectedMoveId: "rj", confidence: 0.9)
        let m2 = WrongMovement(timestamp: CMTime(seconds: 2, preferredTimescale: 600),
                               expectedMove: allMoves[1], detectedMoveId: "lh", confidence: 0.7)
        SessionStore.shared.save(movements: [m1, m2], videoURL: nil, startDate: Date(), duration: 60)
        XCTAssertEqual(SessionStore.shared.wrongMovements.count, 2)
        XCTAssertEqual(SessionStore.shared.wrongMovements[1].detectedMoveId, "lh")
    }
}
```

- [ ] **Step 2: Run tests — expect failures**

```bash
xcodebuild test \
  -project /Users/michael/Projects/BoxMaxxingFinal/BoxMaxxingFinal.xcodeproj \
  -scheme BoxMaxxingFinal \
  -destination 'platform=iOS Simulator,name=iPhone 16e' \
  -only-testing:BoxMaxxingFinalTests/SessionStoreTests \
  2>&1 | grep -E '(Test Case|passed|failed|error:|Build FAILED|Executed)'
```

Expected: Compile error — `save(movements:videoURL:startDate:duration:)` and `wrongMovements` not found.

- [ ] **Step 3: Add new properties and method to SessionStore**

In `BoxMaxxingFinal/Services/SessionStore.swift`, add `import CoreMedia` and the new published properties and save method. Keep all existing code. The file becomes:

```swift
import Foundation
import Combine
import CoreMedia

final class SessionStore: ObservableObject {
    static let shared = SessionStore()
    private init() {}

    // New API
    @Published private(set) var wrongMovements: [WrongMovement] = []
    private(set) var videoURL: URL?

    // Old API — kept until Task 7 cleanup
    @Published private(set) var currentEvents: [SessionEvent] = []
    private(set) var sessionStartDate: Date?
    private(set) var sessionDuration: TimeInterval = 0

    @MainActor
    func save(movements: [WrongMovement], videoURL: URL?,
              startDate: Date, duration: TimeInterval) {
        wrongMovements       = movements
        self.videoURL        = videoURL
        sessionStartDate     = startDate
        sessionDuration      = duration
    }

    @MainActor
    func save(events: [SessionEvent], startDate: Date, duration: TimeInterval) {
        currentEvents    = events
        sessionStartDate = startDate
        sessionDuration  = duration
    }

    @MainActor
    func updateClip(eventId: String, url: URL) {
        guard let idx = currentEvents.firstIndex(where: { $0.id == eventId }) else { return }
        let old = currentEvents[idx]
        currentEvents[idx] = SessionEvent(
            id: old.id, time: old.time, move: old.move,
            status: old.status, confidence: old.confidence,
            detectedAs: old.detectedAs, note: old.note,
            clipURL: url
        )
    }

    @MainActor
    func clear() {
        wrongMovements   = []
        videoURL         = nil
        currentEvents    = []
        sessionStartDate = nil
        sessionDuration  = 0
    }
}
```

- [ ] **Step 4: Run new tests — expect all pass**

```bash
xcodebuild test \
  -project /Users/michael/Projects/BoxMaxxingFinal/BoxMaxxingFinal.xcodeproj \
  -scheme BoxMaxxingFinal \
  -destination 'platform=iOS Simulator,name=iPhone 16e' \
  -only-testing:BoxMaxxingFinalTests/SessionStoreTests \
  2>&1 | grep -E '(Test Case|passed|failed|error:|Build FAILED|Executed)'
```

Expected: All 5 new tests pass.

- [ ] **Step 5: Verify full build**

```bash
xcodebuild build \
  -project /Users/michael/Projects/BoxMaxxingFinal/BoxMaxxingFinal.xcodeproj \
  -scheme BoxMaxxingFinal \
  -destination 'platform=iOS Simulator,name=iPhone 16e' \
  2>&1 | grep -E '(error:|Build FAILED|Build SUCCEEDED)'
```

Expected: `Build SUCCEEDED`.

- [ ] **Step 6: Commit**

```bash
git add BoxMaxxingFinal/Services/SessionStore.swift \
        BoxMaxxingFinalTests/SessionStoreTests.swift
git commit -m "feat: add wrongMovements and videoURL to SessionStore"
```

---

## Task 3: Fix MLInferenceEngine model loading

**Files:**
- Modify: `BoxMaxxingFinal/Services/MLInferenceEngine.swift`

The model file in the bundle is `80_epoch.mlmodelc` (underscore, compiled extension). The current code uses `"80 epoch"` and `"mlmodel"` — both wrong, causing the model to never load.

- [ ] **Step 1: Fix the resource name and extension**

In `BoxMaxxingFinal/Services/MLInferenceEngine.swift`, in `loadModel()`, change:

```swift
// Before:
guard let url = Bundle.main.url(forResource: "80 epoch", withExtension: "mlmodel") else {
```

to:

```swift
// After:
guard let url = Bundle.main.url(forResource: "80_epoch", withExtension: "mlmodelc") else {
```

- [ ] **Step 2: Verify the build succeeds**

```bash
xcodebuild build \
  -project /Users/michael/Projects/BoxMaxxingFinal/BoxMaxxingFinal.xcodeproj \
  -scheme BoxMaxxingFinal \
  -destination 'platform=iOS Simulator,name=iPhone 16e' \
  2>&1 | grep -E '(error:|Build FAILED|Build SUCCEEDED)'
```

Expected: `Build SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add BoxMaxxingFinal/Services/MLInferenceEngine.swift
git commit -m "fix: correct model bundle resource name to 80_epoch.mlmodelc"
```

---

## Task 4: CameraView timestamp passthrough + SessionManager rewrite

**Files:**
- Modify: `BoxMaxxingFinal/RecordingView.swift`
- Modify: `BoxMaxxingFinal/Services/SessionManager.swift`

CameraView currently passes only `CVPixelBuffer` to `onFrame`. We need to also pass the `CMTime` presentation timestamp from the sample buffer — this is the same timestamp written to the movie file, so AVPlayer.seek() will land on the exact frame. SessionManager is rewritten to use MovementDetector, liveWrongMovements, and the new finalizeSession.

- [ ] **Step 1: Update CameraView and CameraPreviewView to pass CMTime**

In `BoxMaxxingFinal/RecordingView.swift`, make three changes:

**Change 1** — `CameraPreviewView` struct (around line 129):
```swift
// Before:
struct CameraPreviewView: UIViewRepresentable {
    var onFrame: ((CVPixelBuffer) -> Void)?

    func makeUIView(context: Context) -> CameraView {
        let view = CameraView()
        view.onFrame = onFrame
        return view
    }
    func updateUIView(_ uiView: CameraView, context: Context) {
        uiView.onFrame = onFrame
    }
}
```

```swift
// After:
struct CameraPreviewView: UIViewRepresentable {
    var onFrame: ((CVPixelBuffer, CMTime) -> Void)?

    func makeUIView(context: Context) -> CameraView {
        let view = CameraView()
        view.onFrame = onFrame
        return view
    }
    func updateUIView(_ uiView: CameraView, context: Context) {
        uiView.onFrame = onFrame
    }
}
```

**Change 2** — `CameraView` class property and delegate method (around line 142):
```swift
// Before:
final class CameraView: UIView, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onFrame: ((CVPixelBuffer) -> Void)?
    ...
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(pixelBuffer)
    }
```

```swift
// After:
final class CameraView: UIView, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onFrame: ((CVPixelBuffer, CMTime) -> Void)?
    ...
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = sampleBuffer.presentationTimeStamp
        onFrame?(pixelBuffer, pts)
    }
```

**Change 3** — `RecordingView.body` call site (around line 28):
```swift
// Before:
CameraPreviewView(onFrame: { [sessionManager] buffer in
    sessionManager.processFrame(buffer)
})
```

```swift
// After:
CameraPreviewView(onFrame: { [sessionManager] buffer, timestamp in
    sessionManager.processFrame(buffer, timestamp: timestamp)
})
```

- [ ] **Step 2: Rewrite SessionManager**

Replace `BoxMaxxingFinal/Services/SessionManager.swift` entirely:

```swift
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

        isRecording      = false
        currentSkeleton  = nil
        currentTargetMove = nil
        lastWindowResult = nil
        isAnalyzing      = true

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
```

- [ ] **Step 3: Build to confirm no compile errors**

```bash
xcodebuild build \
  -project /Users/michael/Projects/BoxMaxxingFinal/BoxMaxxingFinal.xcodeproj \
  -scheme BoxMaxxingFinal \
  -destination 'platform=iOS Simulator,name=iPhone 16e' \
  2>&1 | grep -E '(error:|Build FAILED|Build SUCCEEDED)'
```

Expected: `Build SUCCEEDED`. (ContentView still passes `store.currentEvents` to ResultsView — that still compiles because both old API props still exist in SessionStore.)

- [ ] **Step 4: Commit**

```bash
git add BoxMaxxingFinal/RecordingView.swift \
        BoxMaxxingFinal/Services/SessionManager.swift
git commit -m "feat: wire CMTime through camera frames, switch SessionManager to MovementDetector"
```

---

## Task 5: PostSessionAnalyzer cleanup

**Files:**
- Modify: `BoxMaxxingFinal/Services/PostSessionAnalyzer.swift`
- Modify: `BoxMaxxingFinalTests/PostSessionAnalyzerTests.swift`

Remove `extractClips()` (no longer called). Remove `buildEvent()` (returns SessionEvent which will be removed). Update `analyze()` to return `[WrongMovement]` (still a stub). Keep `groupWindows()` and `selectRepresentative()` — they use only `WindowPrediction` and have passing tests.

- [ ] **Step 1: Remove buildEvent tests from PostSessionAnalyzerTests**

In `BoxMaxxingFinalTests/PostSessionAnalyzerTests.swift`, delete the entire `// MARK: - buildEvent` section (lines 73–107). Keep `groupWindows` and `selectRepresentative` test sections. The file should look like:

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
        let p1 = WindowPrediction(label: "lj", confidence: 0.6, startTime: 0.0, endTime: 2.0)
        let p2 = WindowPrediction(label: "lj", confidence: 0.7, startTime: 2.3, endTime: 4.3)
        let groups = analyzer.groupWindows([p1, p2])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].count, 2)
    }

    func test_groupWindows_sameLabelLargeGap_splitIntoTwoGroups() {
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
}
```

- [ ] **Step 2: Update PostSessionAnalyzer.swift**

Replace `BoxMaxxingFinal/Services/PostSessionAnalyzer.swift` entirely:

```swift
import AVFoundation
import Vision
import Foundation

struct WindowPrediction: Equatable {
    let label: String
    let confidence: Float
    let startTime: Double
    let endTime: Double
}

final class PostSessionAnalyzer {

    static let shared = PostSessionAnalyzer()
    private init() {}

    let clipPaddingSeconds: Double = 0.5
    let windowSize = 60
    let strideSize  = 15

    func analyze(videoURL: URL) async -> [WrongMovement] {
        return []
    }

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

    func selectRepresentative(from group: [WindowPrediction]) -> WindowPrediction {
        group.max(by: { $0.confidence < $1.confidence })!
    }
}
```

- [ ] **Step 3: Run PostSessionAnalyzer tests**

```bash
xcodebuild test \
  -project /Users/michael/Projects/BoxMaxxingFinal/BoxMaxxingFinal.xcodeproj \
  -scheme BoxMaxxingFinal \
  -destination 'platform=iOS Simulator,name=iPhone 16e' \
  -only-testing:BoxMaxxingFinalTests/PostSessionAnalyzerTests \
  2>&1 | grep -E '(Test Case|passed|failed|error:|Build FAILED|Executed)'
```

Expected: All 7 remaining tests pass.

- [ ] **Step 4: Full build check**

```bash
xcodebuild build \
  -project /Users/michael/Projects/BoxMaxxingFinal/BoxMaxxingFinal.xcodeproj \
  -scheme BoxMaxxingFinal \
  -destination 'platform=iOS Simulator,name=iPhone 16e' \
  2>&1 | grep -E '(error:|Build FAILED|Build SUCCEEDED)'
```

Expected: `Build SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add BoxMaxxingFinal/Services/PostSessionAnalyzer.swift \
        BoxMaxxingFinalTests/PostSessionAnalyzerTests.swift
git commit -m "refactor: remove extractClips and buildEvent from PostSessionAnalyzer"
```

---

## Task 6: ResultsView + DetailSheetView + ContentView

**Files:**
- Modify: `BoxMaxxingFinal/ResultsView.swift`
- Modify: `BoxMaxxingFinal/ContentView.swift`

ResultsView gets a new signature `(wrongMovements: [WrongMovement], videoURL: URL?)`. The stats row shows wrong count, bad-technique count, avg confidence. The timeline shows only wrong movements (all items in the list are problems). DetailSheetView gets PlayerHolder with AVPlayer that seeks to movement.timestamp − 0.5s. ContentView removes @ObservedObject and passes the new params.

- [ ] **Step 1: Replace ResultsView.swift**

Replace `BoxMaxxingFinal/ResultsView.swift` entirely with:

```swift
import SwiftUI
import AVKit
import AVFoundation
import CoreMedia

struct ResultsView: View {
    let state: SessionState
    let wrongMovements: [WrongMovement]
    let videoURL: URL?
    let onBack: () -> Void

    @State private var activeMovement: WrongMovement? = nil

    private var total: Int { state.sessionLength * 60 }
    private var wrongCount: Int       { wrongMovements.count }
    private var badTechniqueCount: Int { wrongMovements.filter { $0.isWrongTechnique }.count }
    private var avgConf: Int {
        guard !wrongMovements.isEmpty else { return 0 }
        let sum = wrongMovements.reduce(0.0) { $0 + Double($1.confidence) }
        return Int(sum / Double(wrongMovements.count) * 100)
    }

    var body: some View {
        VStack(spacing: 0) {
            navBar

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Session Review")
                            .font(.system(size: 34, weight: .bold))
                            .tracking(0.37)
                        Text("\(formatTime(total)) · \(state.selectedMoveIds.count) moves")
                            .font(.system(size: 15, design: .monospaced))
                            .monospacedDigit()
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            .tracking(-0.24)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 8)

                    HStack(spacing: 8) {
                        StatCard(label: "Wrong",         value: "\(wrongCount)",        color: Color(UIColor.systemRed))
                        StatCard(label: "Bad technique", value: "\(badTechniqueCount)", color: Color(UIColor.systemOrange))
                        StatCard(label: "Avg Conf",      value: "\(avgConf)%",          color: Color(UIColor.label))
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)

                    HStack {
                        Text("Timeline")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            .tracking(-0.08)
                        Spacer()
                        HStack(spacing: 12) {
                            LegendDot(color: Color(UIColor.systemRed),    label: "Wrong technique")
                            LegendDot(color: Color(UIColor.systemOrange), label: "Bad execution")
                        }
                        .font(.system(size: 13))
                        .foregroundColor(Color(UIColor.secondaryLabel))
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 6)

                    WrongMovementTimelineView(
                        movements: wrongMovements,
                        total: total,
                        onOpenMovement: { activeMovement = $0 }
                    )
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 30)
            }
        }
        .background(Color(UIColor.systemBackground))
        .ignoresSafeArea(edges: .bottom)
        .sheet(item: $activeMovement) { movement in
            DetailSheetView(movement: movement, videoURL: videoURL)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var navBar: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Menu")
                        .font(.system(size: 17, weight: .regular))
                        .tracking(-0.4)
                }
                .foregroundColor(Color(UIColor.systemRed))
            }
            .padding(8)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .frame(minHeight: 44)
    }
}

// MARK: - Timeline

private struct WrongMovementTimelineView: View {
    let movements: [WrongMovement]
    let total: Int
    let onOpenMovement: (WrongMovement) -> Void

    private let dotCenter: CGFloat = 14
    private let dotSize: CGFloat   = 14
    private let rowSpacing: CGFloat = 12

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color(UIColor.separator))
                .frame(width: 2)
                .padding(.leading, dotCenter - 1)
                .padding(.top, dotSize / 2)
                .padding(.bottom, dotSize / 2)

            VStack(alignment: .leading, spacing: 0) {
                endpointRow(time: "00:00", label: "Start")

                ForEach(movements) { movement in
                    movementRow(movement)
                        .padding(.vertical, rowSpacing)
                }

                endpointRow(time: formatTime(total), label: "End")
                    .padding(.top, 4)
            }
        }
    }

    private func endpointRow(time: String, label: String) -> some View {
        HStack(spacing: 10) {
            Circle()
                .stroke(Color(UIColor.tertiaryLabel), lineWidth: 2)
                .frame(width: dotSize, height: dotSize)
                .background(Circle().fill(Color(UIColor.systemBackground)))
                .padding(.leading, dotCenter - dotSize / 2)
            HStack(spacing: 0) {
                Text(time)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .tracking(-0.08)
                Text(" · \(label)")
                    .font(.system(size: 13, weight: .medium))
                    .tracking(-0.08)
            }
            .foregroundColor(Color(UIColor.secondaryLabel))
        }
    }

    private func movementRow(_ movement: WrongMovement) -> some View {
        let accent: Color = movement.isWrongTechnique ? Color(UIColor.systemRed) : Color(UIColor.systemOrange)
        let statusLabel   = movement.isWrongTechnique ? "Wrong technique" : "Bad execution"
        let secs          = Int(CMTimeGetSeconds(movement.timestamp))

        return HStack(spacing: 7) {
            Circle()
                .stroke(accent, lineWidth: 3)
                .frame(width: dotSize, height: dotSize)
                .background(Circle().fill(Color(UIColor.systemBackground)))
                .padding(.leading, dotCenter - dotSize / 2)

            Button(action: { onOpenMovement(movement) }) {
                HStack(spacing: 12) {
                    MoveGlyphView(kind: movement.expectedMove.kind,
                                  side: movement.expectedMove.side,
                                  color: Color(UIColor.label), size: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(movement.expectedMove.name)
                            .font(.system(size: 16, weight: .semibold))
                            .tracking(-0.32)
                            .foregroundColor(Color(UIColor.label))
                        HStack(spacing: 0) {
                            Text(statusLabel)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(accent)
                            Text(" · \(Int(movement.confidence * 100))%")
                                .font(.system(size: 13))
                                .foregroundColor(Color(UIColor.secondaryLabel))
                        }
                        .tracking(-0.08)
                    }
                    Spacer(minLength: 0)
                    Text(formatTime(secs))
                        .font(.system(size: 15, design: .monospaced))
                        .monospacedDigit()
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .tracking(-0.08)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(UIColor.tertiaryLabel))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color(UIColor.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(Color(UIColor.secondaryLabel))
                .tracking(-0.08)
            Text(value)
                .font(.system(size: 28, weight: .bold))
                .monospacedDigit()
                .foregroundColor(color)
                .tracking(0.34)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Legend Dot

private struct LegendDot: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
        }
    }
}

// MARK: - Detail Sheet

struct DetailSheetView: View {
    let movement: WrongMovement
    let videoURL: URL?
    @StateObject private var playerHolder = PlayerHolder()
    @Environment(\.dismiss) private var dismiss

    private var accent: Color {
        Color.performanceColor(for: movement.confidence)
    }

    private var statusLabel: String {
        movement.isWrongTechnique ? "Wrong technique" : Color.performanceLabel(for: movement.confidence)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                VStack(spacing: 2) {
                    Text("Movement Detail")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(UIColor.label))
                    Text("at \(formatTime(Int(CMTimeGetSeconds(movement.timestamp))))")
                        .font(.system(size: 13, design: .monospaced))
                        .monospacedDigit()
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
                .padding(.bottom, 20)

                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(accent.opacity(0.12))
                            .frame(width: 64, height: 64)
                        MoveGlyphView(kind: movement.expectedMove.kind,
                                      side: movement.expectedMove.side,
                                      color: accent, size: 34)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(movement.expectedMove.name)
                            .font(.system(size: 24, weight: .bold))
                            .tracking(0.2)
                        HStack(spacing: 6) {
                            moveBadge(movement.expectedMove.side == .left ? "Left" : "Right")
                            moveBadge(kindLabel(movement.expectedMove.kind))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 20)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        HStack(spacing: 6) {
                            Circle().fill(accent).frame(width: 8, height: 8)
                            Text(statusLabel)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(accent)
                        }
                        Spacer()
                        Text("\(Int(movement.confidence * 100))% confidence")
                            .font(.system(size: 15, design: .monospaced))
                            .monospacedDigit()
                            .foregroundColor(Color(UIColor.secondaryLabel))
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(UIColor.secondarySystemFill))
                            RoundedRectangle(cornerRadius: 4)
                                .fill(accent)
                                .frame(width: geo.size.width * CGFloat(movement.confidence))
                        }
                    }
                    .frame(height: 8)
                    HStack {
                        Text("0%"); Spacer(); Text("50%"); Spacer(); Text("100%")
                    }
                    .font(.system(size: 11))
                    .foregroundColor(Color(UIColor.tertiaryLabel))
                }
                .padding(16)
                .background(Color(UIColor.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.bottom, 16)

                if movement.isWrongTechnique,
                   let detectedName = findMove(movement.detectedMoveId)?.name {
                    detectionMismatchBlock(expected: movement.expectedMove.name, detected: detectedName)
                        .padding(.bottom, 16)
                }

                if let url = videoURL {
                    SectionLabel("Your clip")
                    VideoPlayer(player: playerHolder.player)
                        .aspectRatio(9/16, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.bottom, 20)
                        .onAppear {
                            playerHolder.load(url: url, seekTo: movement.timestamp)
                        }
                        .onDisappear { playerHolder.player.pause() }
                }

                SectionLabel("Coach note")
                Text(PerformanceFeedback.suggestion(for: movement.expectedMove.id))
                    .font(.system(size: 15))
                    .foregroundColor(Color(UIColor.label))
                    .tracking(-0.24)
                    .lineSpacing(4)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(UIColor.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.bottom, 20)

                SectionLabel("Form checklist")
                formChecklist(for: movement.expectedMove.kind)
                    .padding(.bottom, 40)
            }
            .padding(.horizontal, 20)
        }
    }

    private func moveBadge(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.5)
            .foregroundColor(Color(UIColor.secondaryLabel))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(UIColor.tertiarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func detectionMismatchBlock(expected: String, detected: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Detection mismatch")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(UIColor.secondaryLabel))
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Expected").font(.system(size: 11)).foregroundColor(Color(UIColor.tertiaryLabel))
                    Text(expected).font(.system(size: 15, weight: .semibold)).foregroundColor(Color(UIColor.label))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(UIColor.tertiaryLabel))
                    .padding(.horizontal, 12)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Detected as").font(.system(size: 11)).foregroundColor(Color(UIColor.tertiaryLabel))
                    Text(detected).font(.system(size: 15, weight: .semibold)).foregroundColor(Color(UIColor.systemRed))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(Color(UIColor.systemRed).opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func formChecklist(for kind: Move.MoveKind) -> some View {
        let cues = formCues(for: kind)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(cues.enumerated()), id: \.offset) { i, cue in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(accent)
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cue.title)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Color(UIColor.label))
                        Text(cue.detail)
                            .font(.system(size: 13))
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                if i < cues.count - 1 {
                    Divider().padding(.leading, 42)
                }
            }
        }
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func kindLabel(_ kind: Move.MoveKind) -> String {
        switch kind {
        case .jab: return "Jab"
        case .hook: return "Hook"
        case .uppercut: return "Uppercut"
        }
    }

    private struct FormCue { let title: String; let detail: String }

    private func formCues(for kind: Move.MoveKind) -> [FormCue] {
        switch kind {
        case .jab:
            return [
                FormCue(title: "Full extension",  detail: "Extend your arm completely and snap the wrist on impact — a half-extended jab loses both speed and power."),
                FormCue(title: "Chin down",        detail: "Keep your chin tucked behind your lead shoulder throughout the punch to protect your jaw."),
                FormCue(title: "Quick retraction", detail: "Pull the fist back along the exact same line it traveled out — this resets your guard and sets up the next punch."),
            ]
        case .hook:
            return [
                FormCue(title: "Pivot the lead foot", detail: "Rotate on the ball of your foot as you throw — hip rotation is the main power source for the hook."),
                FormCue(title: "Elbow parallel",      detail: "Keep the elbow at shoulder height and parallel to the floor. High or low elbows telegraph the punch and reduce power."),
                FormCue(title: "Rear hand stays up",  detail: "Keep the rear glove high on your cheek while the lead arm swings — don't leave your head exposed."),
            ]
        case .uppercut:
            return [
                FormCue(title: "Dip the shoulder first", detail: "Lower your same-side shoulder slightly before driving up — this loads the punch and hides the tell."),
                FormCue(title: "Drive with the legs",    detail: "Push through the floor and extend the knees. Power comes from the ground up, not from the arm alone."),
                FormCue(title: "Tight elbow path",       detail: "Keep the elbow close to your body as the fist rises — a wide elbow wastes energy and exposes your ribs."),
            ]
        }
    }
}

// MARK: - PlayerHolder

final class PlayerHolder: ObservableObject {
    let player = AVPlayer()

    func load(url: URL, seekTo time: CMTime) {
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        let offset   = CMTime(seconds: 0.5, preferredTimescale: 600)
        let seekTime = CMTimeMaximum(CMTimeSubtract(time, offset), .zero)
        player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            self.player.play()
        }
    }
}

// MARK: - Helpers

private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .regular))
            .foregroundColor(Color(UIColor.secondaryLabel))
            .tracking(-0.08)
            .padding(.bottom, 8)
    }
}

#Preview {
    ContentView()
}
```

- [ ] **Step 2: Update ContentView.swift**

Replace `BoxMaxxingFinal/ContentView.swift` entirely:

```swift
import SwiftUI

enum AppRoute {
    case menu, record, results
}

struct ContentView: View {
    @State private var route: AppRoute = .menu
    @State private var sessionState = SessionState()
    @StateObject private var sessionManager = SessionManager()

    var body: some View {
        ZStack {
            switch route {
            case .menu:
                MenuView(state: $sessionState, onStart: {
                    if let comboId = sessionState.selectedComboId,
                       let combo = allCombos.first(where: { $0.id == comboId }) {
                        sessionManager.configure(combo: combo)
                    }
                    withAnimation(.easeInOut(duration: 0.25)) { route = .record }
                }, onTestVideo: { _ in
                    withAnimation(.easeInOut(duration: 0.25)) { route = .results }
                })
                .transition(.opacity)

            case .record:
                RecordingView(
                    state: sessionState,
                    onFinish: {
                        withAnimation(.easeInOut(duration: 0.25)) { route = .results }
                    },
                    onCancel: {
                        withAnimation(.easeInOut(duration: 0.25)) { route = .menu }
                    }
                )
                .environmentObject(sessionManager)
                .transition(.opacity)

            case .results:
                ResultsView(
                    state: sessionState,
                    wrongMovements: SessionStore.shared.wrongMovements,
                    videoURL: SessionStore.shared.videoURL,
                    onBack: {
                        SessionRecorder.shared.deleteSessionFile()
                        SessionStore.shared.clear()
                        withAnimation(.easeInOut(duration: 0.25)) { route = .menu }
                    }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: route)
        .onAppear {
            SessionRecorder.shared.deleteSessionFile()
        }
    }
}

#Preview {
    ContentView()
}
```

- [ ] **Step 3: Build to confirm no compile errors**

```bash
xcodebuild build \
  -project /Users/michael/Projects/BoxMaxxingFinal/BoxMaxxingFinal.xcodeproj \
  -scheme BoxMaxxingFinal \
  -destination 'platform=iOS Simulator,name=iPhone 16e' \
  2>&1 | grep -E '(error:|Build FAILED|Build SUCCEEDED)'
```

Expected: `Build SUCCEEDED`. (The old SessionEvent/currentEvents types still exist, so nothing is broken yet.)

- [ ] **Step 4: Commit**

```bash
git add BoxMaxxingFinal/ResultsView.swift \
        BoxMaxxingFinal/ContentView.swift
git commit -m "feat: ResultsView and DetailSheetView use WrongMovement and AVPlayer.seek()"
```

---

## Task 7: Cleanup — remove dead code

**Files:**
- Modify: `BoxMaxxingFinal/Models.swift`
- Modify: `BoxMaxxingFinal/Services/SessionStore.swift`
- Modify: `BoxMaxxingFinal/Utilities/ColorExtensions.swift`
- Delete: `BoxMaxxingFinal/Services/MovementAggregator.swift`

Now that all consumers have been migrated, we remove the old API:
- `SessionEvent` struct + extension (from Models.swift)
- `generateEvents()` function (from Models.swift)
- `SessionState` extension referencing `currentEvents` (from Models.swift)
- `MovementState` enum (from ColorExtensions.swift) — only used by the old DetailSheetView
- `SessionStore.currentEvents`, `updateClip()`, old `save(events:)` (from SessionStore.swift)
- `MovementAggregator.swift` — no longer called anywhere

- [ ] **Step 1: Clean up Models.swift**

In `BoxMaxxingFinal/Models.swift`:

**Remove** the entire `// MARK: - Session Event` block (lines 33–76 currently):
```swift
// MARK: - Session Event

struct SessionEvent: Identifiable { ... }

// MARK: - Session Event Extensions

extension SessionEvent { ... }
```

**Remove** the entire `// MARK: - Session State Extensions` block:
```swift
// MARK: - Session State Extensions (computed stats over SessionStore events)

extension SessionState { ... }
```

**Remove** the `generateEvents()` function.

**Keep**: `Move`, `FramePrediction`, `Combo`, `LivePunch`, `WrongMovement`, `WindowResult`, `SkeletonFrame`, `SessionState`, `allMoves`, `allCombos`, `findMove()`, `formatTime()`.

The cleaned Models.swift:

```swift
import Foundation
import CoreMedia
import Vision

// MARK: - Move

struct Move: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let short: String
    let kind: MoveKind
    let side: MoveSide

    enum MoveKind { case jab, hook, uppercut }
    enum MoveSide { case left, right }
}

// MARK: - Frame Prediction

struct FramePrediction {
    let label: String
    let confidence: Float
}

// MARK: - Combo

struct Combo: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let moveIds: [String]
}

// MARK: - Wrong Movement

struct WrongMovement: Identifiable {
    let id = UUID()
    let timestamp: CMTime
    let expectedMove: Move
    let detectedMoveId: String
    let confidence: Float

    var isWrongTechnique: Bool { detectedMoveId != expectedMove.id }
}

// MARK: - Live Punch (for recording HUD)

struct LivePunch: Identifiable {
    let id = UUID()
    let move: Move
    let confidence: Double
    let timestamp: Date
}

// MARK: - Window Result (for live HUD feedback)

struct WindowResult {
    let expectedMoveId: String
    let detectedMoveId: String?
    let confidence: Double
    let matched: Bool
}

// MARK: - Skeleton Frame (for live overlay)

struct SkeletonFrame {
    let joints: [VNHumanBodyPoseObservation.JointName: CGPoint]
    let confidence: [VNHumanBodyPoseObservation.JointName: Float]
}

// MARK: - Session State

struct SessionState {
    var selectedComboId: String? = nil
    var selectedMoveIds: [String] = []
    var sessionLength: Int = 2
}

// MARK: - Static Data

let allMoves: [Move] = [
    Move(id: "lj", name: "Left Jab",       short: "LJ", kind: .jab,      side: .left),
    Move(id: "rj", name: "Right Jab",      short: "RJ", kind: .jab,      side: .right),
    Move(id: "lh", name: "Left Hook",      short: "LH", kind: .hook,     side: .left),
    Move(id: "rh", name: "Right Hook",     short: "RH", kind: .hook,     side: .right),
    Move(id: "lu", name: "Left Uppercut",  short: "LU", kind: .uppercut, side: .left),
    Move(id: "ru", name: "Right Uppercut", short: "RU", kind: .uppercut, side: .right),
]

let allCombos: [Combo] = [
    Combo(id: "c1", name: "The 1-2",        subtitle: "Jab · Cross",         moveIds: ["lj", "rj"]),
    Combo(id: "c2", name: "Jab Cross Hook", subtitle: "Classic combination", moveIds: ["lj", "rj", "lh"]),
    Combo(id: "c3", name: "Body to Head",   subtitle: "Mix elevations",      moveIds: ["lj", "lu", "rh"]),
    Combo(id: "c4", name: "Power Finisher", subtitle: "High impact",         moveIds: ["rj", "lh", "ru"]),
]

func findMove(_ id: String) -> Move? {
    allMoves.first { $0.id == id }
}

func formatTime(_ seconds: Int) -> String {
    String(format: "%02d:%02d", seconds / 60, seconds % 60)
}
```

- [ ] **Step 2: Clean up SessionStore.swift**

Replace `BoxMaxxingFinal/Services/SessionStore.swift` entirely with the final version (old API removed):

```swift
import Foundation
import Combine
import CoreMedia

final class SessionStore: ObservableObject {
    static let shared = SessionStore()
    private init() {}

    @Published private(set) var wrongMovements: [WrongMovement] = []
    private(set) var videoURL: URL?
    private(set) var sessionStartDate: Date?
    private(set) var sessionDuration: TimeInterval = 0

    @MainActor
    func save(movements: [WrongMovement], videoURL: URL?,
              startDate: Date, duration: TimeInterval) {
        wrongMovements       = movements
        self.videoURL        = videoURL
        sessionStartDate     = startDate
        sessionDuration      = duration
    }

    @MainActor
    func clear() {
        wrongMovements   = []
        videoURL         = nil
        sessionStartDate = nil
        sessionDuration  = 0
    }
}
```

- [ ] **Step 3: Remove MovementState from ColorExtensions.swift**

In `BoxMaxxingFinal/Utilities/ColorExtensions.swift`, delete the entire `// MARK: - MovementState` block (the enum and all its computed properties). Keep the `// MARK: - Color Helpers` extension on `Color`. The file becomes:

```swift
import SwiftUI

// MARK: - Color Helpers

extension Color {
    static func performanceColor(for confidence: Float) -> Color {
        let pct = confidence * 100
        if pct >= 85 { return Color(UIColor.systemGreen) }
        if pct >= 50 { return Color(UIColor.systemYellow) }
        return Color(UIColor.systemRed)
    }

    static func performanceLabel(for confidence: Float) -> String {
        let pct = confidence * 100
        if pct >= 85 { return "Excellent" }
        if pct >= 50 { return "Fair" }
        return "Poor"
    }
}
```

- [ ] **Step 4: Delete MovementAggregator.swift**

```bash
rm /Users/michael/Projects/BoxMaxxingFinal/BoxMaxxingFinal/Services/MovementAggregator.swift
```

Then remove the reference from the Xcode project file. To do this cleanly, open Xcode and delete the file from the project navigator (move to trash), OR use:

```bash
# Remove from git tracking
git rm BoxMaxxingFinal/Services/MovementAggregator.swift
```

Note: If the file is listed in the `.xcodeproj` but not deleted via Xcode, the build will fail with "file not found". The safest approach is to delete via `git rm` which also removes it from the working tree.

- [ ] **Step 5: Build to confirm everything compiles**

```bash
xcodebuild build \
  -project /Users/michael/Projects/BoxMaxxingFinal/BoxMaxxingFinal.xcodeproj \
  -scheme BoxMaxxingFinal \
  -destination 'platform=iOS Simulator,name=iPhone 16e' \
  2>&1 | grep -E '(error:|Build FAILED|Build SUCCEEDED)'
```

Expected: `Build SUCCEEDED`.

If there are "cannot find type 'SessionEvent'" errors, check that no file was missed. Common culprits: `MLInferenceEngineTests.swift`, `BoxMaxxingFinalTests.swift`, `SkeletonOverlayTests.swift` — check each for SessionEvent references.

- [ ] **Step 6: Run the full test suite**

```bash
xcodebuild test \
  -project /Users/michael/Projects/BoxMaxxingFinal/BoxMaxxingFinal.xcodeproj \
  -scheme BoxMaxxingFinal \
  -destination 'platform=iOS Simulator,name=iPhone 16e' \
  2>&1 | grep -E '(Test Case|passed|failed|error:|Build FAILED|Executed)'
```

Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
git add BoxMaxxingFinal/Models.swift \
        BoxMaxxingFinal/Services/SessionStore.swift \
        BoxMaxxingFinal/Utilities/ColorExtensions.swift
git commit -m "cleanup: remove SessionEvent, generateEvents, MovementAggregator, MovementState"
```

---

## What Was Removed

| Removed | Replaced by |
|---------|------------|
| `SessionEvent` + extension | `WrongMovement` |
| `MovementAggregator` | `MovementDetector` state machine |
| `PostSessionAnalyzer.extractClips()` | Nothing — no clip files |
| `PostSessionAnalyzer.buildEvent()` | Nothing |
| `SessionStore.updateClip()` | Nothing — videoURL set once |
| `SessionStore.currentEvents` | `SessionStore.wrongMovements` |
| `SessionState` extension (currentEvents stats) | Nothing — ResultsView computes from wrongMovements |
| `MovementState` enum | Nothing — DetailSheetView uses Color.performanceColor/Label directly |
| `generateEvents()` fallback | Zero wrong movements = clean session |
| `ContentView @ObservedObject store` | Direct read at navigation time |
| Background clip Task | Nothing |
