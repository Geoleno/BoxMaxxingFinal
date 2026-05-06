# BoxMaxxing

An iOS boxing training app that uses the device camera to analyse punch technique in real time. During a session the app tracks your body pose frame-by-frame, classifies each movement with a CoreML model, and produces a timestamped results screen at the end so you can review exactly where your form broke down.

---

## Features

- **Live skeleton overlay** — Vision body-pose detection draws a red wireframe over your body during recording so you can see what the camera sees.
- **Per-frame movement detection** — A 3-state machine (idle → confirming → cooldown) confirms each punch over 3 consecutive frames before logging it, filtering out noise and false positives.
- **Wrong-movement classification** — Each logged movement is classified as either *Wrong technique* (you threw a different punch than requested) or *Bad execution* (correct punch but below the 80 % confidence threshold).
- **Session results timeline** — After recording, a scrollable timeline shows every flagged movement in chronological order with colour-coded cards: red for wrong technique, yellow for bad execution.
- **Video playback with seek** — Tapping a result card opens a detail sheet that plays your clip and seeks automatically to the moment the error was detected.
- **Good-example video** — Each detail sheet also plays a reference clip showing the correct technique for that punch.
- **Coach notes & form checklist** — Every card includes written feedback and a drill checklist tailored to the punch type (jab, hook, uppercut).
- **Audio cues** — The app calls out each target punch as the combo window begins.
- **Portrait-locked UI** — The interface is locked to portrait orientation throughout.

---

## Supported Punches

| ID | Name | Description |
|----|------|-------------|
| `lj` | Jab | Left-hand straight punch |
| `rj` | Straight | Right-hand straight punch |
| `lh` | Left Hook | Left hook |
| `rh` | Right Hook | Right hook |
| `lu` | Left Uppercut | Left uppercut |
| `ru` | Right Uppercut | Right uppercut |

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| UI | SwiftUI |
| Camera & recording | AVFoundation |
| Body pose detection | Vision (`VNDetectHumanBodyPoseRequest`) |
| Movement classification | CoreML (`80_epoch.mlmodelc`) |
| Video playback | AVKit `VideoPlayer` |
| Minimum deployment | iOS 17 |

---

## Project Structure

```
BoxMaxxingFinal/
├── BoxMaxxingFinalApp.swift      # App entry point, portrait-orientation lock
├── ContentView.swift             # Root router (menu → record → results)
├── Models.swift                  # All data models, SessionStatistics, demo data generator
│
├── Screens/                      # Full-screen views — no business logic
│   ├── MenuView.swift            # Combo selection and session start
│   ├── RecordingView.swift       # Live camera feed, HUD, skeleton overlay
│   └── ResultsView.swift         # Session timeline, stat cards, detail sheet
│
├── Views/                        # Reusable sub-views and UIKit bridges
│   ├── CameraView.swift          # AVFoundation camera capture (UIViewRepresentable)
│   └── SkeletonOverlayView.swift # Canvas-based skeleton renderer
│
├── ReusableComponents/           # Self-contained components used across screens
│   ├── MoveGlyphView.swift       # Punch icon component
│   └── PlayerHolder.swift        # AVPlayer wrapper with adaptive aspect ratio
│
├── Services/                     # Business logic and data services
│   ├── SessionManager.swift      # Recording lifecycle, frame processing
│   ├── MovementDetector.swift    # 3-frame confirmation state machine
│   ├── MLInferenceEngine.swift   # CoreML model loading and inference
│   ├── VisionProcessor.swift     # Body pose detection and skeleton extraction
│   ├── SessionRecorder.swift     # AVAssetWriter video recording
│   ├── SessionStore.swift        # Stores results across the session boundary
│   ├── AudioCuePlayer.swift      # Plays punch-name audio cues
│   └── PostSessionAnalyzer.swift # Scaffolding for future offline analysis
│
├── Utilities/                    # Stateless helpers
│   ├── ColorExtensions.swift     # Confidence → colour mapping
│   └── PerformanceFeedback.swift # Coach notes and form cues per move
│
├── BoxMaxxingModel/
│   └── 80_epoch.mlmodelc         # Compiled CoreML model (80-epoch training run)
│
└── Video/
    ├── Proper_Example/           # Reference clips shown in the detail sheet
    │   ├── Result_Jab_Video.mp4
    │   └── Result_Straight_Video.mp4
    └── Test_Clip/                # Demo wrong-movement clips (Jab-1..4, Straight-1/3/5/6)
```

---

## How It Works

### During Recording

```
Camera frame (CVPixelBuffer + CMTime)
  → VisionProcessor   — detects body pose joints
  → MLInferenceEngine — classifies the movement (label + confidence)
  → MovementDetector  — confirms over 3 frames, applies cooldown
  → SessionManager    — appends WrongMovement to live list if flagged
```

### Session End

```
SessionManager.finalizeSession()
  → SessionRecorder.stopRecording() — finalises the video file
  → SessionStore.save()             — stores movements + video URL
  → ContentView navigates to ResultsView
```

### Results Screen

```
ResultsView reads [WrongMovement] from ContentView state
  → stat cards: Wrong Technique count (red), Bad Execution count (yellow), avg confidence
  → timeline: one card per movement, sorted by timestamp
  → tap card → DetailSheetView
      → "Your clip"    — plays clip, seeks to movement.timestamp − 0.5 s
      → "Good example" — plays reference video from bundle
      → confidence bar, coach note, form checklist
```

---

## Branches

| Branch | Purpose |
|--------|---------|
| `main` | Integration base |
| `production` | Stable, presentation-ready builds |
| `testing` | Active development and experimentation |

---

## Demo Mode

Tapping **Test Video** on the menu (or finishing any recording) loads 10 pre-generated dummy movements for the Jab + Straight combo across a simulated 2-minute session. This is used for presentations. Demo clips are picked randomly from `Video/Test_Clip/`.

To disable demo mode and show real session data, update the `onFinish` closure in `ContentView.swift` to read from `SessionStore.shared` instead of calling `generateDemoWrongMovements()`.
