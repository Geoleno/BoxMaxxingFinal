# Full Body Skeleton Overlay — Design Spec
**Date:** 2026-05-05  
**Status:** Approved

---

## Goal

Render a real-time full body skeleton overlay on top of the live camera feed during the recording session. The skeleton uses Vision's `VNDetectHumanBodyPoseRequest` (19 joints, full body including legs) and is styled with a glowing red/white aesthetic that matches the app's dark boxing theme.

---

## Scope

- Live recording session only (`.recording` phase in `RecordingView`)
- Always visible when a body is detected; hidden when no body is in frame
- No changes to post-session playback or results screen

---

## Data Flow

```
CameraView.captureOutput()
    → SessionManager.processFrame(pixelBuffer)
        → VisionProcessor.detectBodyPose()        [existing]
            → extract joints from VNHumanBodyPoseObservation
        → SessionManager publishes SkeletonFrame?
            → RecordingView ZStack
                → SkeletonOverlayView (SwiftUI Canvas)
                    → draws glow skeleton each frame
```

`SessionManager` gains one new `@Published` property:  
```swift
@Published var currentSkeleton: SkeletonFrame?
```
Set after every Vision callback during recording. Cleared to `nil` when `isRecording` becomes `false`.

---

## New Types

### `SkeletonFrame` (added to `Models.swift`)

```swift
struct SkeletonFrame {
    let joints: [VNHumanBodyPoseObservation.JointName: CGPoint]     // normalized 0–1, origin bottom-left
    let confidence: [VNHumanBodyPoseObservation.JointName: Float]   // per-joint confidence
}
```

Joints with confidence below **0.3** are skipped during drawing.

---

## Components

### New: `Views/SkeletonOverlayView.swift`

A SwiftUI `View` containing a `Canvas`. Receives:
- `skeleton: SkeletonFrame?` — current joint data (nil = nothing drawn)
- Uses `GeometryReader` internally for coordinate conversion

**Coordinate conversion:**  
Vision uses normalized coords with origin bottom-left. Screen uses top-left origin. Conversion:
```
screenX = jointX * viewWidth
screenY = (1 - jointY) * viewHeight
```

**Bone connections (16 total):**
```
Head:    nose → neck
Torso:   neck → leftShoulder
         neck → rightShoulder
         leftShoulder → leftHip
         rightShoulder → rightHip
         leftHip → rightHip
Arms:    leftShoulder → leftElbow → leftWrist
         rightShoulder → rightElbow → rightWrist
Legs:    leftHip → leftKnee → leftAnkle
         rightHip → rightKnee → rightAnkle
```

**Rendering — 3-pass glow per bone:**

| Pass | Stroke Width | Color | Purpose |
|------|-------------|-------|---------|
| 1 — outer halo | 12pt | `systemRed` @ 15% opacity | wide soft glow |
| 2 — inner glow | 6pt  | `systemRed` @ 40% opacity | tight glow core |
| 3 — bright line | 2pt | white @ 90% opacity | sharp visible line |

**Joint dots:**
- Background: 10pt filled circle, `systemRed` @ 30% opacity
- Foreground: 6pt filled circle, white @ 90% opacity

**Blend mode:** `.screen` on the entire view — glow composites naturally over dark camera feed.

### Modified: `Models.swift`
- Add `SkeletonFrame` struct (imports `Vision`)

### Modified: `VisionProcessor.swift`
- Add `extractSkeleton(from:) -> SkeletonFrame?` method
- Takes the first `VNHumanBodyPoseObservation` from results, extracts all 19 joints and confidence values

### Modified: `SessionManager.swift`
- Add `@Published var currentSkeleton: SkeletonFrame?`
- In `processFrame()`: after Vision callback, call `visionProcessor.extractSkeleton(from:)` and publish result on main queue
- In `finalizeSession()`: set `currentSkeleton = nil`

### Modified: `RecordingView.swift`
- In the ZStack, add `SkeletonOverlayView` between `CameraPreviewView` and the vignette overlay
- Only rendered during `.recording` phase (guard via `phase == .recording`)
- Reads `sessionManager.currentSkeleton`

---

## Visual Style

- Color palette: `Color(UIColor.systemRed)` for glow, white for core lines — matches existing app accent
- View blend mode: `.screen` for natural light-on-dark glow compositing
- No animation transitions on joints — raw position updates at camera frame rate (~30fps)

---

## Out of Scope

- Skeleton visibility in post-session video playback
- Per-joint confidence color coding
- Skeleton fade in/out on detection loss
- 3D pose (`VNDetectHumanBodyPose3DRequest`)
