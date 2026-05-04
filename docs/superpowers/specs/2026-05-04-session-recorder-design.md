# SessionRecorder + PostSessionAnalyzer + VideoPlayerView
**Date:** 2026-05-04
**Project:** BoxMaxxingFinal (ShadowBox)
**Status:** Approved — ready for implementation planning

---

## Problem Being Solved

The existing `ClipRecorder.swift` records individual 3-second clips per move window using `AVAssetWriter`. This approach has known bugs (race conditions, thread-safety issues, hardcoded resolution) and conflates recording, analysis, and clip management into one complex class. It is being replaced entirely.

---

## Core Idea

Record the entire 2-minute session as one continuous `.mov` file. After recording ends, analyze the full video using a 60-frame sliding window (PostSessionAnalyzer). In the Results screen, seek `AVPlayer` to the event timestamp instead of loading a separate clip file — like YouTube timestamps on a single video.

---

## Architecture: Three Phases

```
PHASE 1 — RECORDING (2 minutes)
  Camera feeds two outputs simultaneously:
  ├── AVCaptureVideoDataOutput → per-frame ML inference → live punch chips (HUD only)
  └── AVCaptureMovieFileOutput → SessionRecorder → one continuous .mov on disk

PHASE 2 — ANALYSIS (after recording ends, "Reviewing…" spinner shown)
  PostSessionAnalyzer reads the .mov file
  └── 60-frame sliding window → groups → events → [SessionEvent]

PHASE 3 — RESULTS (on demand, per tap)
  VideoPlayerView(url: sessionFile, startSeconds: event.time)
  └── AVPlayer seeks to event timestamp → plays inline
```

Nothing runs in parallel. Phase 1 finishes completely before Phase 2 starts.

---

## Components

### 1. SessionRecorder.swift (new — replaces ClipRecorder.swift)

**Responsibility:** Own `AVCaptureMovieFileOutput`, manage the single session file.

**Key properties:**
- `static let shared` — singleton, accessible by both CameraView and SessionManager
- `let movieFileOutput: AVCaptureMovieFileOutput` — added to CameraView's AVCaptureSession at startup
- `var debugVideoOverride: URL?` — when set, SessionManager skips live recording and feeds this URL to PostSessionAnalyzer instead
- `private(set) var lastRecordedURL: URL?` — the most recently recorded file

**Key methods:**
- `startRecording()` — calls `movieFileOutput.startRecording(to: documentsDir/session_<timestamp>.mov)`
- `stopRecording() async throws -> URL` — suspends via `withCheckedThrowingContinuation` until `AVCaptureFileOutputRecordingDelegate` fires, then resumes with the file URL
- `deleteSessionFile()` — removes `lastRecordedURL` from disk

**Why NSObject:** `AVCaptureFileOutputRecordingDelegate` is an Objective-C protocol; Swift classes conforming to it must inherit from `NSObject`.

**File naming:** `session_<unix_timestamp>.mov` stored in the app's Documents directory.

**Audio:** No microphone input is added to the AVCaptureSession, so the recording is video-only.

---

### 2. PostSessionAnalyzer.swift (new)

**Responsibility:** Analyze the session video file using a 60-frame sliding window and return `[SessionEvent]`.

**Key constants:**
- `clipPaddingSeconds: Double = 0.5` — padding added to each side of playback range
- `windowSize: Int = 60` — frames per window (must match Create ML training config)
- `strideSize: Int = 15` — frames to advance after each prediction

**Sliding window pipeline:**
```
analyze(videoURL:) async -> [SessionEvent]
  Step 1: Extract frames via AVAssetReader              — TODO (needs CoreML model)
  Step 2: Vision pose detection per frame               — TODO (needs CoreML model)
  Step 3: Buffer 60 frames → run MLInferenceEngine      — TODO (needs CoreML model)
  Step 4: Filter ≤20% (undetected) and >80% (correct)  — TODO (needs CoreML model)
  Step 5: groupWindows() — consecutive same-label windows → one group
  Step 6: selectRepresentative() — highest confidence per group
  Step 7: buildEvent() — apply padding, set clipURL, build SessionEvent
  Step 8: Sort chronologically, return
```

Steps 1–4 require the CoreML `.mlmodel` file and return `[]` until it is integrated.
Steps 5–7 are fully implementable now — no model needed.

**Supporting type:**
```swift
struct WindowPrediction {
    let label: String       // e.g. "lj" — must match Move.id in Models.swift
    let confidence: Float   // 0.0–1.0
    let startTime: Double   // seconds from video start
    let endTime: Double     // startTime + (windowSize / fps)
}
```

**Confidence tiers (from SHADOWBOX_APP_REQUIREMENTS.md):**
| Range | Action |
|---|---|
| 0.00–0.20 | Filter out (undetected) |
| 0.21–0.50 | Keep as SessionEvent, status = .wrong |
| 0.51–0.80 | Keep as SessionEvent, status = .unclear |
| 0.80+ | Filter out (correct) |

**clipURL assignment in buildEvent:**
- Confidence > 0.80 → `clipURL = nil` (green, not shown)
- All others → `clipURL = sessionFileURL` (seek target)

**Grouping rule:** Consecutive `WindowPrediction` values with the same label and a time gap < 0.5s between them belong to the same group. A new group starts when the label changes or the gap exceeds 0.5s.

**Representative window:** The `WindowPrediction` with the highest confidence within a group. Its `startTime` becomes `SessionEvent.time` (the seek target for VideoPlayerView).

**Padding:**
```
paddedStart = max(0, window.startTime - clipPaddingSeconds)
paddedEnd   = min(videoDuration, window.endTime + clipPaddingSeconds)
```
Padding is computed inside `buildEvent` but the padded values are not stored on `SessionEvent` — `Models.swift` is not modified and has no `playbackStartTime`/`playbackEndTime` fields. `VideoPlayerView` seeks to `event.time` (the representative window's unpadded start). Padding can be introduced later by extending `SessionEvent` in `Models.swift` when the full pipeline is wired.

---

### 3. VideoPlayerView.swift (new)

**Responsibility:** A reusable SwiftUI view that wraps AVPlayer, seeks to a timestamp, and plays automatically.

**Interface:**
```swift
VideoPlayerView(url: URL, startSeconds: Int)
```

**Implementation:** `UIViewRepresentable` wrapping a `UIView` with an `AVPlayerLayer` sublayer.

**Why UIViewRepresentable:** SwiftUI has no native view that gives low-level access to `AVPlayerLayer`. `UIViewRepresentable` lets us drop a UIKit `UIView` into SwiftUI layout.

**Why Coordinator:** `makeUIView` runs once. `updateUIView` runs on every SwiftUI re-render. The `Coordinator` stores `AVPlayer` and `AVPlayerLayer` so they survive re-renders without restarting playback.

**Seek precision:** Uses `toleranceBefore: .zero, toleranceAfter: .zero` for frame-accurate seeking. Default tolerance can snap to the nearest keyframe (up to ~1s off), which is unacceptable when events are 3 seconds apart.

**Lifecycle:** `Coordinator.deinit` calls `player?.pause()` — stops playback automatically when the detail sheet is dismissed.

**Usage in DetailSheetView:**
```swift
// Replaces VideoPanel placeholder (one line change)
VideoPlayerView(url: event.clipURL!, startSeconds: event.time)
    .frame(height: 220)
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .padding(.bottom, 22)
```
The force-unwrap is safe — this code is inside the `else` branch that already checks `event.clipURL != nil`.

---

### 4. SessionManager.swift (modified)

**Additions:**
- `@Published var isAnalyzing = false` — drives "Reviewing…" spinner duration in RecordingView

**startSession change:** Conditionally skips `SessionRecorder.shared.startRecording()` when `debugVideoOverride` is set — no live recording is started when testing with a sample file:
```swift
func startSession() {
    // ...existing setup...
    if SessionRecorder.shared.debugVideoOverride == nil {
        SessionRecorder.shared.startRecording()
    }
    startSessionTimer()
    beginMoveWindow()
}
```

**Removals:**
- All `ClipRecorder.shared.*` calls (3 sites: appendFrame, startClip, stopAndEvaluate)
- `collectedEvents: [SessionEvent]` array — no longer needed
- Event-building logic inside `endMoveWindow`

**endMoveWindow after change:** Advances `currentMoveIndex` and `globalWindowIndex`, then calls `beginMoveWindow()`. No event building.

**processFrame after change:** Removes `ClipRecorder.shared.appendFrame(pixelBuffer)`. Vision + ML inference for live punch chips continues unchanged.

**finalizeSession — new async/await pipeline:**
```swift
func finalizeSession() {
    guard isRecording else { return }
    sessionTimer?.invalidate(); windowTimer?.invalidate()
    isRecording = false    // → RecordingView: phase = .done
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
                events: events,
                startDate: sessionStartDate ?? Date(),
                duration: TimeInterval(elapsedSeconds)
            )
        } catch {
            SessionStore.shared.save(events: [], startDate: Date(), duration: 0)
        }
        isAnalyzing = false    // → RecordingView: onFinish()
    }
}
```

**Why @MainActor on Task:** @Published properties must update on the main thread. @MainActor is a compiler-enforced guarantee — it replaces manual `DispatchQueue.main.async` around every UI update.

**Why do/catch:** `stopRecording()` throws if the file write fails (disk full, permissions). The catch block ensures the app never gets stuck on the Reviewing screen — it navigates to Results with an empty timeline.

---

### 5. RecordingView.swift (two small changes)

**Change 1 — CameraView.startSession():** Add `SessionRecorder.shared.movieFileOutput` to the `AVCaptureSession` after the existing `AVCaptureVideoDataOutput`:
```swift
let movieOutput = SessionRecorder.shared.movieFileOutput
if session.canAddOutput(movieOutput) {
    session.addOutput(movieOutput)
}
```
This output must be added to the session before `startRecording()` is called. It is added once at camera setup and stays for the lifetime of the view.

**Change 2 — onChange watchers:** Replace the single `isRecording` watcher (which had a hardcoded 0.6s delay) with two watchers:
```swift
.onChange(of: sessionManager.isRecording) { _, newValue in
    if !newValue && phase == .recording {
        phase = .done   // shows ReviewingOverlay immediately
    }
}
.onChange(of: sessionManager.isAnalyzing) { _, analyzing in
    if !analyzing && phase == .done {
        onFinish()      // navigates only when analysis is complete
    }
}
```
The 0.6s hardcoded delay is removed. Navigation now waits for the actual analysis to finish.

---

### 6. ContentView.swift (two-line swap)

Replace both `ClipRecorder.shared.deleteAllClips()` calls:
```swift
// onBack handler + onAppear
SessionRecorder.shared.deleteSessionFile()
```

---

### 7. ClipRecorder.swift (delete)

The entire file is removed. No logic from it is carried forward.

---

## Debug Video Override

For testing `PostSessionAnalyzer` with a real video before the CoreML model is integrated:

1. Add a sample `.mov` to the Xcode project bundle
2. Set `SessionRecorder.shared.debugVideoOverride = Bundle.main.url(forResource: "sample_session", withExtension: "mov")`
3. Run the app — the full pipeline executes on that file every session
4. When shipping, set `debugVideoOverride = nil`

When the override is set, `SessionRecorder.startRecording()` and `stopRecording()` are never called.

---

## Files Changed Summary

| File | Change |
|---|---|
| `SessionRecorder.swift` | Create (replaces ClipRecorder) |
| `PostSessionAnalyzer.swift` | Create |
| `VideoPlayerView.swift` | Create |
| `SessionManager.swift` | Modify (remove ClipRecorder, add isAnalyzing, new finalizeSession) |
| `RecordingView.swift` | Modify (wire movieFileOutput, fix onChange watchers) |
| `ResultsView.swift` | Modify (one line: VideoPanel → VideoPlayerView) |
| `ContentView.swift` | Modify (two lines: ClipRecorder → SessionRecorder cleanup) |
| `ClipRecorder.swift` | Delete |
| `Models.swift` | No change |
| `MenuView.swift` | No change |
| `MoveGlyphView.swift` | No change |

---

## Outstanding TODOs (not in scope for this build)

| Gap | File | Unlocked by |
|---|---|---|
| Sliding window frame extraction + inference | `PostSessionAnalyzer.analyze()` | CoreML `.mlmodel` from dev team |
| Audio cue `.mp3` files | `AudioCuePlayer` | Asset files from developer |
| Reference movement videos | `DetailSheetView` second VideoPanel | Reference `.mp4` files from developer |

---

## Verification Steps

1. After a session: print `SessionRecorder.shared.lastRecordedURL` and confirm `.mov` exists in Device File Browser
2. Hardcode `startSeconds: 5` in VideoPlayerView and confirm video jumps to correct moment
3. Tap a Yellow/Red event in ResultsView and confirm video seeks to that event's timestamp
4. Navigate back to menu and confirm `.mov` is deleted (Device File Browser)
5. Tap a Green event and confirm no video player appears (`clipURL` is nil)
6. Set `debugVideoOverride` to a sample file and confirm the analyzer receives it
