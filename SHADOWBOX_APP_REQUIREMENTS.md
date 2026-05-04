# ShadowBox iOS App — Complete Requirements & Architecture Document
# Project: BoxMaxxingFinal

---

## 🤖 Instructions for Claude Code — READ THIS FIRST

> **These instructions must be followed before writing a single line of code.**

---

### 1. Current Project State (BoxMaxxingFinal)

The Xcode project **BoxMaxxingFinal** already exists with the following files built and in place. **Do not recreate, rewrite, or restructure any of them** unless explicitly told to do so.

#### Frontend (Original — Do Not Touch)

| File | Status | What It Does |
|---|---|---|
| `ContentView.swift` | ✅ Done | App routing — navigates Menu → Recording → Results using opacity transitions |
| `Models.swift` | ✅ Done | Core domain models: `Move`, `Combo`, `SessionEvent`, `SessionState`. Contains `allMoves`, `allCombos`, and `generateEvents()` |
| `MoveGlyphView.swift` | ✅ Done | Canvas-drawn visual glyphs for each punch type, with mirroring logic for right-side moves |
| `MenuView.swift` | ✅ Done | Start screen — title bar, combo picker with numbered badges, 3x2 move grid, Start button |
| `RecordingView.swift` | ✅ Done | Live session screen — `AVCaptureSession` camera preview, setup hint sheet, 3-2-1 countdown, recording HUD (REC pill, live detection chips, progress bar, stop button), "Reviewing…" spinner |
| `ResultsView.swift` | ✅ Done | Results screen — session stats (Wrong/Unclear/Avg Confidence), vertical timeline with spine and event dots, tappable event cards, bottom sheet with clip panels, confidence bars, form suggestions, correct form visuals |
| `project.pbxproj` | ✅ Done | `NSCameraUsageDescription` permission key added |

#### Backend (Implemented May 3, 2026)

| File | Status | What It Does |
|---|---|---|
| `Services/SessionManager.swift` | ✅ Done | Orchestrates full 2-min session — 1s session timer, 3s move window loop, stop confirmation dialog, auto-finalizes on timeout |
| `Services/VisionProcessor.swift` | ✅ Done | Vision framework body pose detection wrapper; dispatches on background queue |
| `Services/MLInferenceEngine.swift` | ✅ Done (placeholder) | CoreML inference stub; returns `no_movement_detected` until model is integrated |
| `Services/AudioCuePlayer.swift` | ✅ Done (placeholder) | AVFoundation audio cue player keyed by `Move.id`; asset files TBD |
| `Services/MovementAggregator.swift` | ✅ Done | Majority-vote label + avg confidence of winning frames over a 3s window |
| `Services/ClipRecorder.swift` | ✅ Done ⚠️ | AVAssetWriter clip recorder — keep/discard by rating. **Has known bugs (see Section 15)** |
| `Services/SessionStore.swift` | ✅ Done | In-memory storage of session events, start date, and duration |
| `Utilities/ResultExporter.swift` | ✅ Done ⚠️ | Full scrollable JPG export via `UIGraphicsImageRenderer`. **Not yet wired into ResultsView** |
| `Utilities/PerformanceFeedback.swift` | ✅ Done | Contextual feedback strings per move and rating |
| `Utilities/ColorExtensions.swift` | ✅ Done | `MovementState` enum, `performanceColor(for:)` and `performanceLabel(for:)` helpers |

---

### 2. What Remains to Be Done

The backend services are implemented. The following work is still outstanding. **Fix bugs in priority order before adding new features.**

#### Priority 1 — Bug Fixes (see Section 15 for full details)

```
ClipRecorder.swift       — Fix tempClipURL race condition (next window overwrites before finishWriting completes)
ClipRecorder.swift       — Fix thread safety (appendFrame runs on camera queue; start/stop run on main thread)
ClipRecorder.swift       — Fix hardcoded 1080×1920 resolution (must match actual pixel buffer dimensions)
Models.swift             — Add missing 2 combos (allCombos has 4; spec requires 6)
```

#### Priority 2 — Incomplete Features

```
ResultsView.swift        — Wire ResultExporter: replace placeholder message with actual UIScrollView snapshot export
ResultsView.swift        — Replace VideoPanel placeholder with AVPlayer(url: event.clipURL) for user clips
```

#### Priority 3 — External Assets (blocked on team)

```
MLInferenceEngine.swift  — Integrate CoreML model when provided by team
AudioCuePlayer.swift     — Add .mp3 audio files for each of the 6 moves
ResultsView.swift        — Add .mp4 reference videos for each of the 6 moves
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
4. **`SessionStore.swift`** — in-memory store for `SessionState` / result
5. **`MovementAggregator.swift`** — majority vote + average confidence logic
6. **`VisionProcessor.swift`** — Vision body pose detection wrapper
7. **`MLInferenceEngine.swift`** — CoreML placeholder wrapper
8. **`AudioCuePlayer.swift`** — AVFoundation audio cue player with placeholder asset slots
9. **`ClipRecorder.swift`** — AVAssetWriter clip recording, keep/discard logic
10. **`SessionManager.swift`** — full session orchestration (timer, move sequencing, wiring)
11. **`ResultExporter.swift`** — full scrollable JPG export
12. **Wire into views** — inject `SessionManager` and `SessionStore` into `RecordingView` and `ResultsView` last

---

### 5. Placeholders — Leave These Exactly As-Is

The following components are **intentionally unimplemented**. Leave placeholder `// TODO` comments. Do not invent fake data or stub logic that pretends to work:

| Placeholder | File | Owner |
|---|---|---|
| CoreML `.mlmodel` file | `MLInferenceEngine.swift` | Dev Team |
| Audio cue `.mp3` files (6 files) | `AudioCuePlayer.swift` | Developer |
| Correct movement `.mp4` reference videos | `ResultsView.swift` bottom sheet | Developer |
| User clip recording inside `MLInferenceEngine` | `ClipRecorder.swift` | Dev Team |

---

### 6. Behaviour Rules — Non-Negotiable

#### Session
- Duration: exactly **2 minutes (120 seconds)** — fixed, not configurable
- Each move window: exactly **3 seconds** — fixed
- Combo loops continuously until timer expires or user stops
- Each loop occurrence of a move = **its own independent `SessionEvent`** with its own timestamp and clip

#### Camera Calibration
- The setup hint sheet in `RecordingView` is a **UX reminder only** — not a hard gate
- "I'm Ready" is always tappable — do not add any lock condition
- If body pose is lost mid-session: session **continues**, that window logs as `noBodyDetected` at 0% Red

#### ML Aggregation (per 3-second window)
- Collect all frame predictions (~90 frames at 30fps)
- **Label** = most frequent predicted label (majority vote)
- **Confidence** = average confidence of frames that voted for the winning label
- If no valid prediction: label = `noMovementDetected`, confidence = 0.0

#### Stop Button
- Tapping Stop shows a **confirmation dialog** — session timer keeps running in background
- If 2-minute timer expires while dialog is open: finalize session, dismiss dialog, navigate to Results automatically
- Result screen always shows regardless of how many moves were completed

#### Clip Recording
| Rating | Confidence | Action |
|---|---|---|
| 🟢 Green | 85–100% | Discard clip immediately |
| 🟡 Yellow | 50–84% | Save clip to permanent directory |
| 🔴 Red | 0–49% | Save clip to permanent directory |
| ⚠️ No Scan | 0% (no body) | Save clip to permanent directory |
| ❌ No Movement | 0% (unknown) | Save clip to permanent directory |

#### Clip Storage Lifetime
- Clips are deleted when the user **navigates away from the Results screen**
- Clips are deleted when the **app is closed** (startup cleanup on next launch)

#### JPG Export
- Must capture the **entire scrollable content** of `ResultsView` — not just the visible viewport
- One long image including all timeline events, stats, and session details

#### Timestamps (Results Timeline)
- **All `SessionEvent` entries are tappable** — Green, Yellow, Red, No Scan, No Movement
- Green modal: shows "Excellent" message, no clip (clip was discarded)
- Yellow/Red/NoScan/NoMovement modal: shows clip, suggestion, reference video placeholder

---

### 7. Performance Color System

| Confidence | Color | Label |
|---|---|---|
| 85–100% | 🟢 `Color.systemGreen` | Excellent |
| 50–84% | 🟡 `Color.systemYellow` | Fair |
| 0–49% | 🔴 `Color.systemRed` | Poor |
| No Scan / No Movement | 🔴 `Color.systemRed` | No Scan / No Movement |

---

### 8. Static Combo List — Do Not Change

The `allCombos` array in `Models.swift` is already defined and must not be modified. It must match exactly what `MenuView.swift` displays. Do not add, remove, or rename any combo.

---

### 9. Quick Reference Summary

| Rule | Decision |
|---|---|
| Existing files | Do not modify — read and extend only |
| New model files | Do not create — use types from `Models.swift` |
| `generateEvents()` | Replace with real pipeline output after session |
| Build order | Strict — follow Step 4 above |
| Placeholders | Leave all `// TODO` exactly as written |
| Session duration | 2 minutes, fixed |
| Move window | 3 seconds, fixed |
| Combo looping | Each occurrence = independent event + clip decision |
| Stop dialog | Timer keeps running; auto-finalizes if time expires |
| Calibration | UX reminder only, always tappable |
| Clip — Green | Discard immediately after evaluation |
| Clip — all others | Save until user leaves Results or app closes |
| JPG export | Full scrollable content, not visible area only |
| All timeline events | Tappable regardless of rating |

---

**Project Name:** BoxMaxxingFinal
**Project Status:** Bug Fix Phase — backend complete, known bugs outstanding
**Date Created:** May 3, 2026
**Expert Role:** 50-Year Veteran iOS Developer & AI Engineer
**Model Type:** CoreML Action Classifier (Pre-trained by Team)
**Document Version:** 5.2 — Backend Implemented; Bug Fixes Outstanding

---

## Clarification Log

| # | Topic | Decision |
|---|---|---|
| 1 | Camera Calibration | Reminder-only UX. Always tappable. Mid-session failures continue — logged as "No Scan" (Red) |
| 2 | ML Inference Aggregation | Majority vote for label + average confidence of winning label's frames |
| 3 | Clip Per Loop Occurrence | Each move occurrence = independent timestamp + independent clip |
| 4 | Manual Stop | Confirmation dialog required. Result page always shows |
| 5 | Clip Storage Lifetime | Deleted when user leaves Result screen or app is closed |
| 6 | JPG Export | Exports **entire scrollable content** as one long image |
| 7 | Green Tappable | Yes — all timestamps are tappable. Green modal shows "Excellent" message, no clip |
| 8 | Model Unknown / No Move | Treated as "No Movement Detected" → 0% confidence → 🔴 Red → clip saved |

---

## Executive Summary

ShadowBox is a real-time shadow boxing training companion app with AI-powered movement analysis. The app guides users through selected boxing combos, captures their performance via computer vision, analyzes movements using a CoreML model, and provides detailed performance feedback.

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
┌─────────────┐
│   RECORD    │  (Camera calibration → Recording → Analysis)
└──────┬──────┘
       │ Session ends (2 min or manual stop)
       ▼
┌─────────────┐
│   RESULT    │  (Performance summary & detailed breakdown)
└─────────────┘
```

### Tech Stack Required
- **Language:** Swift / SwiftUI
- **Camera & Vision:** AVFoundation + Vision framework
- **ML Inference:** CoreML (pre-trained model provided by team)
- **Audio:** AVFoundation (placeholder audio files)
- **Clip Recording:** AVAssetWriter + AVAssetWriterInput (auto-clip Yellow/Red movements)
- **Clip Playback:** AVPlayer + AVKit VideoPlayer
- **UI Export:** UIGraphicsImageRenderer (JPG export)
- **Storage:** In-memory session management + local file system for clips (temp + permanent)

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
│  CAMERA CALIBRATION PHASE            │
│  (Vision framework scans for pose)   │
│  User taps "I'm Ready"               │
└──────────────┬───────────────────────┘
               │
               ▼
┌──────────────────────────────────────┐
│  RECORDING / SHADOW BOXING PHASE     │
│  (2 minutes, sequential moves)       │
└──────────────┬───────────────────────┘
               │
               ▼
┌──────────────────────────────────────┐
│  SESSION ENDS                        │
│  Navigate to Result screen           │
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

#### Move Sequencing Logic

- Moves from the selected combo play **sequentially**, one at a time
- Each move gets a **3-second window**
- When combo finishes, it **loops** until 2-minute timer expires or user stops

**Example (Combo: Jab → Straight):**
```
0:00 - 0:03  → Jab (audio cue: "JAB!", timer counts down)
0:03 - 0:06  → Straight (audio cue: "STRAIGHT!", timer counts down)
0:06 - 0:09  → Jab (loop repeats)
0:09 - 0:12  → Straight
... (continues until 2:00 or manual stop)
```

#### 3-Second Movement Window Breakdown

**Start of Window (T=0s):**
- Audio cue plays (e.g., "JAB!")
- UI displays current move name
- Camera capture begins
- CoreML inference loop starts

**During Window (T=0-3s):**
- Camera frames are captured at regular intervals (e.g., 30 fps)
- Each frame is fed into MLInferenceEngine
- Model returns predicted move + confidence score
- Movement data is collected in real-time

**End of Window (T=3s):**
- Movement data is aggregated
- Result is logged (correct/incorrect, confidence %)
- UI log is updated with new entry
- Advance to next move in sequence

#### Movement Analysis

**Clarified Aggregation Logic (v3.0):**

At ~30fps over 3 seconds, the model produces ~90 predictions per window. These are aggregated using two rules:

1. **Predicted Label** → **Most Frequent Label** (majority vote across all frames)
2. **Confidence Score** → **Average Confidence** of all frames for the winning label

```swift
struct FramePrediction {
    let label: String       // e.g. "jab"
    let confidence: Float   // 0.0 - 1.0
}

struct MovementAggregator {

    // Called at T=3s with all collected frame predictions
    func aggregate(predictions: [FramePrediction]) -> (label: String, confidence: Float) {

        guard !predictions.isEmpty else {
            // No frames captured — body not detected
            return ("no_movement_detected", 0.0)
        }

        // Step 1: Find the most frequent label (majority vote)
        let labelCounts = Dictionary(grouping: predictions, by: { $0.label })
            .mapValues { $0.count }
        let dominantLabel = labelCounts.max(by: { $0.value < $1.value })?.key ?? "no_movement_detected"

        // Step 2: Average confidence of all frames that voted for dominant label
        let dominantFrames = predictions.filter { $0.label == dominantLabel }
        let avgConfidence = dominantFrames.map { $0.confidence }.reduce(0, +) / Float(dominantFrames.count)

        return (dominantLabel, avgConfidence)
    }
}
```

**Example:**
```
90 frames collected during "Jab" window:
  - 60 frames predicted: "jab" (avg confidence 91%)
  - 20 frames predicted: "straight" (avg confidence 70%)
  - 10 frames predicted: "left hook" (avg confidence 55%)

Result:
  → Dominant label: "jab" (60 votes — majority)
  → Final confidence: 91% (average of jab frames only)
  → Rating: 🟢 GREEN
```

For each 3-second window:

```swift
struct MovementAnalysis {
    let expectedMove: String
    let predictedMove: String   // Most frequent label
    let confidence: Float       // Average confidence of dominant label frames
    let isAccurate: Bool

    // isAccurate = (predictedMove == expectedMove) && (confidence >= 0.85)
}
```

**Confidence Threshold for Accuracy:** 85% (aligns with Green rating = correct execution)

#### CoreML Integration (PLACEHOLDER)

```swift
class MLInferenceEngine {
    // PLACEHOLDER — Team to integrate CoreML model
    
    func loadModel() {
        // TODO: Load YourActionClassifier.mlmodel
    }
    
    func predictMove(poseObservations: [VNHumanBodyPoseObservation]) -> (label: String, confidence: Float) {
        // TODO: Convert pose observations to model input
        // TODO: Run inference
        // TODO: Parse output (label, confidence)
        // Return predicted label and confidence score
    }
}
```

**Expected Model Output:**
- **Labels:** "jab", "straight", "left hook", "right hook", "left uppercut", "right uppercut"
- **Confidence:** Float (0.0 - 1.0)

#### Audio Cue System (PLACEHOLDER)

```swift
class AudioCuePlayer {
    // PLACEHOLDER — Developer to add sound files
    
    let audioFilePaths: [String: String] = [
        "jab": "cue_jab.mp3",                       // TODO: Add file
        "straight": "cue_straight.mp3",             // TODO: Add file
        "left hook": "cue_left_hook.mp3",           // TODO: Add file
        "right hook": "cue_right_hook.mp3",         // TODO: Add file
        "left uppercut": "cue_left_uppercut.mp3",   // TODO: Add file
        "right uppercut": "cue_right_uppercut.mp3"  // TODO: Add file
    ]
    
    func playAudioCue(for move: String) {
        // TODO: Load audio file for move
        // TODO: Play using AVAudioPlayer or AVPlayer
    }
}
```

#### Movement Logger

Every 3 seconds, a new `SessionEvent` (from `Models.swift`) is appended to the session log:

```swift
// NOTE: Do NOT create a new struct — use the existing SessionEvent from Models.swift
// The following shows what fields SessionEvent must support for logging:

// SessionEvent fields used per window:
//   - id: UUID
//   - timestamp: Date
//   - elapsedTime: TimeInterval  (seconds from session start)
//   - expectedMove: Move         (the Move value from allMoves)
//   - predictedMove: String      (label returned by MLInferenceEngine)
//   - confidence: Float          (0.0 - 1.0, aggregated by MovementAggregator)
//   - isAccurate: Bool           (predictedMove == expectedMove.label && confidence >= 0.85)
//   - clipURL: URL?              (nil for Green, saved URL for Yellow/Red/NoScan/NoMovement)

// Appended to SessionState.events every 3 seconds inside SessionManager
```

#### Live Movement Log UI Display

**Requirements:**
- Log updates every 3 seconds (one entry per movement window)
- Shows: timestamp, move name, result (✅/❌), confidence %
- Is scrollable and displays latest entries at bottom
- Example log entry display:

```
[00:03] Expected: Jab | Predicted: Jab | ✅ 92%
[00:06] Expected: Straight | Predicted: Straight | ✅ 88%
[00:09] Expected: Jab | Predicted: Left Hook | ❌ 65%
[00:12] Expected: Straight | Predicted: Straight | ✅ 91%
```

#### Session Manager (Core Orchestration)

**Clarified Rules (v3.0):**
- **Manual Stop** → Shows a **confirmation dialog** before stopping. Result page always shows regardless of how many movements were completed.
- **Combo Looping** → Each occurrence of a move in each loop is treated as its **own independent timestamp and clip**. If the user performs "Jab" 15 times across loops, there are 15 separate log entries and up to 15 separate clips (Yellow/Red only).

```swift
class SessionManager: ObservableObject {
    @Published var isRecording: Bool = false
    @Published var currentMoveIndex: Int = 0
    @Published var elapsedTime: TimeInterval = 0
    @Published var events: [SessionEvent] = []  // Uses existing SessionEvent from Models.swift
    @Published var showStopConfirmation: Bool = false

    let sessionDuration: TimeInterval = 120  // 2 minutes — fixed
    let moveWindowDuration: TimeInterval = 3.0
    let selectedCombo: [String]

    // Global window counter — increments every 3s regardless of combo position
    // Used for unique clip file naming and timestamp tracking
    private var globalWindowIndex: Int = 0

    var currentMove: String {
        let loopedIndex = currentMoveIndex % selectedCombo.count
        return selectedCombo[loopedIndex]
    }

    func startRecording() {
        isRecording = true
        globalWindowIndex = 0
        startSessionTimer()
        startMoveTimer()
    }

    // Called when user taps Stop button
    func requestStop() {
        showStopConfirmation = true  // Triggers confirmation dialog
    }

    // Called when user confirms stop in dialog
    func confirmStop() {
        showStopConfirmation = false
        finalizeSession()
    }

    // Called when user cancels stop in dialog
    func cancelStop() {
        showStopConfirmation = false
        // Session continues normally
    }

    func finalizeSession() {
        isRecording = false
        // Build SessionState from collected SessionEvents
        // Store in SessionStore.shared
        // Navigate to Result screen
    }

    func startSessionTimer() {
        // Timer that runs every 1 second
        // Updates elapsedTime
        // When elapsedTime >= 120 → call finalizeSession()
    }

    func startMoveTimer() {
        // Timer that fires every 3 seconds
        // On fire:
        //   1. Aggregate frame predictions → (label, confidence)
        //   2. Evaluate clip (keep or discard)
        //   3. Append new SessionEvent with globalWindowIndex
        //   4. globalWindowIndex += 1
        //   5. currentMoveIndex += 1 (loops via modulo)
        //   6. Start next window: audio cue + clip recording
    }
}
```

**Confirmation Dialog UI:**
```swift
Alert(
    title: Text("Stop Session?"),
    message: Text("Your current progress will be saved and taken to the results page."),
    primaryButton: .destructive(Text("Stop")) {
        sessionManager.confirmStop()
    },
    secondaryButton: .cancel(Text("Continue")) {
        sessionManager.cancelStop()
    }
)
```

#### Recording Session State

During the 2-minute recording, the app maintains state using the existing `SessionState` from `Models.swift`:

```swift
// NOTE: Do NOT create a new struct — use the existing SessionState from Models.swift
// SessionState must hold:
//   - sessionID: UUID
//   - selectedCombo: Combo       (the Combo value chosen in MenuView)
//   - startTime: Date
//   - events: [SessionEvent]     (appended every 3 seconds)
//   - isActive: Bool
//
// SessionManager owns and mutates this SessionState throughout the session
// SessionStore.shared holds the final SessionState when session ends
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
**This is the equivalent of `MovementEntry` from earlier planning notes.** One entry per 3-second window. Must support:
```swift
// Already in Models.swift — verify it has (extend if missing):
struct SessionEvent {
    let id: UUID
    let timestamp: Date
    let elapsedTime: TimeInterval   // Seconds from session start
    let expectedMove: Move          // What was prompted
    let predictedLabel: String      // What ML returned ("jab", "no_movement_detected", etc.)
    let confidence: Float           // 0.0 - 1.0 (aggregated avg)
    let isAccurate: Bool            // predictedLabel == expectedMove.id && confidence >= 0.85
    let clipURL: URL?               // nil = Green (discarded), URL = Yellow/Red/NoScan/NoMovement

    // Computed — add if missing:
    var confidencePercentage: Float { confidence * 100 }

    var movementState: MovementState {
        switch predictedLabel {
        case "no_body_detected":    return .noScan
        case "no_movement_detected": return .noMovement
        default:
            switch confidencePercentage {
            case 85...100: return .excellent
            case 50...84:  return .fair
            default:       return .poor
            }
        }
    }

    var hasClip: Bool { clipURL != nil }
}

enum MovementState {
    case excellent      // 🟢 85-100%
    case fair           // 🟡 50-84%
    case poor           // 🔴 0-49%
    case noScan         // ⚠️ body not detected
    case noMovement     // ❌ model returned unknown

    var color: Color {
        switch self {
        case .excellent:                        return .green
        case .fair:                             return .yellow
        case .poor, .noScan, .noMovement:       return .red
        }
    }

    var label: String {
        switch self {
        case .excellent:  return "Excellent"
        case .fair:       return "Fair"
        case .poor:       return "Poor"
        case .noScan:     return "No Scan"
        case .noMovement: return "No Movement"
        }
    }

    var isClipSaved: Bool { self != .excellent }
}
```

#### `SessionState`
The full state of a session — owns the list of `SessionEvent` entries. Must support:
```swift
// Already in Models.swift — verify it has (extend if missing):
struct SessionState {
    let sessionID: UUID
    let startDate: Date
    let selectedCombo: Combo
    var events: [SessionEvent]
    var totalDuration: TimeInterval

    // Computed — add if missing:
    var totalMovements: Int { events.count }

    var accurateMovements: Int {
        events.filter { $0.isAccurate }.count
    }

    var movementErrors: Int {
        events.filter { !$0.isAccurate }.count
    }

    var accuracyRate: Float {
        totalMovements == 0 ? 0 : Float(accurateMovements) / Float(totalMovements) * 100
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
- [x] Create `SessionManager` with timer logic
- [x] Create `VisionProcessor` for body pose detection
- [x] Create `SessionStore` for in-memory storage

### Phase 2: ML & Audio Integration Points
- [x] Create `MLInferenceEngine` with placeholder structure
- [x] Create `AudioCuePlayer` with audio file mappings

### Phase 3: Recording Session Flow
- [x] Implement camera calibration phase (SetupHintOverlay — UX reminder only, always tappable)
- [x] Implement move sequencing loop (combo loops via modulo on `currentMoveIndex`)
- [x] Implement 3-second move windows
- [x] Wire up ML inference to camera frames (`processFrame` → VisionProcessor → MLInferenceEngine)
- [x] Populate live punch chips in real-time (`livePunches` published state)
- [x] Implement stop confirmation dialog (timer continues while open; auto-finalizes on timeout)

### Phase 4: Result Screen & Export
- [x] Display session summary metrics (Wrong / Unclear / Avg Confidence stat cards)
- [x] Display movement timestamp breakdown (vertical timeline, all events tappable)
- [x] Implement movement detail modal (DetailSheetView — shows clip, suggestion, reference placeholder)
- [ ] **Wire JPG export** — `ResultsView.exportResults()` currently shows placeholder; must bridge UIScrollView to `ResultExporter`
- [ ] **Wire AVPlayer for user clips** — `DetailSheetView` uses `VideoPanel` placeholder; replace with `AVPlayer(url: event.clipURL!)`

### Phase 4.5: Performance Color Rating System
- [x] Create `Color.performanceColor(for:)` extension
- [x] Create `Color.performanceLabel(for:)` extension
- [x] Create `PerformanceFeedback` helper for contextual messages
- [x] `MovementState` enum with `.color` and `.label` on `SessionEvent`
- [x] Color coding applied in timeline (dot accent color per event status)
- [x] Color coding applied in detail modal (accent follows status)

### Phase 4.6: Bug Fixes Required (found in code review May 3, 2026)
- [ ] **`ClipRecorder` — `tempClipURL` race:** Call `beginMoveWindow()` inside `stopAndEvaluate` completion, not before it
- [ ] **`ClipRecorder` — thread safety:** Serialize `appendFrame` / `startClip` / `stopAndEvaluate` on a private serial queue
- [ ] **`ClipRecorder` — hardcoded resolution:** Read dimensions dynamically from pixel buffer instead of hardcoding 1080×1920
- [ ] **`allCombos` — missing 2 combos:** Add Combo 3 (LJ·RJ·LH·RH), Combo 4 (LJ·LH·RJ), Combo 5 (LJ·RJ·LU·RU), Combo 6 (RJ·RH·LU) — currently only 4 of 6 required combos exist

### Phase 5: Integration & Testing
- [ ] Integrate actual CoreML model (replace placeholder in `MLInferenceEngine`)
- [ ] Integrate audio asset files (add .mp3 files and remove TODO comments in `AudioCuePlayer`)
- [ ] Integrate reference movement videos (add .mp4 files to `ResultsView` detail sheet)
- [ ] End-to-end testing across all 3 pages
- [ ] Test clip keep/discard logic across all rating tiers

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

## Part 14: Automatic Clip Recording System (Yellow & Red Movements Only)

### Overview

The auto-clip system **selectively records and saves short video clips** during the recording session. A clip is only kept when the movement's confidence rating falls into the **Yellow (50–84%)** or **Red (0–49%)** range. Green movements (85–100%) are **discarded immediately** to save storage and avoid unnecessary data.

### Core Principle: Record-Then-Evaluate

Because the ML inference only completes **at the end** of the 3-second window, the system cannot know in advance whether a clip is worth keeping. The strategy is:

```
┌─────────────────────────────────────────────────────────────┐
│  ALWAYS start recording at the beginning of every window    │
│  → Run inference during the 3 seconds                       │
│  → At T=3s, evaluate the confidence rating                  │
│  → IF Yellow or Red → KEEP the clip, save to disk           │
│  → IF Green         → DISCARD the clip, delete temp file    │
└─────────────────────────────────────────────────────────────┘
```

---

### Step-by-Step Flow Per 3-Second Window

```
T = 0.0s  ─── Audio cue plays ("JAB!")
           ─── UI prompt shows current move
           ─── AVAssetWriter starts recording to temp file
           ─── Vision + CoreML inference begins on live frames

T = 0.0s
  to      ─── Frames captured continuously (30 fps)
T = 3.0s  ─── Pose observations fed to ML model
           ─── Confidence scores aggregated

T = 3.0s  ─── AVAssetWriter stops, finalizes temp clip file
           ─── ML returns final predicted label + confidence

           ─── Evaluate rating:
               ┌─────────────────────────────────────────┐
               │ confidence >= 85%  → 🟢 GREEN           │
               │   → Delete temp clip file               │
               │   → userClipURL = nil                   │
               ├─────────────────────────────────────────┤
               │ confidence 50–84%  → 🟡 YELLOW          │
               │   → Move temp clip to permanent path    │
               │   → userClipURL = saved clip URL        │
               ├─────────────────────────────────────────┤
               │ confidence 0–49%   → 🔴 RED             │
               │   → Move temp clip to permanent path    │
               │   → userClipURL = saved clip URL        │
               └─────────────────────────────────────────┘

           ─── Log MovementEntry with userClipURL (or nil)
           ─── Advance to next move
```

---

### ClipRecorder Service

```swift
import AVFoundation

class ClipRecorder {

    // MARK: - Properties

    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var tempClipURL: URL?
    private var isRecording: Bool = false
    private var frameCount: Int64 = 0
    private let frameRate: Int32 = 30

    // MARK: - Temp Storage Directory

    private var tempDirectory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ShadowBoxClips", isDirectory: true)
    }

    // MARK: - Permanent Storage Directory

    private var permanentDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SessionClips", isDirectory: true)
    }

    // MARK: - Setup

    func prepareDirectories() {
        let fm = FileManager.default
        try? fm.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try? fm.createDirectory(at: permanentDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Start Recording (Called at T=0s of each window)

    func startClip(for move: String, windowIndex: Int) {
        prepareDirectories()

        let fileName = "temp_\(move.replacingOccurrences(of: " ", with: "_"))_\(windowIndex).mp4"
        let url = tempDirectory.appendingPathComponent(fileName)

        // Remove any leftover temp file
        try? FileManager.default.removeItem(at: url)
        tempClipURL = url

        do {
            assetWriter = try AVAssetWriter(outputURL: url, fileType: .mp4)
        } catch {
            print("ClipRecorder: Failed to create AVAssetWriter — \(error)")
            return
        }

        // Video settings (match capture session resolution)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 1080,
            AVVideoHeightKey: 1920
        ]

        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput?.expectsMediaDataInRealTime = true

        adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput!,
            sourcePixelBufferAttributes: nil
        )

        if let videoInput = videoInput, assetWriter?.canAdd(videoInput) == true {
            assetWriter?.add(videoInput)
        }

        assetWriter?.startWriting()
        assetWriter?.startSession(atSourceTime: .zero)
        frameCount = 0
        isRecording = true

        print("ClipRecorder: Started recording clip for \(move)")
    }

    // MARK: - Append Frame (Called on every camera frame during window)

    func appendFrame(_ pixelBuffer: CVPixelBuffer) {
        guard isRecording,
              let videoInput = videoInput,
              videoInput.isReadyForMoreMediaData,
              let adaptor = adaptor else { return }

        let presentationTime = CMTime(value: frameCount, timescale: frameRate)
        adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
        frameCount += 1
    }

    // MARK: - Stop and Evaluate (Called at T=3s)

    func stopAndEvaluate(
        confidence: Float,
        predictedLabel: String,
        move: String,
        windowIndex: Int,
        completion: @escaping (_ savedClipURL: URL?) -> Void
    ) {
        guard isRecording else {
            completion(nil)
            return
        }

        isRecording = false
        videoInput?.markAsFinished()

        assetWriter?.finishWriting { [weak self] in
            guard let self = self else { return }

            let confidencePercentage = confidence * 100

            // Special cases: no body detected or no movement — always keep clip as Red
            let isSpecialCase = (predictedLabel == "no_body_detected" || predictedLabel == "no_movement_detected")

            if !isSpecialCase && confidencePercentage >= 85 {
                // 🟢 GREEN — Discard clip
                if let tempURL = self.tempClipURL {
                    try? FileManager.default.removeItem(at: tempURL)
                    print("ClipRecorder: Green rating — clip discarded for \(move)")
                }
                completion(nil)

            } else {
                // 🟡 YELLOW, 🔴 RED, ⚠️ NO SCAN, ❌ NO MOVEMENT — Keep clip
                let ratingTag: String
                if predictedLabel == "no_body_detected" {
                    ratingTag = "noscan"
                } else if predictedLabel == "no_movement_detected" {
                    ratingTag = "nomovement"
                } else if confidencePercentage >= 50 {
                    ratingTag = "yellow"
                } else {
                    ratingTag = "red"
                }

                let savedName = "\(ratingTag)_\(move.replacingOccurrences(of: " ", with: "_"))_\(windowIndex)_\(Int(Date().timeIntervalSince1970)).mp4"
                let savedURL = self.permanentDirectory.appendingPathComponent(savedName)

                do {
                    if let tempURL = self.tempClipURL {
                        try FileManager.default.moveItem(at: tempURL, to: savedURL)
                        print("ClipRecorder: [\(ratingTag.uppercased())] clip saved: \(savedName)")
                        completion(savedURL)
                    } else {
                        completion(nil)
                    }
                } catch {
                    print("ClipRecorder: Failed to save clip — \(error)")
                    completion(nil)
                }
            }
        }
    }

    // MARK: - Cleanup (Called when session ends or app clears memory)

    func deleteAllClips() {
        let fm = FileManager.default

        // Clear temp directory
        if let tempFiles = try? fm.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil) {
            tempFiles.forEach { try? fm.removeItem(at: $0) }
        }

        // Clear permanent directory
        if let savedFiles = try? fm.contentsOfDirectory(at: permanentDirectory, includingPropertiesForKeys: nil) {
            savedFiles.forEach { try? fm.removeItem(at: $0) }
        }

        print("ClipRecorder: All clips deleted from storage")
    }
}
```

---

### Integration Into SessionManager

The `ClipRecorder` is wired directly into the 3-second move window loop inside `SessionManager`:

```swift
class SessionManager: ObservableObject {

    private let clipRecorder = ClipRecorder()

    // Called at T=0s — beginning of each move window
    func beginMoveWindow(move: String, windowIndex: Int) {
        // 1. Play audio cue
        AudioCuePlayer.shared.playAudioCue(for: move)

        // 2. Update UI
        currentMove = move

        // 3. Start clip recording for this window
        clipRecorder.startClip(for: move, windowIndex: windowIndex)

        // 4. Start 3-second timer
        startMoveTimer(move: move, windowIndex: windowIndex)
    }

    // Called on every camera frame — during the 3-second window
    func onCameraFrame(_ pixelBuffer: CVPixelBuffer) {
        // 1. Feed frame to Vision + CoreML
        visionProcessor.detectBodyPose(from: pixelBuffer) { observations in
            let result = self.mlEngine.predictMove(from: observations)
            self.currentFramePredictions.append(result)
        }

        // 2. Feed frame to ClipRecorder simultaneously
        clipRecorder.appendFrame(pixelBuffer)
    }

    // Called at T=3s — end of each move window
    func endMoveWindow(move: String, windowIndex: Int) {
        // 1. Aggregate ML predictions from this window
        let finalConfidence = aggregatePredictions(currentFramePredictions)
        let finalLabel = dominantLabel(currentFramePredictions)
        currentFramePredictions = []

        // 2. Stop recording and evaluate rating
        clipRecorder.stopAndEvaluate(
            confidence: finalConfidence,
            move: move,
            windowIndex: windowIndex
        ) { savedClipURL in

            // 3. Build SessionEvent and append to session
            let event = SessionEvent(
                id: UUID(),
                timestamp: Date(),
                elapsedTime: self.elapsedTime,
                expectedMove: self.currentExpectedMove,
                predictedLabel: finalLabel,
                confidence: finalConfidence,
                isAccurate: (finalLabel == self.currentExpectedMove.id) && (finalConfidence >= 0.85),
                clipURL: savedClipURL
            )

            DispatchQueue.main.async {
                self.events.append(event)
            }
        }

        // 4. Advance to next move
        advanceToNextMove()
    }
}
```

---

### Decision Logic Summary

```swift
// At T=3s, after inference completes:

func shouldKeepClip(confidence: Float) -> Bool {
    let percentage = confidence * 100
    return percentage < 85  // Keep Yellow (50-84%) and Red (0-49%) only
}

// Green (85-100%) → discard → userClipURL = nil
// Yellow (50-84%) → keep   → userClipURL = permanent file URL
// Red (0-49%)     → keep   → userClipURL = permanent file URL
```

---

### File Naming Convention

Saved clips follow a structured naming pattern for easy debugging:

```
red_jab_3_1746278400.mp4
 │    │   │      │
 │    │   │      └── Unix timestamp (unique per clip)
 │    │   └───────── Window index (3rd move in session)
 │    └───────────── Move name
 └────────────────── Performance rating (yellow / red)
```

---

### Clip Playback in Movement Detail Modal

When the user taps a Yellow or Red timestamp on the Result screen, the modal checks `userClipURL`:

```swift
struct MovementDetailModal: View {
    let movement: MovementEntry

    var body: some View {
        VStack(spacing: 20) {

            // Section 1: User's performance clip
            if let clipURL = movement.userClipURL {
                // Clip exists (Yellow or Red movement)
                VideoPlayer(player: AVPlayer(url: clipURL))
                    .frame(height: 300)
                    .cornerRadius(12)
                    .overlay(
                        Text("Your Performance")
                            .font(.caption)
                            .padding(6)
                            .background(Color.black.opacity(0.5))
                            .foregroundColor(.white)
                            .cornerRadius(6),
                        alignment: .topLeading
                    )
            } else {
                // No clip (Green movement — shouldn't normally open modal)
                Text("No clip available — movement was rated Excellent.")
                    .foregroundColor(.gray)
                    .italic()
            }

            // Section 2: Developer suggestion
            Text(moveSuggestions[movement.expectedMove.lowercased()] ?? "")
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)

            // Section 3: Reference video (PLACEHOLDER)
            // TODO: Replace with actual reference video asset
            Text("Reference Video Placeholder — \(movement.expectedMove)")
                .foregroundColor(.gray)
                .italic()
        }
        .padding()
    }
}
```

---

### Memory & Storage Management

### Memory & Storage Management

#### During Session
- **Temp directory:** Stores the currently recording clip (overwritten each window)
- **Permanent directory:** Accumulates Yellow/Red clips throughout the session
- **Green windows:** Temp file deleted immediately, zero storage cost

#### Clip Lifecycle (Clarified v3.0)

```
Session starts
    → Clips accumulate in permanent directory (Yellow/Red only)

Session ends → Result screen shows
    → Clips remain accessible for modal playback

User leaves Result screen (back navigation / new session)
    → ALL clips deleted from permanent directory
    → SessionStore cleared

App is closed / terminated
    → iOS clears temp directory automatically
    → Permanent directory is cleared on next app launch (startup cleanup)
```

**Startup Cleanup (run once on app launch):**
```swift
class AppDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions ...) -> Bool {
        // Clean up any leftover clips from previous session
        ClipRecorder.shared.deleteAllClips()
        return true
    }
}
```

**On Result Screen Dismiss:**
```swift
// Called when user navigates away from Result screen
.onDisappear {
    ClipRecorder.shared.deleteAllClips()
    SessionStore.shared.clearCurrentSession()
}
```

#### Estimated Storage per Session
| Rating | Clip Length | Approx Size | Kept? |
|---|---|---|---|
| 🟢 Green | 3 seconds | ~5MB | ❌ Deleted immediately |
| 🟡 Yellow | 3 seconds | ~5MB | ✅ Until Result dismissed |
| 🔴 Red | 3 seconds | ~5MB | ✅ Until Result dismissed |
| ⚠️ No Detection | 3 seconds | ~5MB | ✅ Until Result dismissed |

In a 2-minute session (~40 windows), worst case all Yellow/Red = ~200MB. Realistically much less.

---

### Updated Data Model

```swift
// Extend SessionEvent in Models.swift — do not create a new file

extension SessionEvent {
    // Convenience check used by ClipRecorder and modal UI
    var hasClip: Bool { clipURL != nil }

    // predictedLabel special values:
    // "no_body_detected"     → body lost mid-session
    // "no_movement_detected" → model returned unknown / no frames
    // "jab", "straight", "left hook", etc. → valid ML output
}
```

---

### Updated Implementation Checklist (Auto-Clip)

- [ ] Create `ClipRecorder` service class
- [ ] Implement `startClip()` — begins `AVAssetWriter` at T=0s
- [ ] Implement `appendFrame()` — feeds pixel buffers during window
- [ ] Implement `stopAndEvaluate()` — keeps or discards based on rating
- [ ] Wire `ClipRecorder` into `SessionManager.beginMoveWindow()`
- [ ] Wire `ClipRecorder` into `SessionManager.onCameraFrame()`
- [ ] Wire `ClipRecorder` into `SessionManager.endMoveWindow()`
- [ ] Implement `deleteAllClips()` cleanup on new session start
- [ ] Update `MovementEntry` with `hasClip` computed property
- [ ] Implement `MovementDetailModal` clip playback with `AVPlayer`
- [ ] Test: Green movement → temp file deleted, `userClipURL` = nil
- [ ] Test: Yellow movement → clip saved, `userClipURL` = valid URL
- [ ] Test: Red movement → clip saved, `userClipURL` = valid URL
- [ ] Test: Modal playback of saved clip

---

This document provides a **complete blueprint** for the ShadowBox backend. All placeholder integration points are clearly marked with `TODO` comments. The frontend UI is assumed to be final and immutable — the backend is designed to seamlessly plug in and support it.

**Next Steps:**
1. Share the frontend SwiftUI code
2. Developer team provides CoreML model + audio files + reference videos
3. Implement services using this architecture
4. Wire services into views
5. Test end-to-end flow

---

---

## Part 15: Known Bugs — Found in Code Review (May 3, 2026)

These bugs were identified during a full code review of the May 3 backend implementation. Fix them before proceeding to asset integration or end-to-end testing.

### Bug 1 — `ClipRecorder`: `tempClipURL` Overwrite Race (Critical)

**Location:** `SessionManager.swift` — `endMoveWindow()` and `ClipRecorder.swift` — `stopAndEvaluate()`

**Problem:** `endMoveWindow()` calls `stopAndEvaluate()` and then *immediately* (synchronously) calls `beginMoveWindow()` → `startClip()`. `AVAssetWriter.finishWriting` is asynchronous — its completion closure hasn't fired yet. `startClip()` overwrites `ClipRecorder.shared.tempClipURL` with the *next* window's path. When the old completion fires, `self.tempClipURL` now points to the wrong file: green clips wrongly delete the new temp file, or yellow/red clips save to an incorrect URL.

**Fix:** Move the `beginMoveWindow()` call *inside* the `stopAndEvaluate` completion closure so the next window only starts after the previous writer fully finalizes.

```swift
// In endMoveWindow() — replace the current synchronous advance with:
ClipRecorder.shared.stopAndEvaluate(...) { [weak self] clipURL in
    guard let self else { return }
    // ... build and append SessionEvent ...
    DispatchQueue.main.async {
        self.collectedEvents.append(event)
        // Advance AFTER the old writer is fully done
        self.globalWindowIndex += 1
        self.currentMoveIndex += 1
        if self.isRecording {
            self.beginMoveWindow()
        }
    }
}
// Remove the synchronous advance block that currently follows stopAndEvaluate
```

---

### Bug 2 — `ClipRecorder`: Thread Safety (Critical)

**Location:** `ClipRecorder.swift` — `appendFrame(_:)`, `startClip(for:windowIndex:)`, `stopAndEvaluate(...)`

**Problem:** `appendFrame` is called from the camera frame queue (`shadowbox.camera.frames`). `startClip` and `stopAndEvaluate` are called from the main thread. `isCapturing`, `frameCount`, `videoInput`, and `adaptor` are mutated from both threads with no synchronization, creating data races.

**Fix:** Add a private serial `DispatchQueue` to `ClipRecorder` and route all state mutations through it.

```swift
private let clipQueue = DispatchQueue(label: "shadowbox.cliprecorder", qos: .userInteractive)

func appendFrame(_ pixelBuffer: CVPixelBuffer) {
    clipQueue.async { [weak self] in
        guard let self, self.isCapturing, ... else { return }
        // ... append logic
    }
}

func startClip(for moveId: String, windowIndex: Int) {
    clipQueue.async { [weak self] in
        // ... setup logic (was previously on main thread)
    }
}
```

---

### Bug 3 — `ClipRecorder`: Hardcoded Video Resolution (Significant)

**Location:** `ClipRecorder.swift:53-57`

**Problem:** `AVVideoWidthKey: 1080, AVVideoHeightKey: 1920` is hardcoded. The capture session uses `.high` preset, which outputs different pixel buffer dimensions on different devices (e.g., 1280×720 on some). If the writer dimensions don't match the actual buffer, AVAssetWriter silently drops frames.

**Fix:** Read dimensions from the first pixel buffer, or remove explicit width/height keys and let AVAssetWriter infer from the adaptor.

---

### Bug 4 — `allCombos` Missing 2 Combos (Significant)

**Location:** `Models.swift:112-117`

**Problem:** `allCombos` defines only 4 combos. The spec requires exactly 6. The two missing combos cause `MenuView` to show an incomplete list.

**Combos to add:**

```swift
Combo(id: "c5", name: "Jab Cross Hooks",    subtitle: "Four-punch chain",  moveIds: ["lj", "rj", "lh", "rh"]),
Combo(id: "c6", name: "Jab Hook Cross",     subtitle: "Cut-back power",    moveIds: ["lj", "lh", "rj"]),
```

*(Combos 5 and 6 from the spec — Jab·Straight·LU·RU and Cross·RHook·LUppercut — may need different moveId mappings depending on final ML model label spec. Confirm with team before adding.)*

---

### Bug 5 — JPG Export Not Wired (Significant)

**Location:** `ResultsView.swift:119-126`

**Problem:** `exportResults()` displays a placeholder string. `ResultExporter` is implemented but never called.

**Fix:** Use a `UIHostingController` snapshot to get a `UIScrollView` reference from the SwiftUI `ScrollView`, then pass it to `ResultExporter.exportFullResultAsJPG(scrollView:)`. Alternatively, use `ImageRenderer` (iOS 16+) to render the full `VStack` content directly without needing a `UIScrollView` bridge.

---

**Document Version:** 5.2 — Backend Implemented; Bug Fixes Outstanding
**Last Updated:** May 4, 2026
**Prepared By:** 50-Year Veteran iOS Developer & AI Engineer
