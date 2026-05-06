# Wrong Movement Detection & Video Seek Design

## Goal

Replace per-window `SessionEvent` accumulation and `AVAssetExportSession` clip extraction with a per-frame `MovementDetector` state machine that stamps `CMTime` timestamps for wrong movements. `AVPlayer.seek(to:)` replaces clip files — the full session video is kept as-is and seeked on demand. Also fixes the model loading bug (`"80 epoch"` + `"mlmodel"` → `"80_epoch"` + `"mlmodelc"`).

## Architecture — Three Phases

**During recording:** The camera delivers `(CVPixelBuffer, CMTime)` per frame. `MLInferenceEngine.predictMove()` runs as before. Each result feeds `MovementDetector.process(prediction:timestamp:expectedMoveId:)`. When the detector confirms a wrong movement — 3 consecutive frames with the same label, where the result is wrong move or low confidence vs expected — it returns a `WrongMovement` that `SessionManager` appends to `liveWrongMovements`.

**Session ends:** `finalizeSession()` calls `SessionRecorder.shared.stopRecording()` to get the video URL. `SessionStore.shared.save(movements:videoURL:startDate:duration:)` stores both atomically. `isAnalyzing = false` immediately — no background processing, no file I/O after this point.

**Results screen:** `ResultsView` reads `store.wrongMovements` for stats and list. Tapping a row opens `DetailSheetView(movement:videoURL:)` which initialises `AVPlayer(url: videoURL)` and seeks to `movement.timestamp − 0.5 s` on appear.

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `BoxMaxxingFinal/Models.swift` | Add `WrongMovement`, remove `SessionEvent` |
| Create | `BoxMaxxingFinal/Services/MovementDetector.swift` | 3-state machine |
| Modify | `BoxMaxxingFinal/Services/SessionStore.swift` | `[WrongMovement]` + `videoURL`, remove `updateClip()` |
| Modify | `BoxMaxxingFinal/Services/MLInferenceEngine.swift` | Fix resource name and extension |
| Modify | `BoxMaxxingFinal/RecordingView.swift` | `onFrame: (CVPixelBuffer, CMTime) -> Void` |
| Modify | `BoxMaxxingFinal/Services/SessionManager.swift` | Use `MovementDetector`, pass `CMTime`, updated `finalizeSession()` |
| Modify | `BoxMaxxingFinal/Services/PostSessionAnalyzer.swift` | Remove `extractClips()` |
| Modify | `BoxMaxxingFinal/ResultsView.swift` | Stats + list from `wrongMovements`, `AVPlayer` detail sheet |
| Modify | `BoxMaxxingFinal/ContentView.swift` | Remove `@ObservedObject store`, pass values directly |

---

## Component Designs

### 1. Models.swift — WrongMovement

Remove `SessionEvent` and its extension (`movementState`, `confidencePercentage`, `hasClip`).
Keep `WindowResult` (still used by `CurrentMoveCard` HUD).
Keep `LivePunch`, `SkeletonFrame`, `SessionState`, `FramePrediction`.

Add after `LivePunch`:

```swift
// MARK: - Wrong Movement

struct WrongMovement: Identifiable {
    let id = UUID()
    let timestamp: CMTime       // presentation time of the first confirming frame — used for seek
    let expectedMove: Move      // what the combo asked for this window
    let detectedMoveId: String  // what the model actually saw (always a valid Move.id)
    let confidence: Float       // average confidence of the 3 confirming frames

    var isWrongTechnique: Bool { detectedMoveId != expectedMove.id }
}
```

A `WrongMovement` is emitted when a confirmed movement is wrong:
- **Bad execution:** `detectedMoveId == expectedMove.id` but `confidence < 0.80`
- **Wrong technique:** `detectedMoveId != expectedMove.id` (regardless of confidence)

Remove `generateEvents()` and `formatTime` is kept (still used by `ResultsView`).

---

### 2. MovementDetector (new file)

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

    /// Call on every camera frame. Returns a WrongMovement when one is confirmed, nil otherwise.
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
            // Confirmed — evaluate
            let avgConfidence = newSum / Float(newFrames)
            let cooldownEnd   = CMTimeAdd(timestamp, CMTime(seconds: cooldownSeconds,
                                                            preferredTimescale: 600))
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

Thread safety: `process()` is called from `DispatchQueue.main.async` inside `processFrame`, same as existing `@Published` mutations. No lock needed.

---

### 3. SessionStore

Replace entire file:

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
        wrongMovements   = movements
        self.videoURL    = videoURL
        sessionStartDate = startDate
        sessionDuration  = duration
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

---

### 4. MLInferenceEngine — model loading fix

In `loadModel()`, change:
```swift
// Before
Bundle.main.url(forResource: "80 epoch", withExtension: "mlmodel")
// After
Bundle.main.url(forResource: "80_epoch", withExtension: "mlmodelc")
```

No other changes to `MLInferenceEngine`.

---

### 5. CameraView — pass CMTime

In `RecordingView.swift`:

`CameraView.onFrame` signature change:
```swift
var onFrame: ((CVPixelBuffer, CMTime) -> Void)?
```

In `captureOutput(_:didOutput:from:)`:
```swift
let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
onFrame?(pixelBuffer, pts)
```

`CameraPreviewView.makeUIView` and `updateUIView` update the `onFrame` closure type accordingly.

`RecordingView` call site:
```swift
CameraPreviewView(onFrame: { [sessionManager] buffer, timestamp in
    sessionManager.processFrame(buffer, timestamp: timestamp)
})
```

---

### 6. SessionManager

**New properties:**
```swift
private let detector = MovementDetector()
private var liveWrongMovements: [WrongMovement] = []
```

Remove: `liveSessionEvents`, `windowResultToken` (keep `lastWindowResult` for HUD flash).

**`processFrame(_:timestamp:)`** — add `timestamp: CMTime` parameter:
```swift
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
```

**`configure()`** additions: `liveWrongMovements = []`, `detector.reset()`.

**`startSession()`** additions: `liveWrongMovements = []`, `detector.reset()`.

**`beginMoveWindow()`** — add `detector.reset()` at the top (clears any in-progress confirmation from the previous window before starting a new expected move).

**`endMoveWindow()`** — remove the `SessionEvent` building block and `lastWindowResult` publish. With `MovementAggregator` removed there is no window-level result to flash. Keep: clear `currentFramePredictions`, increment indices, call `beginMoveWindow()`. `lastWindowResult` stays nil throughout recording — `CurrentMoveCard` shows only its idle state (expected move + "NOW").

**`finalizeSession()`** — replace entirely:
```swift
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
    Task { @MainActor in
        do {
            let videoURL = try await SessionRecorder.shared.stopRecording()
            SessionStore.shared.save(movements: movementsSnapshot,
                                     videoURL: videoURL,
                                     startDate: sessionStartDate ?? Date(),
                                     duration:  TimeInterval(elapsedSeconds))
        } catch {
            SessionStore.shared.save(movements: movementsSnapshot,
                                     videoURL: nil,
                                     startDate: sessionStartDate ?? Date(),
                                     duration:  TimeInterval(elapsedSeconds))
        }
        isAnalyzing = false
    }
}
```

Zero wrong movements is a valid result (clean session). No fallback to `generateEvents()`.

---

### 7. PostSessionAnalyzer

Remove `extractClips(videoURL:events:)`. Keep `analyze(videoURL:)` stub and all helper methods (`groupWindows`, `selectRepresentative`, `buildEvent`) — they are tested and may be used in a future offline analysis path.

---

### 8. ResultsView

`ResultsView` signature: replace `events: [SessionEvent]` with `wrongMovements: [WrongMovement]`, add `videoURL: URL?`.

**Stats row** (3 cards):
- `Wrong` — `wrongMovements.count`
- `Bad technique` — `wrongMovements.filter { $0.isWrongTechnique }.count`
- `Avg conf` — `Int(wrongMovements.map { Double($0.confidence) }.reduce(0,+) / Double(max(wrongMovements.count,1)) * 100)%`

**Timeline:** `ForEach(wrongMovements)` — each row shows: expected move glyph + name, detected move name if `isWrongTechnique`, confidence %, timestamp. Tapping opens `DetailSheetView`.

**`DetailSheetView`** — simplified, no store observation:
```swift
struct DetailSheetView: View {
    let movement: WrongMovement
    let videoURL: URL?
    @StateObject private var playerHolder = PlayerHolder()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let url = videoURL {
                    VideoPlayer(player: playerHolder.player)
                        .aspectRatio(9/16, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.bottom, 20)
                        .onAppear {
                            playerHolder.load(url: url, seekTo: movement.timestamp)
                        }
                        .onDisappear { playerHolder.player.pause() }
                }
                // Hero header: expected move glyph + name
                // If isWrongTechnique: detection mismatch block (expected → detected)
                // Confidence bar
                // Coach note (PerformanceFeedback.suggestion for expectedMove.id)
                // Form checklist (existing formChecklist logic, keyed on expectedMove.kind)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }
}

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
```

`@StateObject private var playerHolder = PlayerHolder()` ensures one player per sheet lifetime.

---

### 9. ContentView

Remove `@ObservedObject private var store = SessionStore.shared`.

`case .results:` passes values read once at navigation time:
```swift
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
```

---

## What Is Removed

| Removed | Replaced by |
|---------|------------|
| `SessionEvent` + extension | `WrongMovement` |
| `MovementAggregator` | `MovementDetector` state machine |
| `PostSessionAnalyzer.extractClips()` | Nothing — no clip files |
| `SessionStore.updateClip()` | Nothing — video URL is set once |
| `SessionStore.currentEvents` | `SessionStore.wrongMovements` |
| `ContentView @ObservedObject store` | Direct read at navigation time |
| `DetailSheetView eventId + store observation` | `WrongMovement` value + `videoURL` |
| `generateEvents()` fallback | Zero wrong movements = clean session |
| Background clip Task | Nothing |

---

## Testing

- **`MovementDetector`**: unit test idle→confirming transitions, 3-frame confirmation, label-change reset to idle, cooldown blocking then resuming, wrong-technique emission, low-confidence-correct-move emission, matched correct move produces nil
- **`SessionStore`**: update tests to use `WrongMovement` and `videoURL`; verify `clear()` resets `videoURL`
- **`ResultsView` stats**: unit test computed values from `[WrongMovement]` fixtures
