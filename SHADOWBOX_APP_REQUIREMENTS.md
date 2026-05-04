# ShadowBox iOS App — Complete Requirements & Architecture Document
# Project: BoxMaxxingFinal

---

## 🤖 Instructions for Claude Code — READ THIS FIRST

> **These instructions must be followed before writing a single line of code.**

---

### 1. Current Project State (BoxMaxxingFinal)

The Xcode project **BoxMaxxingFinal** already exists with the following 7 files built and in place. **Do not recreate, rewrite, or restructure any of them** unless explicitly told to do so.

| File | Status | What It Does |
|---|---|---|
| `ContentView.swift` | ✅ Done | App routing — navigates Menu → Recording → Results using opacity transitions |
| `Models.swift` | ✅ Done | Core domain models: `Move`, `Combo`, `SessionEvent`, `SessionState`. Contains `allMoves`, `allCombos`, and `generateEvents()` |
| `MoveGlyphView.swift` | ✅ Done | Canvas-drawn visual glyphs for each punch type, with mirroring logic for right-side moves |
| `MenuView.swift` | ✅ Done | Start screen — title bar, combo picker with numbered badges, 3x2 move grid, Start button |
| `RecordingView.swift` | ✅ Done | Live session screen — `AVCaptureSession` camera preview, setup hint sheet, 3-2-1 countdown, recording HUD (REC pill, live detection chips, progress bar, stop button), "Reviewing…" spinner |
| `ResultsView.swift` | ✅ Done | Results screen — session stats (Wrong/Unclear/Avg Confidence), vertical timeline with spine and event dots, tappable event cards, bottom sheet with clip panels, confidence bars, form suggestions, correct form visuals |
| `project.pbxproj` | ✅ Done | `NSCameraUsageDescription` permission key added |

---

### 2. What You Need to Build Next

Your job is to implement the **backend logic** that powers the existing views. The views are already built — they need real data and real services wired into them.

**Read `Models.swift` first** to understand the existing data structures (`Move`, `Combo`, `SessionEvent`, `SessionState`) before building anything. All backend logic must use and extend these existing models — do not create duplicate or conflicting model files.

#### Files to Create:

```
Services/SessionManager.swift       — orchestrates the full 2-min session loop + full video recording
Services/VisionProcessor.swift      — Vision framework body pose detection (used during recording for calibration UI only)
Services/MLInferenceEngine.swift    — CoreML Action Classifier inference (placeholder)
Services/AudioCuePlayer.swift       — plays audio cues per move (placeholder assets)
Services/PostSessionAnalyzer.swift  — runs sliding window analysis on full session video after recording ends
Services/VideoRangePlayer.swift     — AVPlayer wrapper for ranged playback using seek + forwardPlaybackEndTime
Services/SessionStore.swift         — in-memory storage of session result and main video URL

Utilities/ResultExporter.swift      — exports full scrollable Result screen as JPG
Utilities/PerformanceFeedback.swift — contextual feedback text per rating
Utilities/ColorExtensions.swift     — performanceColor() and performanceLabel() helpers
```

> ⚠️ **Do NOT create new model files.** Extend or reference the existing `Models.swift` types instead.

---

### 3. Understand the Existing Models Before Building

Before writing any service, read `Models.swift` carefully. The existing types are:

- **`Move`** — represents a single boxing punch (jab, straight, hook, uppercut variants)
- **`Combo`** — an ordered sequence of `Move` values
- **`SessionEvent`** — represents one movement result entry (the equivalent of `MovementEntry` in this document — use this, not a new struct)
- **`SessionState`** — the overall state of a recording session
- **`allMoves`** — static array of all 6 supported moves
- **`allCombos`** — static array of all 6 pre-defined combos (do not change these)
- **`generateEvents()`** — currently generates placeholder/mock session data for the Results view

Your job is to **replace `generateEvents()` with real data** coming from the actual ML inference pipeline once the session completes.

---

### 4. Build Order — Follow This Exactly

Implement in this strict sequence. Do not skip ahead or build out of order:

1. **Read all existing files** — understand models, view bindings, and state flow first
2. **`ColorExtensions.swift`** — `Color.performanceColor(for:)` and `Color.performanceLabel(for:)`
3. **`PerformanceFeedback.swift`** — feedback text per move and rating
4. **`SessionStore.swift`** — in-memory store for `SessionState` + main video URL
5. **`VisionProcessor.swift`** — Vision body pose detection wrapper (calibration UI only)
6. **`MLInferenceEngine.swift`** — CoreML Action Classifier placeholder wrapper
7. **`AudioCuePlayer.swift`** — AVFoundation audio cue player with placeholder asset slots
8. **`SessionManager.swift`** — full session orchestration (timer, move sequencing, full video recording via AVAssetWriter)
9. **`PostSessionAnalyzer.swift`** — sliding window analysis on recorded video, event grouping, representative window selection
10. **`VideoRangePlayer.swift`** — AVPlayer ranged playback wrapper
11. **`ResultExporter.swift`** — full scrollable JPG export
12. **Wire into views** — inject `SessionManager`, `SessionStore`, and `VideoRangePlayer` into `RecordingView` and `ResultsView` last

---

### 5. Placeholders — Leave These Exactly As-Is

The following components are **intentionally unimplemented**. Leave placeholder `// TODO` comments. Do not invent fake data or stub logic that pretends to work:

| Placeholder | File | Owner |
|---|---|---|
| CoreML `.mlmodel` file | `MLInferenceEngine.swift` | Dev Team |
| Audio cue `.mp3` files (6 files) | `AudioCuePlayer.swift` | Developer |
| Correct movement `.mp4` reference videos | `ResultsView.swift` bottom sheet | Developer |

---

### 6. Behaviour Rules — Non-Negotiable

#### Session
- Duration: exactly **2 minutes (120 seconds)** — fixed, not configurable
- Audio cues fire every **3 seconds** to prompt the next move — fixed
- Combo loops continuously until timer expires or user stops
- The full session is recorded as **one continuous video file** saved to temp storage

#### Camera Calibration
- The setup hint sheet in `RecordingView` is a **UX reminder only** — not a hard gate
- "I'm Ready" is always tappable — do not add any lock condition

#### Post-Session Analysis
- Runs **after** recording ends — not during
- Uses Apple CoreML Action Classifier with **60-frame sliding window @ 30fps** (= 2-second window)
- Full session video is fed through the analyzer frame by frame
- Each window produces: `{ label, confidence, windowStartTime, windowEndTime }`
- **Filter:** confidence ≤ 20% → ignored entirely (undetected)
- **Filter:** confidence > 80% → ignored (correct, not shown in results)
- **Group:** consecutive overlapping windows of the same label → one `SessionEvent`
- **Representative window:** highest confidence window within a group is selected
- **Rating:** based on representative window confidence (21–50% = Red, 51–80% = Yellow)
- **Playback range:** representative window start/end ± 0.5s padding (configurable via `clipPaddingSeconds` constant)
- Results timeline order: **chronological**

#### Stop Button
- Tapping Stop shows a **confirmation dialog** — session timer keeps running in background
- If 2-minute timer expires while dialog is open: stop recording, begin analysis, navigate to Results automatically
- Result screen always shows regardless of how many moves were completed

#### Ranged Playback (No Clip Extraction)
- No physical video clips are extracted or written to disk
- The main session video file is reused for all event playback
- Each `SessionEvent` stores `playbackStartTime` and `playbackEndTime` (padded window range)
- `VideoRangePlayer` seeks to `playbackStartTime` and sets `forwardPlaybackEndTime` on the same `AVPlayer`

#### Main Video Storage Lifetime
- Main video saved to **temp directory** during recording
- Remains in temp directory while Results screen is shown (needed for playback)
- User can tap **Save** button on Results screen to copy to permanent Photo Library
- Deleted when user **navigates away from Results screen**
- Deleted on **app launch** (startup cleanup from any previous session)

#### JPG Export
- Must capture the **entire scrollable content** of `ResultsView` — not just the visible viewport
- One long image including all timeline events and session stats

---

### 7. Performance Color System

| Confidence | Color | Label | Shown in Results |
|---|---|---|---|
| 0–20% | — | Undetected | ❌ Not shown |
| 21–50% | 🔴 `Color.systemRed` | Wrong Move | ✅ Shown |
| 51–80% | 🟡 `Color.systemYellow` | Needs Adjustment | ✅ Shown |
| 80%+ | 🟢 `Color.systemGreen` | Correct | ❌ Not shown |

---

### 8. Static Combo List — Do Not Change

The `allCombos` array in `Models.swift` is already defined and must not be modified. It must match exactly what `MenuView.swift` displays. Do not add, remove, or rename any combo.

---

### 9. Quick Reference Summary

| Rule | Decision |
|---|---|
| Existing files | Do not modify — read and extend only |
| New model files | Do not create — use types from `Models.swift` |
| `generateEvents()` | Replace with real pipeline output from `PostSessionAnalyzer` |
| Build order | Strict — follow Step 4 above |
| Placeholders | Leave all `// TODO` exactly as written |
| Session duration | 2 minutes, fixed |
| Audio cue interval | Every 3 seconds, fixed |
| Analysis timing | Post-recording only — full video analyzed after session ends |
| Action Classifier window | 60 frames @ 30fps = 2-second window |
| Confidence: 0–20% | Undetected — ignored entirely, not shown |
| Confidence: 21–50% | Wrong Move 🔴 — shown in results |
| Confidence: 51–80% | Needs Adjustment 🟡 — shown in results |
| Confidence: 80%+ | Correct — not shown in results |
| Window grouping | Consecutive same-label overlapping windows → one event |
| Representative window | Highest confidence window within group |
| Playback | Ranged playback on main video — no clip extraction |
| Playback padding | 0.5s each side (configurable via `clipPaddingSeconds`) |
| Main video storage | Temp until user leaves Results or app closes |
| Save video | User-initiated via Save button → Photo Library |
| Stop dialog | Timer keeps running; auto-finalizes if time expires |
| Calibration | UX reminder only, always tappable |
| Live log | Removed — all evaluation shown post-session on Results screen |
| Results order | Chronological |
| JPG export | Full scrollable content, not visible area only |

---

**Project Name:** BoxMaxxingFinal
**Project Status:** Backend Implementation Phase
**Date Created:** May 3, 2026
**Expert Role:** 50-Year Veteran iOS Developer & AI Engineer
**Model Type:** CoreML Action Classifier (Apple Create ML, 60-frame window @ 30fps)
**Document Version:** 6.0 — Post-Recording Analysis Architecture + Ranged Playback

---

## Clarification Log

| # | Topic | Decision |
|---|---|---|
| 1 | Camera Calibration | Reminder-only UX. Always tappable. Mid-session failures continue — not logged, ignored in post-analysis |
| 2 | ML Inference Strategy | Post-recording only — full 2-minute video is analyzed after session ends, not frame-by-frame during recording |
| 3 | Analysis Unit | Apple Action Classifier sliding window — 60 frames @ 30fps = 2-second window per prediction |
| 4 | Manual Stop | Confirmation dialog required. Result page always shows regardless of session length |
| 5 | Main Video Storage | Saved to temp storage during session. User can save permanently via Save button on Results screen |
| 6 | JPG Export | Exports **entire scrollable content** as one long image |
| 7 | Confidence Tiers | 0–20% = undetected (ignored entirely). 21–50% = Wrong Move 🔴. 51–80% = Needs Adjustment 🟡. 80%+ = Correct (not shown) |
| 8 | Clip Strategy | No physical clips extracted. Ranged playback on main video using `AVPlayer` seek + `forwardPlaybackEndTime` |
| 9 | Window Grouping | Consecutive overlapping windows of same label are grouped into one event. Best confidence window selected as representative |
| 10 | Representative Window | Highest confidence window within a grouped event is used for ranged playback timestamps |
| 11 | Playback Padding | 0.5 seconds added before and after the representative window start/end — configurable constant |
| 12 | Live Feedback | Removed. No live log during recording. All evaluation shown on Results screen after analysis completes |
| 13 | Results Timeline Order | Chronological — earliest flagged event first |

---

## Executive Summary

ShadowBox is a shadow boxing training companion app with AI-powered movement analysis. The app guides users through selected boxing combos via audio cues, records the full 2-minute session as a single video file, then analyzes the recording using a CoreML Action Classifier after the session ends. Results are presented as a chronological timeline of flagged events — only Yellow (needs adjustment) and Red (wrong move) events are shown. Each flagged event uses ranged playback on the original video file — no physical clip extraction occurs.

**Key Constraint:** Backend logic must be **tailored to match the final frontend/UI** (not the other way around).

---

## Part 1: Application Architecture Overview

### Three-Page Flow
```
┌─────────────┐
│    MENU     │  (Static combo selection)
└──────┬──────┘
       │ "Start Session"
       ▼
┌─────────────────────────────────┐
│   RECORD                        │
│   Phase 1: Camera Calibration   │
│   Phase 2: 2-min Recording      │
│   Phase 3: Post-Session Analysis│
└──────┬──────────────────────────┘
       │ Analysis complete
       ▼
┌─────────────┐
│   RESULT    │  (Performance summary & flagged event timeline)
└─────────────┘
```

### Tech Stack Required
- **Language:** Swift / SwiftUI
- **Camera & Video Recording:** AVFoundation (`AVCaptureSession` + `AVAssetWriter` for full session video)
- **Vision & Pose:** Vision framework (`VNDetectHumanBodyPoseRequest`)
- **ML Inference:** CoreML Action Classifier (Apple Create ML, 60-frame sliding window @ 30fps)
- **Audio:** AVFoundation (placeholder audio cue files)
- **Ranged Playback:** `AVPlayer` with `seek(to:)` + `forwardPlaybackEndTime` — no clip extraction
- **UI Export:** UIGraphicsImageRenderer (JPG export of full Results screen)
- **Storage:** In-memory session state + temp local file for main session video

---

## Part 2: Page 1 — Menu Screen

### User Flow
1. App opens on Menu screen
2. User sees a list of **static, pre-configured boxing combos**
3. User taps a combo to select it
4. User taps **"Start Session"** button
5. App navigates to Record screen with selected combo

### Static Combo List (Must Match Frontend Exactly)

These combos are **immutable** — do not suggest alternatives or allow custom combos.

| Combo ID | Combo Sequence |
|----------|---|
| 1 | Jab → Straight |
| 2 | Jab → Straight → Left Hook |
| 3 | Jab → Straight → Left Hook → Right Hook |
| 4 | Jab → Left Hook → Straight |
| 5 | Jab → Straight → Left Uppercut → Right Uppercut |
| 6 | Straight → Right Hook → Left Uppercut |

### Backend Responsibilities

```swift
struct BoxingCombo {
    let id: Int
    let name: String
    let sequence: [String]  // ["jab", "straight", ...]
}

class MenuViewModel: ObservableObject {
    let staticCombos: [BoxingCombo] = [
        BoxingCombo(id: 1, name: "Jab-Straight", sequence: ["jab", "straight"]),
        BoxingCombo(id: 2, name: "Jab-Straight-Left Hook", sequence: ["jab", "straight", "left hook"]),
        // ... etc
    ]
    
    @Published var selectedCombo: BoxingCombo?
    
    func startSession(combo: BoxingCombo) {
        // Create session with:
        // - Selected combo
        // - Duration: 2 minutes (120 seconds)
        // - Initialize SessionManager
        // Navigate to Record screen
    }
}
```

### Key Constants
- **Session Duration:** 2 minutes (120 seconds) — fixed, not configurable
- **Combo Count:** 6 static combos — no more, no less
- **Custom Combos:** NOT allowed

---

## Part 3: Page 2 — Record Screen

### Overall Flow

```
┌──────────────────────────────────────┐
│  PHASE 1: CAMERA CALIBRATION         │
│  UX reminder — user positions body   │
│  User taps "I'm Ready"               │
└──────────────┬───────────────────────┘
               │
               ▼
┌──────────────────────────────────────┐
│  PHASE 2: RECORDING                  │
│  2 minutes, audio cues every 3s      │
│  Full session recorded as one video  │
└──────────────┬───────────────────────┘
               │ Recording ends (timer or manual stop)
               ▼
┌──────────────────────────────────────┐
│  PHASE 3: POST-SESSION ANALYSIS      │
│  "Reviewing…" spinner shown          │
│  PostSessionAnalyzer runs on video   │
│  Sliding window → group → rank       │
└──────────────┬───────────────────────┘
               │ Analysis complete
               ▼
┌──────────────────────────────────────┐
│  RESULT SCREEN                       │
│  Chronological timeline of flags     │
│  Ranged playback per event           │
└──────────────────────────────────────┘
```

### Phase 1: Camera Calibration

**Purpose:** A visual reminder step that prompts the user to position themselves so the camera can see their full body before the session begins. It is **not** a hard technical gate — it is a UX reminder only.

**Clarified Rules (v3.0):**
- Calibration is a **reminder screen**, not a strict gating system
- The **"I'm Ready"** button is always available — user decides when they are positioned
- There is **no timeout** on calibration — user waits as long as needed
- If the Vision framework **fails to detect the user mid-session**, the session **continues uninterrupted**
- That undetected window is logged as **"No scan — body not detected"** in the timestamp

**UI/UX:**
- Camera feed displayed in real-time
- Overlay text prompt: **"Position yourself so your full body is visible"**
- Simple visual guide (e.g., a body silhouette outline as a reference)
- **"I'm Ready"** button is always tappable — no hard lock
- User taps **"I'm Ready"** to proceed to recording

**Mid-Session Calibration Failure Behavior:**
```
If Vision detects no body pose during a 3-second window:
→ Session CONTINUES (no pause, no alert)
→ ML inference returns no result
→ Log entry for that timestamp:
   [00:09] Jab → ⚠️ No scan — body not detected  (0%  🔴)
→ Clip is still recorded and kept (Red rating = clip saved)
→ Developer suggestion: "Ensure your full body is visible 
   to the camera throughout the session."
```

**Backend Responsibilities:**

```swift
class VisionProcessor {

    func detectBodyPose(from pixelBuffer: CVPixelBuffer) -> [VNHumanBodyPoseObservation]? {
        // IMPLEMENTATION: Use Vision framework to detect human body pose
        // Return pose observations or nil if no person detected
    }

    func isBodyDetected(observations: [VNHumanBodyPoseObservation]?) -> Bool {
        // Returns true if at least one valid body pose observation exists
        guard let observations = observations, !observations.isEmpty else { return false }
        return true
    }
}
```

### Phase 2: Recording & Shadow Boxing

#### Full Session Video Recording

The entire 2-minute session is recorded as **one continuous video file** using `AVAssetWriter`. This is the source file for all post-session analysis and ranged playback.

- File written to **temp directory** during recording
- Resolution and frame rate must match capture session settings
- File is finalized (`.finishWriting()`) when the session ends
- Audio is **not** recorded in the session video — audio cues are system-only playback

#### Move Sequencing & Audio Cues

- Audio cues fire every **3 seconds** to prompt the next move
- Combo loops continuously until the 2-minute timer expires or user stops
- Audio cues are **UX guidance only** — they do not define clip boundaries
- The model determines move timestamps independently during post-session analysis

**Example (Combo: Jab → Straight):**
```
0:00  → Audio cue: "JAB!"
0:03  → Audio cue: "STRAIGHT!"
0:06  → Audio cue: "JAB!" (loop)
0:09  → Audio cue: "STRAIGHT!"
... (continues until 2:00 or manual stop)
```

#### Session Manager (Core Orchestration)

```swift
class SessionManager: ObservableObject {
    @Published var isRecording: Bool = false
    @Published var currentMoveIndex: Int = 0
    @Published var elapsedTime: TimeInterval = 0
    @Published var showStopConfirmation: Bool = false
    @Published var isAnalyzing: Bool = false  // Shows "Reviewing…" spinner

    let sessionDuration: TimeInterval = 120   // 2 minutes — fixed
    let audioCueInterval: TimeInterval = 3.0  // Audio cue fires every 3s
    let selectedCombo: Combo                  // Uses Combo from Models.swift

    // Full session video writer
    private var sessionVideoWriter: AVAssetWriter?
    private var sessionVideoURL: URL?         // Temp file URL

    var currentMove: Move {
        let loopedIndex = currentMoveIndex % selectedCombo.moves.count
        return selectedCombo.moves[loopedIndex]
    }

    func startRecording() {
        isRecording = true
        setupSessionVideoWriter()   // Begin writing full video to temp file
        startSessionTimer()         // 120s countdown
        startAudioCueTimer()        // Fires every 3s, advances currentMoveIndex
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
    }

    func finalizeSession() {
        isRecording = false
        sessionVideoWriter?.finishWriting {
            self.isAnalyzing = true
            // Hand off to PostSessionAnalyzer
        }
    }

    func startSessionTimer() {
        // Fires every 1 second
        // When elapsedTime >= 120 → call finalizeSession()
    }

    func startAudioCueTimer() {
        // Fires every 3 seconds
        // On fire: play audio cue for currentMove, then advance currentMoveIndex
    }

    func setupSessionVideoWriter() {
        // Create AVAssetWriter writing to temp directory
        // Add AVAssetWriterInput for video track
        // Begin writing session — frames appended from AVCaptureSession delegate
    }
}
```

---

### Phase 3: Post-Session Analysis

This phase runs immediately after recording ends, while the "Reviewing…" spinner is shown. It is entirely separate from the recording pipeline.

#### How the Action Classifier Sliding Window Works

The Apple CoreML Action Classifier processes video using a **sliding window** of fixed frame count:

- **Window size:** 60 frames (as configured in Create ML)
- **Frame rate:** 30fps → each window covers **2 seconds** of video
- **Stride:** the window slides forward by a fixed number of frames after each prediction
- Each window produces one prediction: `{ label: String, confidence: Float }`
- The same physical move will appear across **multiple overlapping consecutive windows** — this is expected

**Example of overlapping windows on one jab rep:**
```
Window @ 3.0s–5.0s:  jab, confidence: 0.41  (red)
Window @ 3.1s–5.1s:  jab, confidence: 0.55  (yellow)
Window @ 3.2s–5.2s:  jab, confidence: 0.71  (yellow)  ← highest
Window @ 3.3s–5.3s:  jab, confidence: 0.63  (yellow)
Window @ 3.4s–5.4s:  jab, confidence: 0.38  (red)
```

These 5 windows all describe the same jab rep — they must be **grouped into one `SessionEvent`**.

#### PostSessionAnalyzer Pipeline

```swift
// FILE: Services/PostSessionAnalyzer.swift

class PostSessionAnalyzer {

    // MARK: - Constants
    let clipPaddingSeconds: Double = 0.5  // Configurable padding on each side of playback range

    // MARK: - Confidence Tiers
    // 0.00–0.20  → undetected  → ignored entirely
    // 0.21–0.50  → wrong move  → 🔴 Red
    // 0.51–0.80  → adjustment  → 🟡 Yellow
    // 0.80+      → correct     → ignored (not shown)

    // MARK: - Main Entry Point
    func analyze(videoURL: URL, completion: @escaping ([SessionEvent]) -> Void) {
        // TODO: Load CoreML model via MLInferenceEngine
        // Step 1: Extract pose observations frame by frame from videoURL
        // Step 2: Feed frames through 60-frame sliding window
        // Step 3: Collect raw window predictions
        // Step 4: Filter out undetected (≤ 20%) and correct (> 80%)
        // Step 5: Group consecutive overlapping same-label windows
        // Step 6: Select representative window (highest confidence) per group
        // Step 7: Build SessionEvent array
        // Step 8: Return sorted chronologically
        completion([])
    }

    // MARK: - Step 5: Group overlapping windows
    func groupWindows(_ predictions: [WindowPrediction]) -> [[WindowPrediction]] {
        // Consecutive windows with same label = one group
        // A new group starts when label changes or there is a time gap
        // Returns array of groups, each group = one physical move occurrence
    }

    // MARK: - Step 6: Select representative window per group
    func selectRepresentative(from group: [WindowPrediction]) -> WindowPrediction {
        // Return window with highest confidence within the group
        return group.max(by: { $0.confidence < $1.confidence })!
    }

    // MARK: - Step 7: Build SessionEvent from representative window
    func buildEvent(from window: WindowPrediction) -> SessionEvent {
        let paddedStart = max(0, window.startTime - clipPaddingSeconds)
        let paddedEnd   = window.endTime + clipPaddingSeconds

        return SessionEvent(
            id: UUID(),
            timestamp: Date(),
            elapsedTime: window.startTime,
            predictedLabel: window.label,
            confidence: window.confidence,
            playbackStartTime: paddedStart,
            playbackEndTime: paddedEnd
        )
    }
}

// MARK: - Supporting Types

struct WindowPrediction {
    let label: String           // e.g. "jab"
    let confidence: Float       // 0.0–1.0
    let startTime: Double       // Seconds from video start
    let endTime: Double         // startTime + window duration
}
```

#### VideoRangePlayer Service

```swift
// FILE: Services/VideoRangePlayer.swift

import AVFoundation
import AVKit

class VideoRangePlayer: ObservableObject {

    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?

    // Set up the player once with the main session video
    func configure(videoURL: URL) {
        playerItem = AVPlayerItem(url: videoURL)
        player = AVPlayer(playerItem: playerItem)
    }

    // Play a specific time range — no clip extraction
    func play(from startSeconds: Double, to endSeconds: Double) {
        guard let player = player else { return }

        let startTime = CMTime(seconds: startSeconds, preferredTimescale: 600)
        let endTime   = CMTime(seconds: endSeconds,   preferredTimescale: 600)

        player.currentItem?.forwardPlaybackEndTime = endTime
        player.seek(to: startTime) { _ in
            player.play()
        }
    }

    func pause() {
        player?.pause()
    }

    func getPlayer() -> AVPlayer? {
        return player
    }
}
```

**Usage in ResultsView event modal:**
```swift
// One shared VideoRangePlayer instance per Results screen
// When user taps a SessionEvent card:
videoRangePlayer.play(
    from: event.playbackStartTime,
    to: event.playbackEndTime
)
```

---

## Part 4: Page 3 — Result Screen

### Display Structure

The Result screen shows a comprehensive performance summary followed by a detailed timestamp breakdown.

#### Section 1: Session Summary Card

**Displays:**
- **Session Date/Time:** When the session occurred
- **Selected Combo:** Name of combo performed (e.g., "Jab-Straight-Left Hook")
- **Duration:** Actual session length in MM:SS format
- **Total Movements Evaluated:** Count of all 3-second windows completed

#### Section 2: Performance Metrics

**4-Metric Display:**

| Metric | Description | Calculation |
|---|---|---|
| **Accurate Movements** | Count of ✅ movements | `events.filter { $0.isAccurate }.count` |
| **Movement Errors** | Count of ❌ movements | `events.filter { !$0.isAccurate }.count` |
| **Accuracy Rate** | Percentage of correct | `(accurate / total) * 100` |
| **Avg Confidence** | Mean confidence score | `events.map { $0.confidence }.average()` |

### Performance Rating System (Color-Coded)

The **Avg Confidence** and individual movement confidence scores are displayed with **color-coded performance ratings**:

| Confidence Range | Color | Rating | Meaning |
|---|---|---|---|
| **85-100%** | 🟢 **GREEN** | Excellent | Very Good Performance |
| **50-84%** | 🟡 **YELLOW** | Fair | Not Good Enough |
| **0-49%** | 🔴 **RED** | Poor | Very Bad Performance |

#### Color Implementation Guidelines

**For Average Confidence Metric:**
```swift
func getConfidenceColor(percentage: Float) -> UIColor {
    switch percentage {
    case 85...100:
        return UIColor.systemGreen  // ✅ Excellent
    case 50...84:
        return UIColor.systemYellow // ⚠️ Fair
    case 0...49:
        return UIColor.systemRed    // ❌ Poor
    default:
        return UIColor.gray
    }
}
```

**For Timestamp Breakdown (Individual Movements):**
```swift
// Each movement entry displays confidence with color coding
[00:03] Jab        → Predicted: Jab        ✅ 92%  🟢 (Green - 85-100%)
[00:06] Straight   → Predicted: Straight   ✅ 88%  🟢 (Green - 85-100%)
[00:09] Jab        → Predicted: Left Hook  ❌ 65%  🟡 (Yellow - 50-84%)
[00:12] Straight   → Predicted: Straight   ✅ 91%  🟢 (Green - 85-100%)
[00:15] Left Hook  → Predicted: Left Hook  ✅ 42%  🔴 (Red - 0-49%)
```

**Visual Indicators:**
- Display a **colored bar** or **background tint** next to each confidence percentage
- Use consistent color palette across:
  - Average Confidence metric card
  - Individual movement entries in timestamp breakdown
  - Movement detail modal (when viewing detailed analysis)

#### Enhanced Data Model with Color Support

```swift
// NOTE: These properties belong on SessionEvent in Models.swift
// Extend SessionEvent to add these computed properties if not already present:

extension SessionEvent {
    var confidencePercentage: Float { confidence * 100 }

    var performanceRating: MovementState {
        switch predictedLabel {
        case "no_body_detected":     return .noScan
        case "no_movement_detected": return .noMovement
        default:
            switch confidencePercentage {
            case 85...100: return .excellent
            case 50...84:  return .fair
            default:       return .poor
            }
        }
    }
}

extension SessionState {
    var overallPerformanceRating: MovementState {
        switch averageConfidencePercentage {
        case 85...100: return .excellent
        case 50...84:  return .fair
        default:       return .poor
        }
    }
}
```

**Usage in SwiftUI:**
```swift
// Display average confidence with color (uses SessionState)
ZStack {
    Circle()
        .fill(sessionState.overallPerformanceRating.color)

    VStack {
        Text("Avg Confidence")
            .font(.caption)
        Text(String(format: "%.1f%%", sessionState.averageConfidencePercentage))
            .font(.title2)
            .fontWeight(.bold)
    }
}

// Display individual movement with color (uses SessionEvent)
HStack {
    Text("[00:03] Jab")
    Spacer()
    HStack(spacing: 4) {
        Circle()
            .fill(event.performanceRating.color)
            .frame(width: 12, height: 12)
        Text(String(format: "%.0f%%", event.confidencePercentage))
            .foregroundColor(event.performanceRating.color)
            .fontWeight(.semibold)
    }
}
```

#### Section 3: Timestamp Breakdown Table

A scrollable list of **all movements** with **color-coded confidence**. **All timestamps are tappable** regardless of rating.

```
[00:03] Jab        → Predicted: Jab               ✅ 92%  🟢  Excellent   (tappable)
[00:06] Straight   → Predicted: Straight          ✅ 88%  🟢  Excellent   (tappable)
[00:09] Jab        → Predicted: Left Hook         ❌ 65%  🟡  Fair        (tappable)
[00:12] Straight   → Predicted: Straight          ✅ 91%  🟢  Excellent   (tappable)
[00:15] Left Hook  → Predicted: Left Hook         ✅ 42%  🔴  Poor        (tappable)
[00:18] Jab        → ⚠️ No scan — body not detected  0%  🔴  Poor        (tappable)
[00:21] Straight   → ❌ No movement detected         0%  🔴  Poor        (tappable)
...
```

**Color Legend:**
- 🟢 **GREEN (85-100%)** — Excellent, very good execution
- 🟡 **YELLOW (50-84%)** — Fair, needs improvement
- 🔴 **RED (0-49%)** — Poor, very bad execution
- ⚠️ **NO SCAN (0%)** — Body not visible, treated as Red
- ❌ **NO MOVEMENT (0%)** — Model returned unknown, treated as Red

**Tappable Behavior:** ALL timestamps open a modal. Modal content varies by rating (see below).

### Movement Detail Modal

**All ratings open the modal** — content adapts based on performance:

#### Modal Variants by Rating

**🟢 GREEN (85-100%) — No clip available:**
```swift
// Header
"Movement Evaluation — Jab"
Confidence: 92%  🟢  EXCELLENT

// Content
"Great job! Your jab form is excellent. Keep it up!"

// No user clip (Green clips are discarded)
Text: "No clip — movement was rated Excellent ✅"

// Developer suggestion (shown as encouragement)
"Jab tip: Maintain this form — shoulder back, 
 full extension, fast return to guard."

// Reference video still shown for study
// PLACEHOLDER — Developer to add reference video
```

**🟡 YELLOW (50-84%) — Clip available:**
```swift
// Header
"Movement Evaluation — Jab"
Confidence: 65%  🟡  FAIR

// Content
"Your jab has room for improvement. 
 Review your clip and the reference video below."

// User performance clip (auto-saved)
VideoPlayer(player: AVPlayer(url: movement.userClipURL!))

// Developer suggestion
"Keep your shoulder back. Extend your arm fully 
 with speed. Return quickly to guard."

// Reference video
// PLACEHOLDER — Developer to add reference video
```

**🔴 RED (0-49%) — Clip available:**
```swift
// Header
"Movement Evaluation — Jab"
Confidence: 35%  🔴  POOR

// Content
"Your jab needs significant improvement. 
 Study the correct technique carefully."

// User performance clip (auto-saved)
VideoPlayer(player: AVPlayer(url: movement.userClipURL!))

// Developer suggestion
"Keep your shoulder back. Extend your arm fully 
 with speed. Return quickly to guard."

// Reference video
// PLACEHOLDER — Developer to add reference video
```

**⚠️ NO SCAN — Body not detected:**
```swift
// Header
"Movement Evaluation — Jab"
Confidence: 0%  🔴  NO SCAN

// Content
"Your body was not detected during this window."

// User clip (still recorded and saved as Red)
VideoPlayer(player: AVPlayer(url: movement.userClipURL!))

// Fixed suggestion
"Ensure your full body is visible to the camera 
 throughout the entire session."

// Reference video still shown
// PLACEHOLDER — Developer to add reference video
```

**❌ NO MOVEMENT — Model returned unknown:**
```swift
// Header
"Movement Evaluation — Jab"
Confidence: 0%  🔴  NO MOVEMENT DETECTED

// Content
"No movement was detected during this window."

// User clip (recorded and saved as Red)
VideoPlayer(player: AVPlayer(url: movement.userClipURL!))

// Fixed suggestion
"Make sure you execute the move clearly and 
 fully within the 3-second window."

// Reference video shown
// PLACEHOLDER — Developer to add reference video
```

#### Developer Suggestions (Hardcoded per Move Type)

```swift
let moveSuggestions: [String: String] = [
    "jab": "Keep your shoulder back. Extend your arm fully with speed. Return quickly to guard.",
    "straight": "Drive from your hips. Keep your rear hand powered. Maintain balance throughout.",
    "left hook": "Rotate your hips. Keep your elbow high. Generate power from your torso.",
    "right hook": "Similar to left hook, mirror the mechanics. Turn your shoulders fully.",
    "left uppercut": "Bend your knees. Explode upward with your core. Keep your elbow tight.",
    "right uppercut": "Mirror left uppercut. Maintain balance. Protect your face."
]
```

#### Reference Videos (PLACEHOLDER)

```swift
// PLACEHOLDER — Developer to provide reference videos
let correctMovementVideos: [String: String] = [
    "jab": "correct_jab.mp4",                      // TODO: Add file
    "straight": "correct_straight.mp4",            // TODO: Add file
    "left hook": "correct_left_hook.mp4",          // TODO: Add file
    "right hook": "correct_right_hook.mp4",        // TODO: Add file
    "left uppercut": "correct_left_uppercut.mp4",  // TODO: Add file
    "right uppercut": "correct_right_uppercut.mp4" // TODO: Add file
]
```

### Save Results as JPG

**Clarified Behavior (v3.0):**
- Exports the **entire scrollable content** of the Result screen — not just the visible area
- This produces one long image capturing all movement timestamps, metrics, and session details
- Success notification confirms save to Photo Library

**Implementation:**

```swift
class ResultExporter {

    // Renders entire scrollable content — not just visible area
    func exportFullResultAsJPG(scrollView: UIScrollView) {
        let fullSize = CGSize(
            width: scrollView.contentSize.width,
            height: scrollView.contentSize.height
        )

        let renderer = UIGraphicsImageRenderer(size: fullSize)
        let jpgImage = renderer.image { context in
            // Save current offset
            let savedOffset = scrollView.contentOffset
            let savedFrame = scrollView.frame

            // Expand frame to full content size
            scrollView.contentOffset = .zero
            scrollView.frame = CGRect(origin: .zero, size: fullSize)

            // Render the full content
            scrollView.layer.render(in: context.cgContext)

            // Restore original state
            scrollView.contentOffset = savedOffset
            scrollView.frame = savedFrame
        }

        // Save to Photo Library
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else {
                print("ResultExporter: Photo Library access denied")
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: jpgImage)
            }) { success, error in
                if success {
                    print("ResultExporter: Full result page saved as JPG ✅")
                } else {
                    print("ResultExporter: Save failed — \(error?.localizedDescription ?? "unknown error")")
                }
            }
        }
    }
}
```

**Note for SwiftUI:** If the Result screen is built in SwiftUI, use a `ScrollView` with a `GeometryReader` to capture the full content height, then render via `UIHostingController` snapshot before passing to the exporter.

---

## Part 5: Data Models & Storage

> ⚠️ **Important:** Do NOT create new model structs. All models below already exist in `Models.swift`. This section documents what fields those models must contain to support the backend. If `Models.swift` is missing any field listed here, **extend it** — do not create a separate file.

### Existing Models (from `Models.swift`)

#### `Move`
Represents a single boxing punch. Must support:
```swift
// Already in Models.swift — verify it has:
struct Move {
    let id: String          // e.g. "jab", "straight", "left_hook"
    let label: String       // Display name e.g. "Jab", "Left Hook"
    // ... any other existing fields
}
```

#### `Combo`
An ordered sequence of `Move` values. Must support:
```swift
// Already in Models.swift — verify it has:
struct Combo {
    let id: Int
    let name: String
    let moves: [Move]       // Ordered sequence — this drives the session loop
}
```

#### `SessionEvent`
One entry per flagged movement event detected during post-session analysis. Only Yellow and Red events are stored — correct and undetected events are discarded during analysis. Must support:
```swift
// Already in Models.swift — verify it has (extend if missing):
struct SessionEvent {
    let id: UUID
    let timestamp: Date
    let elapsedTime: TimeInterval    // Seconds from video start (= representative window start)
    let predictedLabel: String       // e.g. "jab", "straight", "left hook"
    let confidence: Float            // 0.0–1.0 (representative window — highest in group)
    let playbackStartTime: Double    // Padded start for ranged playback (seconds)
    let playbackEndTime: Double      // Padded end for ranged playback (seconds)

    // Computed — add if missing:
    var confidencePercentage: Float { confidence * 100 }

    var movementRating: MovementRating {
        switch confidencePercentage {
        case 51...80: return .needsAdjustment   // 🟡 Yellow
        default:      return .wrongMove          // 🔴 Red (21–50%)
        }
    }

    var hasPlaybackRange: Bool { playbackEndTime > playbackStartTime }
}

enum MovementRating {
    case wrongMove         // 🔴 21–50%
    case needsAdjustment   // 🟡 51–80%

    var color: Color {
        switch self {
        case .wrongMove:       return .red
        case .needsAdjustment: return .yellow
        }
    }

    var label: String {
        switch self {
        case .wrongMove:       return "Wrong Move"
        case .needsAdjustment: return "Needs Adjustment"
        }
    }
}
```
```

#### `SessionState`
The full result of a session — owns the list of flagged `SessionEvent` entries and the main video URL. Must support:
```swift
// Already in Models.swift — verify it has (extend if missing):
struct SessionState {
    let sessionID: UUID
    let startDate: Date
    let selectedCombo: Combo
    var events: [SessionEvent]       // Only Yellow + Red events (sorted chronologically)
    var totalDuration: TimeInterval
    var sessionVideoURL: URL?        // Temp URL of full 2-minute recording

    // Computed — add if missing:
    var totalFlaggedEvents: Int { events.count }

    var wrongMoveCount: Int {
        events.filter { $0.movementRating == .wrongMove }.count
    }

    var needsAdjustmentCount: Int {
        events.filter { $0.movementRating == .needsAdjustment }.count
    }

    var averageConfidence: Float {
        events.isEmpty ? 0 : events.map { $0.confidence }.reduce(0, +) / Float(events.count)
    }

    var averageConfidencePercentage: Float { averageConfidence * 100 }
}
```

### Terminology Mapping (Old Planning Names → Actual `Models.swift` Names)

> Parts 6–14 of this document were written before `Models.swift` was examined. They use older planning terminology. Use this table to translate:

| Old Planning Name | Actual Name in `Models.swift` | Notes |
|---|---|---|
| `MovementEntry` | `SessionEvent` | Same concept — one per 3-second window |
| `MovementLogEntry` | `SessionEvent` | Same as above |
| `SessionResult` | `SessionState` | Holds all events + session metadata |
| `BoxingCombo` | `Combo` | Ordered move sequence |
| `RecordingSession` | `SessionState` | Same struct, already in Models.swift |
| `MovementLogger` | Removed | Logic lives inside `SessionManager` |
| `sequence: [String]` | `moves: [Move]` | Use Move type, not raw strings |

### Session Store (In-Memory)

```swift
// FILE: Services/SessionStore.swift — CREATE THIS FILE

class SessionStore: ObservableObject {
    static let shared = SessionStore()

    @Published var currentSession: SessionState?

    func save(_ session: SessionState) {
        currentSession = session
    }

    func clear() {
        // Delete main session video from temp storage before clearing
        if let url = currentSession?.sessionVideoURL {
            try? FileManager.default.removeItem(at: url)
        }
        currentSession = nil
    }
}
```

---

## Part 6: Integration Points & Placeholders

### Placeholder Summary Table

| Component | Type | Location | Owner | Status |
|---|---|---|---|---|
| **CoreML Model** | `.mlmodel` file | `MLInferenceEngine.swift` | Dev Team | Pending Integration |
| **Audio Cues** | `.mp3` files (6 files) | `AudioCuePlayer.swift` | Developer | Pending Asset Addition |
| **Correct Movement Videos** | `.mp4` files (6 files) | `ResultDetailView.swift` | Developer | Pending Asset Addition |
| **User Movement Clips** | Recording + storage | `SessionManager.swift` | Dev Team + Framework | Pending Implementation |

### Placeholder Code Templates

#### Template 1: CoreML Model Integration

```swift
// FILE: MLInferenceEngine.swift

import CoreML
import Vision

class MLInferenceEngine {
    var model: MLModel?
    
    func loadModel() {
        // PLACEHOLDER — Replace with actual model
        do {
            // TODO: Replace "YourModel" with actual model name
            let config = MLModelConfiguration()
            self.model = try YourActionClassifier(configuration: config).model
        } catch {
            print("Failed to load ML model: \(error)")
        }
    }
    
    func predictMove(
        from poseObservations: [VNHumanBodyPoseObservation]
    ) -> (label: String, confidence: Float) {
        // TODO: Convert VNHumanBodyPoseObservation to model input format
        // TODO: Run inference
        // TODO: Extract output (predicted class, confidence)
        
        // PLACEHOLDER RETURN
        return ("unknown", 0.0)
    }
}
```

#### Template 2: Audio Cue Playback

```swift
// FILE: AudioCuePlayer.swift

import AVFoundation

class AudioCuePlayer {
    var audioPlayer: AVAudioPlayer?
    
    let audioAssets: [String: String] = [
        "jab": "cue_jab.mp3",
        "straight": "cue_straight.mp3",
        "left hook": "cue_left_hook.mp3",
        "right hook": "cue_right_hook.mp3",
        "left uppercut": "cue_left_uppercut.mp3",
        "right uppercut": "cue_right_uppercut.mp3"
    ]
    
    func playAudioCue(for move: String) {
        guard let fileName = audioAssets[move.lowercased()] else {
            print("Audio file not found for move: \(move)")
            return
        }
        
        // TODO: Add audio files to Xcode project
        // TODO: Load and play using AVAudioPlayer
        
        guard let url = Bundle.main.url(forResource: fileName, withExtension: nil) else {
            print("Audio file URL not found: \(fileName)")
            return
        }
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
        } catch {
            print("Failed to play audio: \(error)")
        }
    }
}
```

#### Template 3: Reference Movement Videos

```swift
// FILE: ResultDetailView.swift

import AVKit

struct MovementDetailView: View {
    let movement: MovementEntry
    
    let correctMovementVideos: [String: String] = [
        "jab": "correct_jab.mp4",
        "straight": "correct_straight.mp4",
        "left hook": "correct_left_hook.mp4",
        "right hook": "correct_right_hook.mp4",
        "left uppercut": "correct_left_uppercut.mp4",
        "right uppercut": "correct_right_uppercut.mp4"
    ]
    
    let moveSuggestions: [String: String] = [
        "jab": "Keep your shoulder back. Extend your arm fully with speed. Return quickly to guard.",
        "straight": "Drive from your hips. Keep your rear hand powered. Maintain balance throughout.",
        "left hook": "Rotate your hips. Keep your elbow high. Generate power from your torso.",
        "right hook": "Similar to left hook, mirror the mechanics. Turn your shoulders fully.",
        "left uppercut": "Bend your knees. Explode upward with your core. Keep your elbow tight.",
        "right uppercut": "Mirror left uppercut. Maintain balance. Protect your face."
    ]
    
    var body: some View {
        VStack {
            Text("Movement Evaluation")
            
            // User clip player
            // TODO: Add user's recorded clip playback
            Text("User Clip Placeholder")
            
            // Suggestion text
            if let suggestion = moveSuggestions[movement.expectedMove.lowercased()] {
                Text(suggestion)
                    .padding()
            }
            
            // Reference video player
            // TODO: Add correct movement reference video
            Text("Reference Video Placeholder")
        }
    }
}
```

---

## Part 7: Key Constraints & Requirements

### Fixed Parameters
- **Session Duration:** 2 minutes (120 seconds) — immutable
- **Move Window:** 3 seconds per move — immutable
- **Confidence Threshold:** 70% (adjustable)
- **ML Model Moves:** Exactly 6 classes (jab, straight, left hook, right hook, left uppercut, right uppercut)
- **Static Combos:** Exactly 6 pre-defined combos — no custom combos

### Data Flow Invariants
1. Menu → Record: Combo is passed and locked for entire session
2. Record → Result: All movement entries are finalized and immutable
3. Result: No changes to data; only export/view operations

### UI/Backend Coupling
- **Frontend is Final:** Backend adapts to UI, not vice versa
- **Combo List:** Must match exactly what frontend displays
- **Move Names:** Must match exactly what frontend labels and what ML model outputs

---

## Part 11: Implementation Checklist

### Phase 1: Core Architecture
- [ ] Create `SessionManager` with timer logic
- [ ] Create `VisionProcessor` for body pose detection
- [ ] Create `MovementLogger` for tracking entries
- [ ] Set up `SessionStore` for in-memory storage

### Phase 2: ML & Audio Integration Points
- [ ] Create `MLInferenceEngine` with placeholder structure
- [ ] Create `AudioCuePlayer` with audio file mappings
- [ ] Test placeholder inference/audio with mock data

### Phase 3: Recording Session Flow
- [ ] Implement camera calibration phase
- [ ] Implement move sequencing loop
- [ ] Implement 3-second move windows
- [ ] Wire up ML inference to camera frames
- [ ] Populate movement log in real-time

### Phase 4: Result Screen & Export
- [ ] Display session summary metrics
- [ ] Display movement timestamp breakdown
- [ ] Implement movement detail modal
- [ ] Implement JPG export functionality

### Phase 4.5: Performance Color Rating System (NEW)
- [ ] Create `Color.performanceColor(for:)` extension
- [ ] Create `Color.performanceLabel(for:)` extension
- [ ] Build `ConfidenceDisplay` SwiftUI component
- [ ] Build `AverageConfidenceCard` SwiftUI component
- [ ] Build `MovementLogEntry` with color rating display
- [ ] Create `PerformanceFeedback` helper for contextual messages
- [ ] Update data models with `performanceRating` computed property
- [ ] Apply color coding to all confidence displays (session + individual movements)
- [ ] Test color contrast and accessibility (WCAG AA)

### Phase 5: Integration & Testing
- [ ] Integrate actual CoreML model (replace placeholder)
- [ ] Integrate audio asset files (replace placeholder)
- [ ] Integrate reference movement videos (replace placeholder)
- [ ] End-to-end testing across all 3 pages
- [ ] Test color rating system with various confidence ranges

---

## Part 12: File Structure (Recommended)

```
ShadowBoxApp/
├── Models/
│   ├── BoxingCombo.swift
│   ├── MovementEntry.swift
│   ├── SessionResult.swift
│   └── PerformanceRating.swift
├── ViewModels/
│   ├── MenuViewModel.swift
│   ├── RecordViewModel.swift
│   └── ResultViewModel.swift
├── Views/
│   ├── MenuView.swift
│   ├── RecordView.swift
│   ├── CalibrationView.swift
│   ├── ResultView.swift
│   ├── MovementDetailView.swift
│   ├── ConfidenceDisplay.swift
│   ├── AverageConfidenceCard.swift
│   └── MovementLogEntry.swift
├── Services/
│   ├── SessionManager.swift
│   ├── VisionProcessor.swift
│   ├── MLInferenceEngine.swift
│   ├── AudioCuePlayer.swift
│   ├── MovementLogger.swift
│   ├── SessionStore.swift
│   └── ClipRecorder.swift          ← NEW (auto-clip Yellow/Red)
├── Utilities/
│   ├── ResultExporter.swift
│   ├── PerformanceFeedback.swift
│   └── ColorExtensions.swift
└── Assets/
    ├── Audio/
    │   ├── cue_jab.mp3 (TODO)
    │   ├── cue_straight.mp3 (TODO)
    │   └── ... (6 total)
    └── Videos/
        ├── correct_jab.mp4 (TODO)
        ├── correct_straight.mp4 (TODO)
        └── ... (6 total)
```

---

## Part 13: API Contract Examples

### Example 1: Starting a Session
```swift
// From MenuView → RecordingView
// Uses existing Combo type from Models.swift
let selectedCombo = allCombos.first { $0.id == 2 }!
// e.g. Combo: "Jab-Straight-Left Hook", moves: [jab, straight, leftHook]

let sessionManager = SessionManager(selectedCombo: selectedCombo)
sessionManager.startRecording()  // Called after user taps "I'm Ready"
// Inject sessionManager as @StateObject or @EnvironmentObject into RecordingView
```

### Example 2: Logging a Movement (Every 3 Seconds)
```swift
// Inside SessionManager.endMoveWindow():
let result = movementAggregator.aggregate(predictions: currentFramePredictions)

clipRecorder.stopAndEvaluate(
    confidence: result.confidence,
    predictedLabel: result.label,
    move: currentExpectedMove.id,
    windowIndex: globalWindowIndex
) { savedClipURL in

    let event = SessionEvent(
        id: UUID(),
        timestamp: Date(),
        elapsedTime: self.elapsedTime,
        expectedMove: self.currentExpectedMove,
        predictedLabel: result.label,
        confidence: result.confidence,
        isAccurate: (result.label == self.currentExpectedMove.id) && (result.confidence >= 0.85),
        clipURL: savedClipURL
    )
    // Append to SessionState.events — drives live log in RecordingView
    self.events.append(event)
}
// Color coded in live log: 92% → 🟢 Green, 65% → 🟡 Yellow, 35% → 🔴 Red
```

### Example 3: Displaying Performance Rating in UI
```swift
// Get color and label from SessionEvent directly
let event: SessionEvent
let color = event.performanceRating.color   // .green / .yellow / .red
let label = event.performanceRating.label   // "Excellent" / "Fair" / "Poor" / "No Scan" / "No Movement"

// Use in ResultsView timeline
Text("\(Int(event.confidencePercentage))% — \(label)")
    .foregroundColor(color)
```

### Example 4: Session Summary with Overall Rating
```swift
// SessionState computed properties drive the stats cards in ResultsView
let session: SessionState = SessionStore.shared.currentSession!

// Cards display:
session.totalMovements          // Total windows evaluated
session.accurateMovements       // Green count
session.movementErrors          // Yellow + Red + NoScan + NoMovement count
session.averageConfidencePercentage  // Colored by overallPerformanceRating

// Overall color badge
let overallColor = session.overallPerformanceRating.color
```

### Example 5: Exporting Results
```swift
// ResultsView "Save" button handler
let exporter = ResultExporter()
exporter.exportFullResultAsJPG(scrollView: resultsScrollView)
// Saves full-length image to Photo Library
// Photo Library permission: add NSPhotoLibraryAddUsageDescription to project.pbxproj
```

---

## Part 10.5: Performance Color Rating System (NEW)

### Overview

The ShadowBox app uses a **three-tier color-coded confidence rating system** to provide instant visual feedback on movement quality.

### Color Mapping

| Confidence Range | Color | Hex Code | UIColor | Performance Level | Description |
|---|---|---|---|---|---|
| **85-100%** | 🟢 Green | #34C759 | `.systemGreen` | **Excellent** | Very good performance, excellent form |
| **50-84%** | 🟡 Yellow | #FFCC00 | `.systemYellow` | **Fair** | Not good enough, needs improvement |
| **0-49%** | 🔴 Red | #FF3B30 | `.systemRed` | **Poor** | Very bad performance, incorrect execution |

### Where Color Rating Appears

#### 1. Average Confidence Metric (Session Summary)
The **"Avg Confidence"** card displays the session's overall average confidence with:
- **Large colored circle** or **background tint** matching the rating
- **Percentage number** in the corresponding color
- **Text label** (Optional): "Excellent", "Fair", or "Poor"

**Examples:**
- **Avg Confidence: 91%** → 🟢 GREEN background + "Excellent"
- **Avg Confidence: 72%** → 🟡 YELLOW background + "Fair"
- **Avg Confidence: 35%** → 🔴 RED background + "Poor"

#### 2. Individual Movement Timestamps (Breakdown Table)
Each movement entry in the timestamp log shows:
- Move name and prediction result
- Confidence percentage with color indicator
- Optional colored bar or circle next to percentage

**Example Layout:**
```
┌─────────────────────────────────────────┐
│ [00:03] Jab → Jab       ✅ 92%  🟢    │
│ [00:06] Straight → Straight ✅ 88% 🟢  │
│ [00:09] Jab → Left Hook  ❌ 65%  🟡    │
│ [00:12] Straight → Straight ✅ 91% 🟢  │
│ [00:15] Left Hook → Left Hook ✅ 42% 🔴 │
└─────────────────────────────────────────┘
```

#### 3. Movement Detail Modal
When user taps a movement timestamp, the modal displays:
- The movement's confidence percentage with color
- Performance rating label (Excellent/Fair/Poor)
- Suggestions tailored to the rating level

**Example:**
```swift
// If confidence is 42% (Red - Poor)
Title: "Movement Analysis — Jab"
Confidence: 42% (🔴 Poor)
Feedback: "Your jab needs significant improvement. Review the correct form below."

// If confidence is 92% (Green - Excellent)
Title: "Movement Analysis — Jab"
Confidence: 92% (🟢 Excellent)
Feedback: "Great job! Your jab form is excellent. Keep it up!"
```

### Implementation Code

#### SwiftUI Color Modifier Helper

```swift
extension Color {
    static func performanceColor(for confidence: Float) -> Color {
        switch confidence * 100 {
        case 85...100:
            return Color.green       // Excellent
        case 50...84:
            return Color.yellow      // Fair
        case 0...49:
            return Color.red         // Poor
        default:
            return Color.gray
        }
    }
    
    static func performanceLabel(for confidence: Float) -> String {
        switch confidence * 100 {
        case 85...100:
            return "Excellent"
        case 50...84:
            return "Fair"
        case 0...49:
            return "Poor"
        default:
            return "Unknown"
        }
    }
}
```

#### Example SwiftUI View Component

```swift
struct ConfidenceDisplay: View {
    let percentage: Float
    
    var confidenceColor: Color {
        Color.performanceColor(for: percentage)
    }
    
    var performanceLabel: String {
        Color.performanceLabel(for: percentage)
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Colored circle indicator
            Circle()
                .fill(confidenceColor)
                .frame(width: 12, height: 12)
            
            // Percentage text
            Text(String(format: "%.0f%%", percentage * 100))
                .font(.system(.body, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundColor(confidenceColor)
            
            // Performance label (optional)
            Text(performanceLabel)
                .font(.caption)
                .foregroundColor(confidenceColor)
                .opacity(0.8)
        }
    }
}

// Usage
ConfidenceDisplay(percentage: 0.92)  // Shows: 🟢 92% Excellent
ConfidenceDisplay(percentage: 0.65)  // Shows: 🟡 65% Fair
ConfidenceDisplay(percentage: 0.35)  // Shows: 🔴 35% Poor
```

#### Average Confidence Card

```swift
struct AverageConfidenceCard: View {
    let percentage: Float
    
    var backgroundColor: Color {
        Color.performanceColor(for: percentage)
    }
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(backgroundColor.opacity(0.2))
                .stroke(backgroundColor, lineWidth: 2)
            
            VStack(spacing: 8) {
                Text("Avg Confidence")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Text(String(format: "%.1f%%", percentage * 100))
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(backgroundColor)
                
                Text(Color.performanceLabel(for: percentage))
                    .font(.caption)
                    .foregroundColor(backgroundColor)
            }
            .padding()
        }
    }
}

// Usage
AverageConfidenceCard(percentage: 0.87)  // Green: Excellent
AverageConfidenceCard(percentage: 0.72)  // Yellow: Fair
AverageConfidenceCard(percentage: 0.42)  // Red: Poor
```

### Performance Rating in Movement Logger

```swift
struct MovementLogEntry: View {
    let movement: MovementEntry
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("[\(formatTime(movement.elapsedSessionTime))] \(movement.expectedMove.capitalized)")
                    .font(.body)
                    .fontWeight(.semibold)
                
                Text("Predicted: \(movement.predictedMove.capitalized)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            // Result indicator
            Image(systemName: movement.isAccurate ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(movement.isAccurate ? .green : .red)
            
            // Color-coded confidence
            ConfidenceDisplay(percentage: movement.confidence)
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}
```

### Feedback Text Based on Performance Rating

```swift
struct PerformanceFeedback {
    static func getFeedback(for confidence: Float, move: String) -> String {
        let percentage = confidence * 100
        
        switch percentage {
        case 85...100:
            return "🟢 Excellent! Your \(move) form is perfect. Outstanding execution!"
            
        case 50...84:
            return "🟡 Fair. Your \(move) has room for improvement. Review the reference video and adjust your form."
            
        case 0...49:
            return "🔴 Poor. Your \(move) needs significant improvement. Study the correct technique below."
            
        default:
            return "Unable to analyze movement"
        }
    }
}
```

### Data Model Update Summary

**Existing:** `MovementEntry` and `SessionResult` now include:
- `performanceRating` computed property
- Color getter method
- Performance label method

**New Methods:**
- `Color.performanceColor(for: Float)` — Returns color based on confidence
- `Color.performanceLabel(for: Float)` — Returns label text
- `PerformanceFeedback.getFeedback()` — Returns contextual feedback

### Visual Design Consistency

**Across All Pages:**
- Use the same three colors consistently (Green/Yellow/Red)
- Apply color to circles, bars, background tints, and text
- Ensure sufficient contrast for accessibility (WCAG AA standard)
- Display color alongside percentage (don't rely on color alone)

---

## Part 14: Post-Session Analysis System

### Overview

After the 2-minute recording ends, the full session video is analyzed using the Apple CoreML Action Classifier. This runs while the "Reviewing…" spinner is displayed in `RecordingView`. The output is a sorted array of `SessionEvent` objects representing only flagged (Yellow/Red) movements — correct and undetected movements are discarded.

---

### Full Pipeline (Step by Step)

```
Recording ends
  → AVAssetWriter finalizes session video to temp file
  → PostSessionAnalyzer.analyze(videoURL:) called

Step 1: Frame Extraction
  → Read video asset frame by frame using AVAssetReader
  → Extract CVPixelBuffer per frame at native frame rate (30fps)

Step 2: Pose Detection (per frame)
  → Feed each CVPixelBuffer to VisionProcessor
  → VNDetectHumanBodyPoseRequest returns VNHumanBodyPoseObservation

Step 3: Sliding Window Inference
  → Buffer pose observations in a rolling array of 60 frames
  → When buffer reaches 60 frames: run MLInferenceEngine.predict()
  → Record: { label, confidence, windowStartTime, windowEndTime }
  → Slide forward (remove oldest frames by stride amount)
  → Repeat until end of video

Step 4: Filter
  → Remove windows with confidence ≤ 0.20 (undetected)
  → Remove windows with confidence > 0.80 (correct)
  → Remaining: 0.21–0.50 (Red), 0.51–0.80 (Yellow)

Step 5: Group
  → Consecutive windows with the same label = one event group
  → New group starts when: label changes OR time gap between windows exceeds threshold

Step 6: Select Representative
  → Within each group: pick window with highest confidence
  → That window's { label, confidence, startTime, endTime } represents the event

Step 7: Apply Padding
  → paddedStart = max(0, representativeWindow.startTime - clipPaddingSeconds)
  → paddedEnd   = representativeWindow.endTime + clipPaddingSeconds
  → clipPaddingSeconds = 0.5 (configurable constant)

Step 8: Build SessionEvent
  → One SessionEvent per group
  → Sorted chronologically by elapsedTime

Step 9: Store Result
  → SessionState.events = sorted SessionEvent array
  → SessionState.sessionVideoURL = temp video URL
  → SessionStore.shared.save(sessionState)
  → Navigate to ResultsView
```

---

### Confidence Tier Reference

| Range | Label | Color | Action |
|---|---|---|---|
| 0.00–0.20 | Undetected | — | Filtered out in Step 4 |
| 0.21–0.50 | Wrong Move | 🔴 Red | Kept as SessionEvent |
| 0.51–0.80 | Needs Adjustment | 🟡 Yellow | Kept as SessionEvent |
| 0.80+ | Correct | 🟢 Green | Filtered out in Step 4 |

---

### PostSessionAnalyzer — Full Implementation Blueprint

```swift
// FILE: Services/PostSessionAnalyzer.swift

import AVFoundation
import Vision
import CoreML

class PostSessionAnalyzer {

    // MARK: - Configurable Constants
    let clipPaddingSeconds: Double = 0.5   // Padding added to each side of playback range
    let windowSize: Int = 60               // Must match Create ML training configuration
    let strideSize: Int = 15              // How many frames to advance after each prediction

    // MARK: - Dependencies
    private let visionProcessor = VisionProcessor()
    private let mlEngine = MLInferenceEngine()

    // MARK: - Main Entry Point
    func analyze(videoURL: URL, completion: @escaping ([SessionEvent]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            // TODO: Implement full pipeline steps 1–8
            // Step 1: Extract frames from videoURL using AVAssetReader
            // Step 2: Run VisionProcessor on each frame
            // Step 3: Buffer poses into 60-frame windows, run MLInferenceEngine
            // Step 4: Filter by confidence tier
            // Step 5: Group consecutive same-label windows
            // Step 6: Select representative (highest confidence) per group
            // Step 7: Apply clipPaddingSeconds to start/end
            // Step 8: Build and sort SessionEvent array

            DispatchQueue.main.async {
                completion([]) // Replace with real events
            }
        }
    }

    // MARK: - Step 5: Group consecutive windows
    func groupWindows(_ predictions: [WindowPrediction]) -> [[WindowPrediction]] {
        var groups: [[WindowPrediction]] = []
        var currentGroup: [WindowPrediction] = []

        for prediction in predictions {
            if currentGroup.isEmpty {
                currentGroup.append(prediction)
            } else if let last = currentGroup.last,
                      last.label == prediction.label,
                      (prediction.startTime - last.endTime) < 0.5 {
                // Same label and no significant gap → same group
                currentGroup.append(prediction)
            } else {
                // New group starts
                groups.append(currentGroup)
                currentGroup = [prediction]
            }
        }
        if !currentGroup.isEmpty { groups.append(currentGroup) }
        return groups
    }

    // MARK: - Step 6: Select representative window
    func selectRepresentative(from group: [WindowPrediction]) -> WindowPrediction {
        return group.max(by: { $0.confidence < $1.confidence })!
    }

    // MARK: - Step 7+8: Build SessionEvent with padding
    func buildEvent(from window: WindowPrediction, videoDuration: Double) -> SessionEvent {
        let paddedStart = max(0, window.startTime - clipPaddingSeconds)
        let paddedEnd   = min(videoDuration, window.endTime + clipPaddingSeconds)

        return SessionEvent(
            id: UUID(),
            timestamp: Date(),
            elapsedTime: window.startTime,
            predictedLabel: window.label,
            confidence: window.confidence,
            playbackStartTime: paddedStart,
            playbackEndTime: paddedEnd
        )
    }
}

// MARK: - Supporting Type
struct WindowPrediction {
    let label: String        // e.g. "jab"
    let confidence: Float    // 0.0–1.0
    let startTime: Double    // Seconds from video start (first frame of window)
    let endTime: Double      // Seconds from video start (last frame of window)
}
```

---

### VideoRangePlayer — Full Implementation Blueprint

```swift
// FILE: Services/VideoRangePlayer.swift

import AVFoundation
import AVKit
import Combine

class VideoRangePlayer: ObservableObject {

    private(set) var player: AVPlayer = AVPlayer()
    private var endTimeObserver: Any?

    // MARK: - Setup (called once when Results screen appears)
    func configure(videoURL: URL) {
        let item = AVPlayerItem(url: videoURL)
        player.replaceCurrentItem(with: item)
    }

    // MARK: - Ranged Playback
    // No clip extraction — seeks main video to start, stops at end
    func play(from startSeconds: Double, to endSeconds: Double) {
        guard player.currentItem != nil else { return }

        let startTime = CMTime(seconds: startSeconds, preferredTimescale: 600)
        let endTime   = CMTime(seconds: endSeconds,   preferredTimescale: 600)

        // Set playback end boundary
        player.currentItem?.forwardPlaybackEndTime = endTime

        // Seek to start then play
        player.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            self?.player.play()
        }
    }

    func pause() { player.pause() }

    func reset() {
        player.pause()
        player.currentItem?.forwardPlaybackEndTime = .invalid
    }
}
```

**Usage in ResultsView event modal:**
```swift
// One VideoRangePlayer instance shared across all event modals
// Configured once when ResultsView appears with session video URL
// When user taps a SessionEvent:

videoRangePlayer.play(
    from: event.playbackStartTime,   // e.g. 3.7s (padded)
    to:   event.playbackEndTime      // e.g. 6.2s (padded)
)

// Display using AVKit's VideoPlayer
VideoPlayer(player: videoRangePlayer.player)
    .frame(height: 300)
    .cornerRadius(12)
```

---

### Main Video Storage & Lifecycle

```
Session starts
  → AVAssetWriter begins writing to temp directory
  → File: ShadowBox_session_{UUID}.mp4

Recording ends
  → AVAssetWriter.finishWriting() called
  → PostSessionAnalyzer runs on finalized file
  → sessionVideoURL stored in SessionState

Results screen shown
  → VideoRangePlayer.configure(videoURL: sessionVideoURL)
  → All ranged playback uses this single file

User taps Save button (optional)
  → Copy session video to Photo Library via PHPhotoLibrary
  → Original temp file remains until navigation away

User leaves Results screen
  → SessionStore.shared.clear() called
  → Temp video file deleted
  → VideoRangePlayer reset

App launch (startup cleanup)
  → Scan temp directory for leftover session videos
  → Delete any found (from previous crash or force-quit)
```

**Startup Cleanup:**
```swift
// Run on app launch before any UI appears
func cleanupLeftoverSessionVideos() {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ShadowBoxSessions", isDirectory: true)
    if let files = try? FileManager.default.contentsOfDirectory(
        at: tempDir, includingPropertiesForKeys: nil) {
        files.forEach { try? FileManager.default.removeItem(at: $0) }
    }
}
```

**On Results Screen Dismiss:**
```swift
.onDisappear {
    videoRangePlayer.reset()
    SessionStore.shared.clear()  // Also deletes temp video file
}
```

---

### Estimated Processing Time

| Session Length | Frames | Approx Analysis Time |
|---|---|---|
| 2 minutes (full) | ~3,600 frames | 5–15 seconds (device dependent) |
| 1 minute (early stop) | ~1,800 frames | 3–8 seconds |

Analysis runs on a background thread (`DispatchQueue.global(qos: .userInitiated)`) so the "Reviewing…" UI remains responsive.

---

### Updated Implementation Checklist

- [ ] Implement `SessionManager` full video recording via `AVAssetWriter`
- [ ] Implement `PostSessionAnalyzer.analyze(videoURL:)` pipeline
- [ ] Implement frame extraction from video using `AVAssetReader`
- [ ] Implement 60-frame sliding window buffer with configurable stride
- [ ] Implement `groupWindows()` — consecutive same-label grouping
- [ ] Implement `selectRepresentative()` — highest confidence per group
- [ ] Implement `buildEvent()` — padding + `SessionEvent` construction
- [ ] Implement `VideoRangePlayer.configure()` and `play(from:to:)`
- [ ] Wire `VideoRangePlayer` into ResultsView event modal
- [ ] Implement main video Save button → Photo Library copy
- [ ] Implement startup cleanup of leftover temp session videos
- [ ] Implement `SessionStore.clear()` with temp file deletion
- [ ] Test: correct move (>80%) → not in results
- [ ] Test: undetected (≤20%) → not in results
- [ ] Test: yellow (51–80%) → appears in results, ranged playback works
- [ ] Test: red (21–50%) → appears in results, ranged playback works
- [ ] Test: overlapping windows on same move → grouped into one event
- [ ] Test: highest confidence window selected as representative
- [ ] Test: padding applied correctly at video boundaries (start/end)

---

This document provides a **complete blueprint** for the ShadowBox backend. All placeholder integration points are clearly marked with `TODO` comments. The frontend UI is assumed to be final and immutable — the backend is designed to seamlessly plug in and support it.

**Next Steps:**
1. Share the frontend SwiftUI code
2. Developer team provides CoreML model + audio files + reference videos
3. Implement services using this architecture
4. Wire services into views
5. Test end-to-end flow

---

**Document Version:** 6.0 — Post-Recording Analysis Architecture + Ranged Playback
**Last Updated:** May 4, 2026
**Prepared By:** 50-Year Veteran iOS Developer & AI Engineer
