# Skeleton Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render a real-time glowing full-body skeleton overlay on the live camera feed during the recording session using Vision's `VNDetectHumanBodyPoseRequest` (2D joints).

**Architecture:** `VisionProcessor` extracts a `SkeletonFrame` from each Vision observation and returns it alongside the existing body-pose result. `SessionManager` publishes the latest `SkeletonFrame?` as `@Published var currentSkeleton`. `RecordingView` layers a new `SkeletonOverlayView` (SwiftUI `Canvas`) on top of the camera feed, visible only during the `.recording` phase.

**Tech Stack:** Vision framework (`VNDetectHumanBodyPoseRequest`), SwiftUI `Canvas`, `GeometryReader`, `.blendMode(.screen)`

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `BoxMaxxingFinal/Models.swift` | Add `SkeletonFrame` struct |
| Modify | `BoxMaxxingFinal/Services/VisionProcessor.swift` | Add `extractSkeleton(from:)` |
| Modify | `BoxMaxxingFinal/Services/SessionManager.swift` | Publish `currentSkeleton`, clear on stop |
| **Create** | `BoxMaxxingFinal/Views/SkeletonOverlayView.swift` | Canvas with 3-pass glow rendering |
| Modify | `BoxMaxxingFinal/RecordingView.swift` | Layer overlay in ZStack during `.recording` |
| **Create** | `BoxMaxxingFinalTests/SkeletonOverlayTests.swift` | Coordinate conversion unit tests |

---

## Task 1: Add `SkeletonFrame` to Models.swift

**Files:**
- Modify: `BoxMaxxingFinal/Models.swift`
- Create: `BoxMaxxingFinalTests/SkeletonOverlayTests.swift`

- [ ] **Step 1: Write the failing test**

Create `BoxMaxxingFinalTests/SkeletonOverlayTests.swift`:

```swift
import XCTest
import Vision
@testable import BoxMaxxingFinal

final class SkeletonOverlayTests: XCTestCase {

    func test_skeletonFrame_storesJointsAndConfidence() {
        let joints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [
            .leftWrist: CGPoint(x: 0.3, y: 0.7)
        ]
        let confidence: [VNHumanBodyPoseObservation.JointName: Float] = [
            .leftWrist: 0.9
        ]
        let frame = SkeletonFrame(joints: joints, confidence: confidence)
        XCTAssertEqual(frame.joints[.leftWrist], CGPoint(x: 0.3, y: 0.7))
        XCTAssertEqual(frame.confidence[.leftWrist], 0.9)
    }

    func test_skeletonFrame_emptyJointsIsValid() {
        let frame = SkeletonFrame(joints: [:], confidence: [:])
        XCTAssertTrue(frame.joints.isEmpty)
    }
}
```

- [ ] **Step 2: Run test — expect compile failure** (`SkeletonFrame` not defined)

```bash
xcodebuild test -scheme BoxMaxxingFinal -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E "error:|FAILED|PASSED" | head -20
```

- [ ] **Step 3: Add `SkeletonFrame` to `Models.swift`**

Open `BoxMaxxingFinal/Models.swift`. Add this block after the `LivePunch` struct (after line 84):

```swift
// MARK: - Skeleton Frame (for live overlay)

import Vision

struct SkeletonFrame {
    /// Normalized joint positions (x: 0–1, y: 0–1, Vision origin: bottom-left)
    let joints: [VNHumanBodyPoseObservation.JointName: CGPoint]
    /// Per-joint detection confidence (0.0–1.0)
    let confidence: [VNHumanBodyPoseObservation.JointName: Float]
}
```

- [ ] **Step 4: Run tests — expect PASS**

```bash
xcodebuild test -scheme BoxMaxxingFinal -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E "error:|FAILED|PASSED" | head -20
```

Expected: `Test Suite ... passed`

- [ ] **Step 5: Commit**

```bash
git add BoxMaxxingFinal/Models.swift BoxMaxxingFinalTests/SkeletonOverlayTests.swift
git commit -m "feat: add SkeletonFrame model and tests"
```

---

## Task 2: Create `SkeletonOverlayView` with coordinate conversion

**Files:**
- Create: `BoxMaxxingFinal/Views/SkeletonOverlayView.swift`
- Modify: `BoxMaxxingFinalTests/SkeletonOverlayTests.swift`

- [ ] **Step 1: Write failing tests for coordinate conversion**

Append to `BoxMaxxingFinalTests/SkeletonOverlayTests.swift` inside the class:

```swift
    // MARK: - Coordinate conversion

    func test_toScreen_visionOriginBottomLeft_mapsToScreenBottomLeft() {
        // Vision (0,0) = bottom-left → screen bottom-left = (0, height)
        let result = SkeletonOverlayView.toScreen(CGPoint(x: 0, y: 0), size: CGSize(width: 100, height: 200))
        XCTAssertEqual(result, CGPoint(x: 0, y: 200))
    }

    func test_toScreen_visionTopRight_mapsToScreenTopRight() {
        // Vision (1,1) = top-right → screen top-right = (width, 0)
        let result = SkeletonOverlayView.toScreen(CGPoint(x: 1, y: 1), size: CGSize(width: 100, height: 200))
        XCTAssertEqual(result, CGPoint(x: 100, y: 0))
    }

    func test_toScreen_center_mapsToCenter() {
        let result = SkeletonOverlayView.toScreen(CGPoint(x: 0.5, y: 0.5), size: CGSize(width: 100, height: 200))
        XCTAssertEqual(result, CGPoint(x: 50, y: 100))
    }

    func test_toScreen_visionTopLeft_mapsToScreenTopLeft() {
        // Vision (0,1) = top-left → screen (0, 0)
        let result = SkeletonOverlayView.toScreen(CGPoint(x: 0, y: 1), size: CGSize(width: 100, height: 200))
        XCTAssertEqual(result, CGPoint(x: 0, y: 0))
    }
```

- [ ] **Step 2: Run — expect compile failure** (`SkeletonOverlayView` not found)

```bash
xcodebuild test -scheme BoxMaxxingFinal -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E "error:|FAILED|PASSED" | head -20
```

- [ ] **Step 3: Create `BoxMaxxingFinal/Views/SkeletonOverlayView.swift`**

First create the `Views` directory if it doesn't exist:
```bash
mkdir -p /Users/michael/Projects/BoxMaxxingFinal/BoxMaxxingFinal/Views
```

Then create the file:

```swift
import SwiftUI
import Vision

struct SkeletonOverlayView: View {
    let skeleton: SkeletonFrame?

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                guard let skeleton else { return }
                drawSkeleton(context: context, size: size, skeleton: skeleton)
            }
        }
        .blendMode(.screen)
        .allowsHitTesting(false)
    }

    // MARK: - Coordinate Conversion

    /// Converts Vision normalized coordinates (origin bottom-left) to screen coordinates (origin top-left).
    static func toScreen(_ point: CGPoint, size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: (1 - point.y) * size.height)
    }

    // MARK: - Drawing

    private func drawSkeleton(context: GraphicsContext, size: CGSize, skeleton: SkeletonFrame) {
        let bones: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] = [
            (.nose, .neck),
            (.neck, .leftShoulder),  (.neck, .rightShoulder),
            (.leftShoulder, .leftElbow),   (.leftElbow, .leftWrist),
            (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
            (.leftShoulder, .leftHip),     (.rightShoulder, .rightHip),
            (.leftHip, .rightHip),
            (.leftHip, .leftKnee),   (.leftKnee, .leftAnkle),
            (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
        ]

        let red = Color(UIColor.systemRed)

        for (nameA, nameB) in bones {
            guard let ptA = skeleton.joints[nameA],
                  let ptB = skeleton.joints[nameB] else { continue }

            let screenA = Self.toScreen(ptA, size: size)
            let screenB = Self.toScreen(ptB, size: size)

            var path = Path()
            path.move(to: screenA)
            path.addLine(to: screenB)

            // Pass 1: outer halo
            context.stroke(path, with: .color(red.opacity(0.15)),
                           style: StrokeStyle(lineWidth: 12, lineCap: .round))
            // Pass 2: inner glow
            context.stroke(path, with: .color(red.opacity(0.40)),
                           style: StrokeStyle(lineWidth: 6, lineCap: .round))
            // Pass 3: bright core line
            context.stroke(path, with: .color(.white.opacity(0.90)),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }

        // Joint dots
        for (_, pt) in skeleton.joints {
            let screen = Self.toScreen(pt, size: size)
            let outerRect = CGRect(x: screen.x - 5, y: screen.y - 5, width: 10, height: 10)
            let innerRect = CGRect(x: screen.x - 3, y: screen.y - 3, width: 6, height: 6)
            context.fill(Path(ellipseIn: outerRect), with: .color(red.opacity(0.30)))
            context.fill(Path(ellipseIn: innerRect), with: .color(.white.opacity(0.90)))
        }
    }
}
```

- [ ] **Step 4: Add the new file to the Xcode target**

Open `BoxMaxxingFinal.xcodeproj` in Xcode, right-click the `Views` folder → "Add Files to BoxMaxxingFinal" → select `SkeletonOverlayView.swift`, ensure "BoxMaxxingFinal" target is checked.

Alternatively via command line — edit `BoxMaxxingFinal.xcodeproj/project.pbxproj` to register the file. The easiest approach: open Xcode and drag the file into the project navigator under a `Views` group.

- [ ] **Step 5: Run tests — expect PASS**

```bash
xcodebuild test -scheme BoxMaxxingFinal -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E "error:|FAILED|PASSED" | head -20
```

Expected: all 6 tests pass.

- [ ] **Step 6: Commit**

```bash
git add BoxMaxxingFinal/Views/SkeletonOverlayView.swift BoxMaxxingFinalTests/SkeletonOverlayTests.swift
git commit -m "feat: add SkeletonOverlayView with 3-pass glow Canvas"
```

---

## Task 3: Add `extractSkeleton(from:)` to `VisionProcessor`

**Files:**
- Modify: `BoxMaxxingFinal/Services/VisionProcessor.swift`

> Note: `VNHumanBodyPoseObservation` cannot be easily instantiated in unit tests (it requires a real Vision pipeline). This method is tested via the live camera in Task 5's integration step.

- [ ] **Step 1: Add `extractSkeleton(from:)` to `VisionProcessor.swift`**

Open `BoxMaxxingFinal/Services/VisionProcessor.swift`. Add this method inside the `VisionProcessor` class, after `isBodyDetected`:

```swift
    /// Extracts normalized 2D joint positions from the first body pose observation.
    /// Returns nil if no observation exists or all joints fall below the confidence threshold.
    func extractSkeleton(from observations: [VNHumanBodyPoseObservation]?) -> SkeletonFrame? {
        guard let observation = observations?.first else { return nil }

        let allJointNames: [VNHumanBodyPoseObservation.JointName] = [
            .nose, .neck,
            .leftShoulder, .rightShoulder,
            .leftElbow, .rightElbow,
            .leftWrist, .rightWrist,
            .leftHip, .rightHip,
            .leftKnee, .rightKnee,
            .leftAnkle, .rightAnkle,
            .leftEye, .rightEye,
            .leftEar, .rightEar,
            .root
        ]

        var joints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        var confidence: [VNHumanBodyPoseObservation.JointName: Float] = [:]

        for name in allJointNames {
            guard let point = try? observation.recognizedPoint(name),
                  point.confidence > 0.3 else { continue }
            joints[name] = CGPoint(x: point.location.x, y: point.location.y)
            confidence[name] = point.confidence
        }

        guard !joints.isEmpty else { return nil }
        return SkeletonFrame(joints: joints, confidence: confidence)
    }
```

- [ ] **Step 2: Build to confirm no compile errors**

```bash
xcodebuild build -scheme BoxMaxxingFinal -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add BoxMaxxingFinal/Services/VisionProcessor.swift
git commit -m "feat: add extractSkeleton(from:) to VisionProcessor"
```

---

## Task 4: Publish `currentSkeleton` from `SessionManager`

**Files:**
- Modify: `BoxMaxxingFinal/Services/SessionManager.swift`

- [ ] **Step 1: Add `@Published var currentSkeleton` property**

In `SessionManager.swift`, in the `// MARK: - Published State` section, add after the existing `@Published` properties:

```swift
    @Published var currentSkeleton: SkeletonFrame?
```

- [ ] **Step 2: Update `processFrame` to extract and publish the skeleton**

Find `func processFrame(_ pixelBuffer: CVPixelBuffer)`. Replace the entire method with:

```swift
    func processFrame(_ pixelBuffer: CVPixelBuffer) {
        guard isRecording else { return }

        visionProcessor.detectBodyPose(from: pixelBuffer) { [weak self] observations in
            guard let self else { return }
            let prediction = self.mlEngine.predictMove(from: observations)
            let skeleton = self.visionProcessor.extractSkeleton(from: observations)
            DispatchQueue.main.async {
                guard self.isRecording else { return }
                self.currentSkeleton = skeleton
                self.currentFramePredictions.append(prediction)
                self.updateLivePunchIfNeeded(prediction: prediction)
            }
        }
    }
```

- [ ] **Step 3: Clear `currentSkeleton` when session ends**

In `finalizeSession()`, find the line `isRecording = false` and add the clear immediately after:

```swift
        isRecording = false     // RecordingView: phase switches to .done (ReviewingOverlay)
        currentSkeleton = nil
        isAnalyzing = true
```

- [ ] **Step 4: Build and run tests**

```bash
xcodebuild test -scheme BoxMaxxingFinal -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E "error:|FAILED|PASSED" | head -20
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add BoxMaxxingFinal/Services/SessionManager.swift
git commit -m "feat: publish currentSkeleton from SessionManager"
```

---

## Task 5: Wire `SkeletonOverlayView` into `RecordingView`

**Files:**
- Modify: `BoxMaxxingFinal/RecordingView.swift`

- [ ] **Step 1: Add `SkeletonOverlayView` to the ZStack**

In `RecordingView.swift`, find the `body` property's `ZStack`. It currently reads:

```swift
ZStack {
    CameraPreviewView(onFrame: { [sessionManager] buffer in
        sessionManager.processFrame(buffer)
    })
    .ignoresSafeArea()

    // Vignette overlay
    LinearGradient(
```

Insert the skeleton overlay between the camera preview and the vignette — **after** `.ignoresSafeArea()` and **before** the `// Vignette overlay` comment:

```swift
    CameraPreviewView(onFrame: { [sessionManager] buffer in
        sessionManager.processFrame(buffer)
    })
    .ignoresSafeArea()

    if phase == .recording {
        SkeletonOverlayView(skeleton: sessionManager.currentSkeleton)
            .ignoresSafeArea()
    }

    // Vignette overlay
    LinearGradient(
```

- [ ] **Step 2: Build — confirm no compile errors**

```bash
xcodebuild build -scheme BoxMaxxingFinal -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Run on device or simulator and verify visually**

Launch the app on a physical device or simulator with camera access:
1. Tap a combo → tap "I'm Ready" → wait for countdown
2. Stand in front of the camera so your full body is visible
3. During the `.recording` phase, confirm:
   - Glowing red/white skeleton lines appear over your body
   - Skeleton updates in real time as you move
   - Skeleton is absent during `.hint` and `.countdown` phases
   - Skeleton disappears when session ends (ReviewingOverlay appears)
4. Punch — confirm skeleton tracks arm extension

- [ ] **Step 4: Commit**

```bash
git add BoxMaxxingFinal/RecordingView.swift
git commit -m "feat: layer SkeletonOverlayView on camera feed during recording"
```

---

## Self-Review

**Spec coverage check:**
- ✅ Full body skeleton (19 joints via `VNDetectHumanBodyPoseRequest`) — Task 3
- ✅ Glowing red/white aesthetic — Task 2 (3-pass Canvas render)
- ✅ `.screen` blend mode — Task 2
- ✅ Always visible when body detected — Task 2 (no fade logic)
- ✅ `SkeletonFrame` model — Task 1
- ✅ Only during `.recording` phase — Task 5
- ✅ Joints below 0.3 confidence skipped — Task 3
- ✅ Coordinate flip (Vision bottom-left → screen top-left) — Task 2, tested in Task 2

**Type consistency:**
- `SkeletonFrame` defined in Task 1, used in Tasks 2, 3, 4 — consistent
- `extractSkeleton(from:)` defined in Task 3, called in Task 4 — consistent
- `currentSkeleton: SkeletonFrame?` defined in Task 4, read in Task 5 — consistent
- `SkeletonOverlayView.toScreen(_:size:)` defined and tested in Task 2 — consistent

**Placeholder scan:** None found.
