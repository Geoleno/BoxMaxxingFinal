# Live Movement Analysis Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the fake `generateEvents()` fallback with real ML-powered per-window movement evaluation that runs during the recording session, delivers instant results when the session ends, and extracts video clips in the background.

**Architecture:** `MLInferenceEngine` maintains a 60-frame rolling buffer; when full it runs `model.prediction()` and returns real `FramePrediction` values. `SessionManager` evaluates each 3-second window using `MovementAggregator`, builds `SessionEvent` objects in real-time, and saves them instantly at session end. `PostSessionAnalyzer.extractClips()` then trims video clips for wrong/unclear events in the background, updating `SessionStore` as each clip finishes. `SessionStore` becomes an `ObservableObject` so `ContentView` and `DetailSheetView` react to clip arrivals.

**Tech Stack:** CoreML (`MLMultiArray`, `MLDictionaryFeatureProvider`), `AVAssetExportSession`, SwiftUI `ObservableObject`/`@ObservedObject`

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `BoxMaxxingFinal/Models.swift` | Add `WindowResult` struct |
| Modify | `BoxMaxxingFinal/Services/SessionStore.swift` | `ObservableObject`, `@Published currentEvents`, `updateClip()` |
| Create | `BoxMaxxingFinalTests/SessionStoreTests.swift` | Tests for `updateClip()` |
| Modify | `BoxMaxxingFinal/Services/MLInferenceEngine.swift` | 60-frame buffer, joint extraction, real `model.prediction()` |
| Create | `BoxMaxxingFinalTests/MLInferenceEngineTests.swift` | Tests for label mapping, joint count, buffer reset |
| Modify | `BoxMaxxingFinal/Services/SessionManager.swift` | `currentWindowMoveId`, `liveSessionEvents`, window evaluation, fast-path `finalizeSession()` |
| Modify | `BoxMaxxingFinal/Services/PostSessionAnalyzer.swift` | Add `extractClips(videoURL:events:)` |
| Modify | `BoxMaxxingFinal/RecordingView.swift` | Add `CurrentMoveCard` to `RecordingHUD` |
| Modify | `BoxMaxxingFinal/ContentView.swift` | `@ObservedObject` `SessionStore` for reactive event passing |
| Modify | `BoxMaxxingFinal/ResultsView.swift` | `DetailSheetView` observes store by event ID for live clip updates |

---

## Conventions used throughout

**`SessionEvent.move` = the EXPECTED move** (what the app prompted). This matches the existing `generateEvents()` convention where `event.move` is the requested move and `event.detectedAs` is the wrong move name when the model detected something else. `DetailSheetView` shows "Expected: [event.move.name] → Detected as: [detectedAs]" — consistent with this.

**Status tiers** (match `PostSessionAnalyzer.buildEvent()`):
- `avgConfidence > 0.80` → `.correct` (no clip extracted)
- `avgConfidence > 0.50` → `.unclear` (clip extracted)
- `avgConfidence ≤ 0.50` → `.wrong` (clip extracted)

**Windows with no valid move detection** (body not found or no movement) → no `SessionEvent` emitted. `findMove(dominantLabel) != nil` is the guard: only `"lj"`, `"rj"`, `"lh"`, `"rh"`, `"lu"`, `"ru"` pass it.

---

## Task 1: WindowResult model + observable SessionStore

**Files:**
- Modify: `BoxMaxxingFinal/Models.swift`
- Modify: `BoxMaxxingFinal/Services/SessionStore.swift`
- Create: `BoxMaxxingFinalTests/SessionStoreTests.swift`

- [ ] **Step 1: Write failing tests for `updateClip()`**

Create `BoxMaxxingFinalTests/SessionStoreTests.swift`:

```swift
import XCTest
@testable import BoxMaxxingFinal

final class SessionStoreTests: XCTestCase {

    override func setUp() {
        super.setUp()
        SessionStore.shared.clear()
    }

    func test_updateClip_setsURLOnMatchingEvent() {
        let event = SessionEvent(id: "e1", time: 10, move: allMoves[0],
                                 status: .wrong, confidence: 0.4,
                                 detectedAs: nil, note: "", clipURL: nil)
        SessionStore.shared.save(events: [event], startDate: Date(), duration: 120)
        let url = URL(fileURLWithPath: "/tmp/clip.mov")
        SessionStore.shared.updateClip(eventId: "e1", url: url)
        XCTAssertEqual(SessionStore.shared.currentEvents.first?.clipURL, url)
    }

    func test_updateClip_doesNotAffectOtherEvents() {
        let e1 = SessionEvent(id: "e1", time: 10, move: allMoves[0],
                              status: .wrong, confidence: 0.4,
                              detectedAs: nil, note: "", clipURL: nil)
        let e2 = SessionEvent(id: "e2", time: 20, move: allMoves[1],
                              status: .unclear, confidence: 0.6,
                              detectedAs: nil, note: "", clipURL: nil)
        SessionStore.shared.save(events: [e1, e2], startDate: Date(), duration: 120)
        SessionStore.shared.updateClip(eventId: "e1", url: URL(fileURLWithPath: "/tmp/clip.mov"))
        XCTAssertNil(SessionStore.shared.currentEvents.first { $0.id == "e2" }?.clipURL)
    }

    func test_updateClip_unknownId_doesNothing() {
        let event = SessionEvent(id: "e1", time: 10, move: allMoves[0],
                                 status: .wrong, confidence: 0.4,
                                 detectedAs: nil, note: "", clipURL: nil)
        SessionStore.shared.save(events: [event], startDate: Date(), duration: 120)
        SessionStore.shared.updateClip(eventId: "unknown", url: URL(fileURLWithPath: "/tmp/clip.mov"))
        XCTAssertNil(SessionStore.shared.currentEvents.first?.clipURL)
    }
}
```

- [ ] **Step 2: Run tests — expect compile failure** (`updateClip` not yet defined)

```bash
xcodebuild test -scheme BoxMaxxingFinal -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD FAILED|TEST SUCCEEDED" | head -10
```

Expected: BUILD FAILED — `value of type 'SessionStore' has no member 'updateClip'`.

- [ ] **Step 3: Add `WindowResult` to `Models.swift`**

In `BoxMaxxingFinal/Models.swift`, after the `LivePunch` struct (around line 85), add:

```swift
// MARK: - Window Result (for live HUD feedback)

struct WindowResult {
    let expectedMoveId: String
    let detectedMoveId: String?   // nil when no valid move detected
    let confidence: Double         // 0.0–1.0
    let matched: Bool              // detectedMoveId == expectedMoveId
}
```

- [ ] **Step 4: Replace `SessionStore.swift` with `ObservableObject` version**

Replace the entire contents of `BoxMaxxingFinal/Services/SessionStore.swift`:

```swift
import Foundation

final class SessionStore: ObservableObject {
    static let shared = SessionStore()
    private init() {}

    @Published private(set) var currentEvents: [SessionEvent] = []
    private(set) var sessionStartDate: Date?
    private(set) var sessionDuration: TimeInterval = 0

    func save(events: [SessionEvent], startDate: Date, duration: TimeInterval) {
        currentEvents = events
        sessionStartDate = startDate
        sessionDuration = duration
    }

    /// Replaces the event matching `eventId` with an updated copy that has `clipURL` set.
    /// Must be called on the main queue.
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

    func clear() {
        currentEvents = []
        sessionStartDate = nil
        sessionDuration = 0
    }
}
```

- [ ] **Step 5: Run all tests — expect PASS**

```bash
xcodebuild test -scheme BoxMaxxingFinal -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "FAILED|TEST SUCCEEDED" | head -10
```

Expected: TEST SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add BoxMaxxingFinal/Models.swift BoxMaxxingFinal/Services/SessionStore.swift BoxMaxxingFinalTests/SessionStoreTests.swift
git commit -m "feat: add WindowResult model and make SessionStore observable with updateClip()"
```

---

## Task 2: MLInferenceEngine — 60-frame buffer + real inference

**Files:**
- Modify: `BoxMaxxingFinal/Services/MLInferenceEngine.swift`
- Create: `BoxMaxxingFinalTests/MLInferenceEngineTests.swift`

> **Model facts:** Input `poses: [60, 3, 18]` — shape is frames × coordinate (x/y/confidence) × joint. 18 joints in the fixed order below must match Create ML's training format. Output `label: String` and `labelProbabilities: [String: NSNumber]`. 6 classes: `"Jab"`, `"Straight"`, `"Left Hook"`, `"Right Hook"`, `"Left Uppercut"`, `"Right Uppercut"`.
>
> **Thread safety:** `predictMove()` is called from `DispatchQueue.global(qos: .userInteractive)` (inside `VisionProcessor.detectBodyPose` completion). `alwaysDiscardsLateVideoFrames = true` on the camera output prevents frame pile-up, so concurrent calls to `predictMove()` are extremely rare in practice. No lock is added — a missed prediction due to a race is benign.

- [ ] **Step 1: Write failing tests**

Create `BoxMaxxingFinalTests/MLInferenceEngineTests.swift`:

```swift
import XCTest
import Vision
@testable import BoxMaxxingFinal

final class MLInferenceEngineTests: XCTestCase {

    func test_labelToMoveId_mapsAllSixClasses() {
        XCTAssertEqual(MLInferenceEngine.labelToMoveId["Jab"],            "lj")
        XCTAssertEqual(MLInferenceEngine.labelToMoveId["Straight"],       "rj")
        XCTAssertEqual(MLInferenceEngine.labelToMoveId["Left Hook"],      "lh")
        XCTAssertEqual(MLInferenceEngine.labelToMoveId["Right Hook"],     "rh")
        XCTAssertEqual(MLInferenceEngine.labelToMoveId["Left Uppercut"],  "lu")
        XCTAssertEqual(MLInferenceEngine.labelToMoveId["Right Uppercut"], "ru")
    }

    func test_jointNames_hasExactly18Entries() {
        XCTAssertEqual(MLInferenceEngine.jointNames.count, 18)
    }

    func test_predictMove_nilObservations_returnsNoBody() {
        let engine = MLInferenceEngine()
        let pred = engine.predictMove(from: nil)
        XCTAssertEqual(pred.label, "no_body_detected")
        XCTAssertEqual(pred.confidence, 0.0)
    }

    func test_predictMove_emptyObservations_returnsNoBody() {
        let engine = MLInferenceEngine()
        let pred = engine.predictMove(from: [])
        XCTAssertEqual(pred.label, "no_body_detected")
        XCTAssertEqual(pred.confidence, 0.0)
    }

    func test_resetBuffer_doesNotCrash_andSubsequentNilPredictionWorks() {
        let engine = MLInferenceEngine()
        engine.resetBuffer()
        let pred = engine.predictMove(from: nil)
        XCTAssertEqual(pred.label, "no_body_detected")
    }
}
```

- [ ] **Step 2: Run tests — expect compile failure** (`labelToMoveId`, `jointNames` not yet `static`)

```bash
xcodebuild test -scheme BoxMaxxingFinal -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD FAILED|TEST SUCCEEDED" | head -10
```

Expected: BUILD FAILED.

- [ ] **Step 3: Replace `MLInferenceEngine.swift` with full implementation**

Replace the entire contents of `BoxMaxxingFinal/Services/MLInferenceEngine.swift`:

```swift
import Vision
import CoreML

final class MLInferenceEngine {

    // MARK: - Constants

    /// Fixed joint order — must match the order Create ML used during training.
    static let jointNames: [VNHumanBodyPoseObservation.JointName] = [
        .nose,
        .leftEye,  .rightEye,
        .leftEar,  .rightEar,
        .leftShoulder,  .rightShoulder,
        .leftElbow,     .rightElbow,
        .leftWrist,     .rightWrist,
        .leftHip,       .rightHip,
        .leftKnee,      .rightKnee,
        .leftAnkle,     .rightAnkle,
        .neck
    ]

    static let labelToMoveId: [String: String] = [
        "Jab":            "lj",
        "Straight":       "rj",
        "Left Hook":      "lh",
        "Right Hook":     "rh",
        "Left Uppercut":  "lu",
        "Right Uppercut": "ru",
    ]

    private static let windowSize = 60   // frames — matches model's Prediction Window Size

    // MARK: - State

    private var model: MLModel?
    // Rolling buffer: each entry is 54 floats — 18 joints × [x, y, confidence]
    private var frameBuffer: [[Float]] = []

    // MARK: - Setup

    func loadModel() {
        do {
            guard let url = Bundle.main.url(forResource: "80 epoch", withExtension: "mlmodel") else {
                print("MLInferenceEngine: Model file not found in bundle")
                return
            }
            model = try MLModel(contentsOf: url, configuration: MLModelConfiguration())
        } catch {
            print("MLInferenceEngine: Failed to load model — \(error)")
        }
    }

    func resetBuffer() {
        frameBuffer = []
    }

    // MARK: - Per-frame inference

    func predictMove(from observations: [VNHumanBodyPoseObservation]?) -> FramePrediction {
        guard let observations, !observations.isEmpty else {
            return FramePrediction(label: "no_body_detected", confidence: 0.0)
        }

        // Extract joint values from the highest-confidence observation (Vision sorts desc)
        let allPoints = (try? observations[0].recognizedPoints(.all)) ?? [:]
        var frameValues = [Float](repeating: 0, count: 54)  // 18 joints × 3
        for (i, name) in Self.jointNames.enumerated() {
            if let pt = allPoints[name] {
                frameValues[i * 3]     = Float(pt.location.x)
                frameValues[i * 3 + 1] = Float(pt.location.y)
                frameValues[i * 3 + 2] = Float(pt.confidence)
            }
            // missing joint stays (0, 0, 0)
        }

        // Slide buffer: append new frame, drop oldest when over window size
        frameBuffer.append(frameValues)
        if frameBuffer.count > Self.windowSize {
            frameBuffer.removeFirst()
        }

        // Need a full 60-frame window before running inference
        guard frameBuffer.count == Self.windowSize, let model else {
            return FramePrediction(label: "no_movement_detected", confidence: 0.0)
        }

        // Build MLMultiArray with shape [60, 3, 18]
        guard let multiArray = try? MLMultiArray(shape: [60, 3, 18] as [NSNumber], dataType: .float32) else {
            return FramePrediction(label: "no_movement_detected", confidence: 0.0)
        }
        for frameIdx in 0..<Self.windowSize {
            let frame = frameBuffer[frameIdx]
            for jointIdx in 0..<18 {
                let base = jointIdx * 3
                multiArray[[frameIdx, 0, jointIdx] as [NSNumber]] = NSNumber(value: frame[base])
                multiArray[[frameIdx, 1, jointIdx] as [NSNumber]] = NSNumber(value: frame[base + 1])
                multiArray[[frameIdx, 2, jointIdx] as [NSNumber]] = NSNumber(value: frame[base + 2])
            }
        }

        // Run inference
        guard let input  = try? MLDictionaryFeatureProvider(dictionary: ["poses": MLFeatureValue(multiArray: multiArray)]),
              let output = try? model.prediction(from: input) else {
            return FramePrediction(label: "no_movement_detected", confidence: 0.0)
        }

        let rawLabel   = output.featureValue(for: "label")?.stringValue ?? ""
        let probs      = output.featureValue(for: "labelProbabilities")?.dictionaryValue as? [String: NSNumber]
        let confidence = Float(probs?[rawLabel]?.doubleValue ?? 0)
        let moveId     = Self.labelToMoveId[rawLabel] ?? "no_movement_detected"

        return FramePrediction(label: moveId, confidence: confidence)
    }
}
```

- [ ] **Step 4: Run all tests — expect PASS**

```bash
xcodebuild test -scheme BoxMaxxingFinal -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "FAILED|TEST SUCCEEDED" | head -10
```

Expected: TEST SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add BoxMaxxingFinal/Services/MLInferenceEngine.swift BoxMaxxingFinalTests/MLInferenceEngineTests.swift
git commit -m "feat: implement MLInferenceEngine with 60-frame rolling buffer and real CoreML inference"
```

---

## Task 3: SessionManager — window evaluation + live events

**Files:**
- Modify: `BoxMaxxingFinal/Services/SessionManager.swift`

> **Convention reminder:** `event.move` = the EXPECTED move (what the app prompted). `event.detectedAs` = the detected move's name when wrong (nil when matched). This matches the existing `generateEvents()` and `DetailSheetView` convention.
>
> **`currentWindowMoveId`:** Set in `beginMoveWindow()` when the window starts. Used in `endMoveWindow()` as the ground-truth expected move ID — no index arithmetic after `currentMoveIndex` is incremented.
>
> **No unit tests:** The logic composition (MovementAggregator + status tiers) is already covered in `PostSessionAnalyzerTests` and `SessionStoreTests`. End-to-end behavior is verified on device.

- [ ] **Step 1: Add new properties**

In `BoxMaxxingFinal/Services/SessionManager.swift`, in the `// MARK: - Published State` section, after `@Published var videoBufferSize`, add:

```swift
@Published var currentTargetMove: Move? = nil
@Published var lastWindowResult: WindowResult? = nil
```

In the `// MARK: - Internal State` section, after `private var currentFramePredictions`, add:

```swift
private var liveSessionEvents: [SessionEvent] = []
private var currentWindowMoveId: String = ""
private var windowResultToken = UUID()
```

- [ ] **Step 2: Reset new state in `configure()` and `startSession()`**

In `configure()`, after `livePunches = []`, add:

```swift
liveSessionEvents = []
currentWindowMoveId = ""
currentTargetMove = nil
lastWindowResult = nil
```

In `startSession()`, after `livePunches = []`, add:

```swift
liveSessionEvents = []
currentWindowMoveId = ""
mlEngine.resetBuffer()
```

- [ ] **Step 3: Update `finalizeSession()` to nil-out the new published properties**

In `finalizeSession()`, after `currentSkeleton = nil`, add:

```swift
currentTargetMove = nil
lastWindowResult = nil
```

- [ ] **Step 4: Replace `beginMoveWindow()` to save `currentWindowMoveId` and publish the target**

Replace the entire `beginMoveWindow()` method:

```swift
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
```

- [ ] **Step 5: Replace `endMoveWindow()` with evaluation logic**

Replace the entire `endMoveWindow()` method:

```swift
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
            move:       expectedMove,                                 // EXPECTED (convention)
            status:     status,
            confidence: Double(avgConfidence),
            detectedAs: matched ? nil : detectedMove.name,           // detected name when wrong
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
```

- [ ] **Step 6: Replace `finalizeSession()` with live-events fast path**

Replace the entire `finalizeSession()` method:

```swift
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
```

- [ ] **Step 7: Build — confirm no compile errors**

```bash
xcodebuild build -scheme BoxMaxxingFinal -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 8: Run all tests**

```bash
xcodebuild test -scheme BoxMaxxingFinal -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "FAILED|TEST SUCCEEDED" | head -10
```

Expected: TEST SUCCEEDED.

- [ ] **Step 9: Commit**

```bash
git add BoxMaxxingFinal/Services/SessionManager.swift
git commit -m "feat: evaluate each recording window live and accumulate SessionEvents during session"
```

---

## Task 4: PostSessionAnalyzer — background clip extraction

**Files:**
- Modify: `BoxMaxxingFinal/Services/PostSessionAnalyzer.swift`

> **No unit tests:** `AVAssetExportSession` requires a real video file. Verified on device after Task 3 integration.
>
> **Clip timing:** Start = `event.time - 0.5s` (clamped to 0), end = `event.time + 2.5s` (clamped to video duration) → 3-second window centered on the detected move.
>
> **Serial processing:** Events are trimmed one at a time to avoid iOS throttling multiple `AVAssetExportSession` exports.
>
> **`updateClip()` must run on main queue** — wrap each call in `await MainActor.run {}`.

- [ ] **Step 1: Add `import AVFoundation` to `PostSessionAnalyzer.swift` if not present**

Check the top of `BoxMaxxingFinal/Services/PostSessionAnalyzer.swift`. If the first line is `import AVFoundation`, skip this step. Otherwise add it:

```swift
import AVFoundation
import Vision
import Foundation
```

- [ ] **Step 2: Add `extractClips(videoURL:events:)` to `PostSessionAnalyzer`**

Add the following method inside `PostSessionAnalyzer`, after `buildEvent()`:

```swift
// MARK: - Background clip extraction

/// Trims a 3-second clip for each wrong/unclear event and updates SessionStore as each completes.
/// Processes events serially to avoid AVAssetExportSession throttling. Must be called from any
/// non-main queue context (e.g., a detached Task). updateClip() is dispatched to main actor.
func extractClips(videoURL: URL, events: [SessionEvent]) async {
    let asset = AVAsset(url: videoURL)

    let videoDuration: Double
    do {
        let cmDuration = try await asset.load(.duration)
        videoDuration = CMTimeGetSeconds(cmDuration)
    } catch {
        return  // can't load asset — skip all clips
    }

    for event in events where event.status != .correct {
        let startSec = max(0, Double(event.time) - 0.5)
        let endSec   = min(videoDuration, Double(event.time) + 2.5)
        guard endSec > startSec else { continue }

        let timeRange = CMTimeRange(
            start:    CMTime(seconds: startSec, preferredTimescale: 600),
            duration: CMTime(seconds: endSec - startSec, preferredTimescale: 600)
        )

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mov")

        guard let session = AVAssetExportSession(asset: asset,
                                                 presetName: AVAssetExportPresetPassthrough) else { continue }
        session.outputURL      = outputURL
        session.outputFileType = .mov
        session.timeRange      = timeRange

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { cont.resume() }
        }

        guard session.status == .completed else { continue }

        let eventId = event.id
        let clipURL = outputURL
        await MainActor.run {
            SessionStore.shared.updateClip(eventId: eventId, url: clipURL)
        }
    }
}
```

- [ ] **Step 3: Build — confirm no compile errors**

```bash
xcodebuild build -scheme BoxMaxxingFinal -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Run all tests**

```bash
xcodebuild test -scheme BoxMaxxingFinal -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "FAILED|TEST SUCCEEDED" | head -10
```

Expected: TEST SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add BoxMaxxingFinal/Services/PostSessionAnalyzer.swift
git commit -m "feat: add PostSessionAnalyzer.extractClips() for background video clip extraction"
```

---

## Task 5: Approach A HUD — CurrentMoveCard

**Files:**
- Modify: `BoxMaxxingFinal/RecordingView.swift`

> `currentTargetMove` and `lastWindowResult` are already published by `SessionManager` (Task 3). This task only adds the view layer. The card appears above the progress bar; when `lastWindowResult` is non-nil the card switches to a result flash (green ✓ matched / red ✗ missed) for 1.5s then reverts to the idle "NOW: [move]" state.

- [ ] **Step 1: Add `CurrentMoveCard` view**

In `BoxMaxxingFinal/RecordingView.swift`, add this struct after the closing brace of `LivePunchChip` (around line 482):

```swift
private struct CurrentMoveCard: View {
    let targetMove: Move?
    let result: WindowResult?

    var body: some View {
        Group {
            if let result {
                HStack(spacing: 10) {
                    Image(systemName: result.matched ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(result.matched ? Color(UIColor.systemGreen) : Color(UIColor.systemRed))
                        .font(.system(size: 18, weight: .semibold))
                    Text(result.matched ? "Nice!" : "Missed")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Text("\(Int(result.confidence * 100))%")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(result.matched
                              ? Color(UIColor.systemGreen).opacity(0.25)
                              : Color(UIColor.systemRed).opacity(0.20))
                )
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            } else if let move = targetMove {
                HStack(spacing: 10) {
                    MoveGlyphView(kind: move.kind, side: move.side, color: .white, size: 18)
                    Text(move.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                    Spacer()
                    Text("NOW")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.5)
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .animation(.easeOut(duration: 0.3), value: result?.matched)
        .animation(.easeOut(duration: 0.3), value: targetMove?.id)
    }
}
```

- [ ] **Step 2: Add `currentTargetMove` and `lastWindowResult` parameters to `RecordingHUD`**

Find `private struct RecordingHUD: View` and add two parameters:

```swift
private struct RecordingHUD: View {
    let elapsed: Int
    let total: Int
    let progress: Double
    let livePunches: [LivePunch]
    let currentTargetMove: Move?
    let lastWindowResult: WindowResult?
    let onStop: () -> Void
    let onCancel: () -> Void
```

- [ ] **Step 3: Add `CurrentMoveCard` to the HUD body**

In `RecordingHUD.body`, find the `// Progress bar` `GeometryReader` block. Add `CurrentMoveCard` immediately before it:

```swift
            // Current combo target card
            CurrentMoveCard(targetMove: currentTargetMove, result: lastWindowResult)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            // Progress bar
            GeometryReader { geo in
```

- [ ] **Step 4: Update the `RecordingHUD` call site in `RecordingView.body`**

Find the `case .recording:` block and update the `RecordingHUD` initializer:

```swift
case .recording:
    RecordingHUD(
        elapsed: sessionManager.elapsedSeconds,
        total: total,
        progress: progress,
        livePunches: sessionManager.livePunches,
        currentTargetMove: sessionManager.currentTargetMove,
        lastWindowResult: sessionManager.lastWindowResult,
        onStop: { sessionManager.requestStop() },
        onCancel: onCancel
    )
```

- [ ] **Step 5: Build — confirm no compile errors**

```bash
xcodebuild build -scheme BoxMaxxingFinal -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Run all tests**

```bash
xcodebuild test -scheme BoxMaxxingFinal -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "FAILED|TEST SUCCEEDED" | head -10
```

Expected: TEST SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add BoxMaxxingFinal/RecordingView.swift
git commit -m "feat: add CurrentMoveCard to RecordingHUD for live window target and result feedback"
```

---

## Task 6: ContentView + DetailSheetView — progressive clip updates

**Files:**
- Modify: `BoxMaxxingFinal/ContentView.swift`
- Modify: `BoxMaxxingFinal/ResultsView.swift`

> `SessionStore` is now an `ObservableObject` with `@Published currentEvents` (Task 1). `ContentView` currently reads `SessionStore.shared.currentEvents` directly without observing — changes from `updateClip()` won't trigger re-renders. This task wires the reactivity.
>
> `DetailSheetView` currently receives `let event: SessionEvent` (a value-type snapshot). If a clip arrives while the sheet is open, the sheet won't update. Changing it to look up the live event from the store by ID fixes this. Inside `if let event { }`, all existing references to `event` remain unchanged.

- [ ] **Step 1: Add `@ObservedObject` to `ContentView` and use `store.currentEvents`**

In `BoxMaxxingFinal/ContentView.swift`, add a property to `ContentView`:

```swift
@ObservedObject private var store = SessionStore.shared
```

Then update the `case .results:` block from:

```swift
case .results:
    ResultsView(
        state: sessionState,
        events: SessionStore.shared.currentEvents,
        onBack: {
            SessionRecorder.shared.deleteSessionFile()
            SessionStore.shared.clear()
            withAnimation(.easeInOut(duration: 0.25)) { route = .menu }
        }
    )
    .transition(.opacity)
```

to:

```swift
case .results:
    ResultsView(
        state: sessionState,
        events: store.currentEvents,
        onBack: {
            SessionRecorder.shared.deleteSessionFile()
            SessionStore.shared.clear()
            withAnimation(.easeInOut(duration: 0.25)) { route = .menu }
        }
    )
    .transition(.opacity)
```

- [ ] **Step 2: Change `DetailSheetView` to look up its event live from the store**

In `BoxMaxxingFinal/ResultsView.swift`, find `struct DetailSheetView: View` (around line 293). Replace the struct header and its `accent` property:

Replace:
```swift
struct DetailSheetView: View {
    let event: SessionEvent
    @Environment(\.dismiss) private var dismiss
    @State private var clipPlaying = false

    private var accent: Color { event.movementState.color }
```

With:
```swift
struct DetailSheetView: View {
    let eventId: String
    @ObservedObject private var store = SessionStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var clipPlaying = false

    private var event: SessionEvent? {
        store.currentEvents.first { $0.id == eventId }
    }

    private var accent: Color { event?.movementState.color ?? Color(UIColor.systemGray) }
```

- [ ] **Step 3: Wrap `DetailSheetView.body` with `if let event`**

Find `var body: some View {` in `DetailSheetView`. Wrap the existing `ScrollView { ... }` content:

Replace:
```swift
    var body: some View {
        ScrollView {
```

With:
```swift
    var body: some View {
        if let event {
        ScrollView {
```

And at the very end of `var body`, before the final `}` that closes the `var body` block, add a closing `}` for the `if let event`:

```swift
        }  // end ScrollView
        }  // end if let event
    }  // end var body
```

> **Clarification:** The `ScrollView` and all its content inside `DetailSheetView.body` are unchanged — only the outer `if let event { }` wrapper is added. All references to `event` inside the ScrollView work as-is since they are inside the `if let` binding scope.

- [ ] **Step 4: Update the `DetailSheetView` call site**

In `ResultsView.body`, find:

```swift
.sheet(item: $activeEvent) { event in
    DetailSheetView(event: event)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
}
```

Replace with:

```swift
.sheet(item: $activeEvent) { event in
    DetailSheetView(eventId: event.id)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
}
```

- [ ] **Step 5: Build — confirm no compile errors**

```bash
xcodebuild build -scheme BoxMaxxingFinal -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Run all tests**

```bash
xcodebuild test -scheme BoxMaxxingFinal -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "FAILED|TEST SUCCEEDED" | head -10
```

Expected: TEST SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add BoxMaxxingFinal/ContentView.swift BoxMaxxingFinal/ResultsView.swift
git commit -m "feat: observe SessionStore in ContentView and DetailSheetView for progressive clip updates"
```

---

## Self-Review

**Spec coverage:**
- ✅ `WindowResult` struct — Task 1
- ✅ `SessionStore` `ObservableObject` + `@Published currentEvents` + `updateClip()` — Task 1
- ✅ `MLInferenceEngine` 60-frame buffer + joint extraction + real `model.prediction()` — Task 2
- ✅ Label → Move.id mapping — Task 2
- ✅ `resetBuffer()` called at session start — Task 3
- ✅ `currentWindowMoveId` set in `beginMoveWindow()` — Task 3
- ✅ `currentTargetMove` and `lastWindowResult` published — Task 3
- ✅ `endMoveWindow()` evaluation → `liveSessionEvents` accumulation — Task 3
- ✅ `finalizeSession()` fast path (instant results) + background clip Task — Task 3
- ✅ Fallback path (no camera) preserved — Task 3
- ✅ `extractClips(videoURL:events:)` serial export + `updateClip()` on main actor — Task 4
- ✅ `CurrentMoveCard` — idle state + result flash — Task 5
- ✅ `ContentView` `@ObservedObject store` — Task 6
- ✅ `DetailSheetView` looks up live event by ID — Task 6

**Placeholder scan:** None.

**Type consistency:**
- `WindowResult` defined Task 1 → used in Task 3 (`lastWindowResult`) and Task 5 (`CurrentMoveCard`) ✓
- `updateClip(eventId:url:)` defined Task 1 → called in Task 4 ✓
- `extractClips(videoURL:events:)` defined Task 4 → called in Task 3 `finalizeSession()` ✓
- `currentTargetMove: Move?` and `lastWindowResult: WindowResult?` defined Task 3 → used in Task 5 ✓
- `DetailSheetView(eventId:)` defined Task 6 Step 2 → call site updated Task 6 Step 4 ✓
