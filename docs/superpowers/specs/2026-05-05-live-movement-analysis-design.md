# Live Movement Analysis Design

## Goal

Replace the fake `generateEvents()` fallback with real ML-powered movement evaluation. Evaluation runs window-by-window during the recording session so ResultsView opens instantly with full accuracy data. Video clips for wrong/unclear events are extracted in the background and appear progressively in ResultsView over the next few seconds.

## Architecture — Three-Phase Pipeline

**Phase 1 — During recording (live, per 3-second window):**
`MLInferenceEngine` maintains a 60-frame rolling buffer of joint positions. Each camera frame fills one slot. Once full, it runs `model.prediction()` and returns a real `FramePrediction`. At the end of each 3-second window, `SessionManager` aggregates collected predictions via `MovementAggregator`, compares the result to the expected combo move, builds a `SessionEvent` (with `clipURL = nil`), and appends it to a private `liveSessionEvents` array.

**Phase 2 — Session ends (instant):**
`finalizeSession()` detects that `liveSessionEvents` is non-empty and uses them directly — no call to `PostSessionAnalyzer.analyze()`. `isAnalyzing` goes false immediately. ResultsView opens with full accuracy data.

**Phase 3 — Background (a few seconds):**
A background Task waits for the video file, trims clips for wrong/unclear events serially using `AVAssetExportSession`, and updates each event in `SessionStore` as clips complete. `SessionStore` becomes an `ObservableObject` so ResultsView re-renders when clip URLs arrive.

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `BoxMaxxingFinal/Models.swift` | Add `WindowResult` struct |
| Modify | `BoxMaxxingFinal/Services/MLInferenceEngine.swift` | Implement 60-frame buffer + real inference |
| Modify | `BoxMaxxingFinal/Services/SessionManager.swift` | Window evaluation, live events, HUD properties |
| Modify | `BoxMaxxingFinal/Services/PostSessionAnalyzer.swift` | Implement clip extraction (replaces stub analyze()) |
| Modify | `BoxMaxxingFinal/Services/SessionStore.swift` | ObservableObject, @Published currentEvents, updateClip() |
| Modify | `BoxMaxxingFinal/RecordingView.swift` | Approach A HUD: target card + result flash |
| Modify | `BoxMaxxingFinal/ResultsView.swift` | Clip loading state (spinner → active on clipURL) |
| Modify | `BoxMaxxingFinal/ContentView.swift` | Observe SessionStore for progressive clip updates |

---

## Component Designs

### 1. Models.swift — WindowResult

Add after `LivePunch`:

```swift
struct WindowResult {
    let expectedMoveId: String
    let detectedMoveId: String?   // nil if no_movement_detected or no_body_detected
    let confidence: Double         // 0.0–1.0
    let matched: Bool              // detectedMoveId == expectedMoveId
}
```

---

### 2. MLInferenceEngine — 60-frame buffer + real inference

**Joint order (fixed — must match Create ML training):**
```swift
static let jointNames: [VNHumanBodyPoseObservation.JointName] = [
    .nose,
    .leftEye, .rightEye,
    .leftEar, .rightEar,
    .leftShoulder, .rightShoulder,
    .leftElbow, .rightElbow,
    .leftWrist, .rightWrist,
    .leftHip, .rightHip,
    .leftKnee, .rightKnee,
    .leftAnkle, .rightAnkle,
    .neck
]
```

**Label → Move.id mapping:**
```swift
static let labelToMoveId: [String: String] = [
    "Jab":            "lj",
    "Straight":       "rj",
    "Left Hook":      "lh",
    "Right Hook":     "rh",
    "Left Uppercut":  "lu",
    "Right Uppercut": "ru",
]
```

**Buffer:** `private var frameBuffer: [[Float]] = []` — each entry is 54 values (18 joints × 3: x, y, confidence). Capped at 60 entries; oldest frame dropped when full.

**Per-frame extraction:** For each of the 18 joints in order, read the `VNRecognizedPoint` from `observation.recognizedPoints(.all)`. If the joint is absent, append `(0, 0, 0)`. Append the 54-value row to `frameBuffer`.

**Inference trigger:** When `frameBuffer.count == 60`:
1. Create `MLMultiArray(shape: [60, 3, 18], dataType: .float32)`
2. Fill: `array[[frameIdx, 0, jointIdx]] = x`, `array[[frameIdx, 1, jointIdx]] = y`, `array[[frameIdx, 2, jointIdx]] = confidence`
3. Call `model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["poses": array]))`
4. Read `label` (String) and `labelProbabilities` (dict) from output
5. Map label via `labelToMoveId` → Move.id (or `"no_movement_detected"` if not in dict)
6. Return `FramePrediction(label: mappedId, confidence: Float(labelProbabilities[label] ?? 0))`

Before buffer reaches 60 frames, return `FramePrediction(label: "no_movement_detected", confidence: 0.0)`.

**Buffer reset:** Add `func resetBuffer()` — called by `SessionManager` at session start so state doesn't bleed between sessions.

The buffer is not thread-safe by design — `predictMove()` is always called from the camera thread via `processFrame`, consistent with today.

---

### 3. SessionManager — window evaluation + live events

**New private state:**
```swift
private var liveSessionEvents: [SessionEvent] = []
```

**New @Published properties (Approach A HUD):**
```swift
@Published var currentTargetMove: Move? = nil
@Published var lastWindowResult: WindowResult? = nil
```

**New private state (in addition to liveSessionEvents):**
```swift
private var currentWindowMoveId: String = ""
```

**beginMoveWindow() addition:**
```swift
let moveId = combo.moveIds[currentMoveIndex % combo.moveIds.count]
currentWindowMoveId = moveId
currentTargetMove = findMove(moveId)
```

**endMoveWindow() — replace discard with evaluation (runs before incrementing currentMoveIndex):**
```
let (dominantLabel, avgConfidence) = MovementAggregator().aggregate(predictions: currentFramePredictions)
let expectedMoveId = currentWindowMoveId
let matched = dominantLabel == expectedMoveId

let status: SessionEvent.EventStatus
switch avgConfidence {
  case let c where c > 0.80: status = .correct
  case let c where c > 0.50: status = .unclear
  default:                    status = .wrong
}

// Only emit event if a real move was detected (not no_body / no_movement)
if let move = findMove(dominantLabel) {
    let event = SessionEvent(
        id: UUID().uuidString,
        time: elapsedSeconds,
        move: move,
        status: status,
        confidence: Double(avgConfidence),
        detectedAs: matched ? nil : findMove(dominantLabel)?.name,
        note: PerformanceFeedback.suggestion(for: dominantLabel),
        clipURL: nil
    )
    liveSessionEvents.append(event)
}

// HUD result flash (cleared after 1.5s)
let result = WindowResult(
    expectedMoveId: expectedMoveId,
    detectedMoveId: findMove(dominantLabel) != nil ? dominantLabel : nil,
    confidence: Double(avgConfidence),
    matched: matched
)
lastWindowResult = result
DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
    if self?.lastWindowResult?.expectedMoveId == result.expectedMoveId {
        self?.lastWindowResult = nil
    }
}
```

**finalizeSession() — use live events:**
```swift
// After stopping timers and setting isRecording = false:
if !liveSessionEvents.isEmpty {
    SessionStore.shared.save(
        events:    liveSessionEvents,
        startDate: sessionStartDate ?? Date(),
        duration:  TimeInterval(elapsedSeconds)
    )
    isAnalyzing = false   // instant — ResultsView opens now

    // Background: finalize the video file and extract clips
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
            // Recording failed — clips unavailable, accuracy data already saved
        }
    }
} else {
    // Fallback path (no camera / debug): existing PostSessionAnalyzer flow unchanged
    isAnalyzing = true
    Task { @MainActor in
        // ... existing logic unchanged ...
    }
}
```

**startSession() addition:** Call `mlEngine.resetBuffer()` and `liveSessionEvents = []`.

**finalizeSession() addition:** `currentTargetMove = nil`, `lastWindowResult = nil`.

---

### 4. PostSessionAnalyzer — clip extraction

`analyze(videoURL:)` stub stays as-is (used only by the debug/fallback path).

Add a new method used by `SessionManager`:

```swift
func extractClips(videoURL: URL, events: [SessionEvent]) async
```

For each event where `status != .correct`:
1. Load `AVAsset(url: videoURL)`
2. Compute time range: `CMTimeRange` from `event.time - 0.5s` to `event.time + 2.5s`, clamped to video duration
3. Create `AVAssetExportSession(asset:, presetName: AVAssetExportPresetMediumQuality)`
4. Set `outputURL` to a unique file in `FileManager.default.temporaryDirectory`
5. `await exportSession.export()`
6. On success: call `SessionStore.shared.updateClip(eventId: event.id, url: outputURL)`

Process events serially (one export at a time) to avoid iOS throttling.

---

### 5. SessionStore — ObservableObject + updateClip

```swift
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

`updateClip()` must be called on the main queue (background Task uses `await MainActor.run { }` before calling it).

---

### 6. ContentView — observe SessionStore

`ContentView` (or whichever view owns navigation to `ResultsView`) needs to observe `SessionStore.shared` so it re-renders when clips arrive and passes updated events to `ResultsView`.

Change the `ResultsView` call site from:
```swift
ResultsView(state: state, events: SessionStore.shared.currentEvents, onBack: onBack)
```
to observe the store:
```swift
@ObservedObject private var store = SessionStore.shared
// ...
ResultsView(state: state, events: store.currentEvents, onBack: onBack)
```

---

### 7. RecordingHUD — Approach A target card + result flash

Add a new `CurrentMoveCard` view above the progress bar in `RecordingHUD`. It receives `currentTargetMove: Move?` and `lastWindowResult: WindowResult?`.

**Idle state** (during window, no result yet): Shows the expected move glyph + name + a 3-second countdown bar (driven by `elapsedSeconds % 3`).

**Result flash** (when `lastWindowResult != nil`, lasts 1.5s): The card background flashes — green with a checkmark if `matched`, red/dim if not matched (showing detected move name). Uses `.animation(.easeOut(duration: 0.3))`.

`RecordingHUD` gains two new parameters: `currentTargetMove: Move?` and `lastWindowResult: WindowResult?`. The call site in `RecordingView` passes `sessionManager.currentTargetMove` and `sessionManager.lastWindowResult`.

---

## Status Tiers

Consistent with existing `PostSessionAnalyzer.buildEvent()` tiers:

| Confidence | Status | Color |
|---|---|---|
| > 0.80 | `.correct` | Green — no clip |
| 0.51–0.80 | `.unclear` | Yellow — clip extracted |
| ≤ 0.50 | `.wrong` | Red — clip extracted |

Events where no valid move was detected (body not found, no movement) are not emitted as `SessionEvent`s — they are silently skipped. If a window produces no event, the fallback `generateEvents()` gap is acceptable.

---

## Fallback Behavior (unchanged)

If `liveSessionEvents` is empty at session end (no camera available, or all windows had no body detected):
- `finalizeSession()` falls through to the existing path: calls `PostSessionAnalyzer.analyze(videoURL:)` (still a stub → returns `[]`) → falls back to `generateEvents()`.
- The debug video override path is also unchanged.

---

## Testing

- `MLInferenceEngine`: unit test buffer filling, joint extraction with a mock observation, MLMultiArray shape, label mapping. Test that buffer resets between sessions.
- `MovementAggregator`: already tested.
- `SessionManager.endMoveWindow()`: unit test that a matching prediction produces `.correct` event, mismatched produces `.wrong`, empty predictions produce no event.
- `SessionStore.updateClip()`: unit test that event at correct index gets updated clipURL, other events unchanged.
- `PostSessionAnalyzer.extractClips()`: no unit test — AVAssetExportSession requires real video file. Verified on device.
