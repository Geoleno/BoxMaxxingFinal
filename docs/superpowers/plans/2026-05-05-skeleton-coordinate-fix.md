# Skeleton Overlay Coordinate Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix skeleton joints appearing in wrong screen positions by (1) delivering portrait-oriented pixel buffers to Vision and (2) compensating for `resizeAspectFill` cropping in the coordinate transform.

**Architecture:** Two root causes are fixed in sequence. First, `CameraView` sets `videoOrientation = .portrait` on the `AVCaptureVideoDataOutput` connection so iOS physically rotates pixel buffers before Vision sees them — Vision then returns portrait-space joint coordinates directly. Second, `SessionManager` publishes the pixel buffer dimensions; `SkeletonOverlayView.toScreen` uses them to compute how much `resizeAspectFill` crops the video frame and maps joint coordinates through that crop, eliminating the systematic offset at body edges.

**Tech Stack:** `AVCaptureConnection.videoOrientation`, `CVPixelBufferGetWidth/Height`, `CGFloat` arithmetic for aspect-ratio crop math, SwiftUI `Canvas`

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `BoxMaxxingFinal/RecordingView.swift` | Set `videoOrientation = .portrait` on connection + update `SkeletonOverlayView` call site |
| Modify | `BoxMaxxingFinal/Services/SessionManager.swift` | Publish `videoBufferSize`, read from pixel buffer in `processFrame` |
| Modify | `BoxMaxxingFinal/Views/SkeletonOverlayView.swift` | Add `bufferSize` param, update `toScreen` with crop math |
| Modify | `BoxMaxxingFinalTests/SkeletonOverlayTests.swift` | Update 4 existing `toScreen` tests + add 2 crop tests |

---

## Task 1: Set portrait orientation on the video output connection

**Files:**
- Modify: `BoxMaxxingFinal/RecordingView.swift` — `CameraView.startSession()`, lines 176–180

> No unit test is possible here — this is a camera hardware integration point. Verification is by build success and live device testing in Task 3.

- [ ] **Step 1: Locate the exact insertion point**

In `BoxMaxxingFinal/RecordingView.swift`, find this block inside `CameraView.startSession()`:

```swift
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }

        // Movie file output for full-session recording (added once, used by SessionRecorder)
        let movieOutput = SessionRecorder.shared.movieFileOutput
```

- [ ] **Step 2: Add the orientation fix immediately after the videoOutput is added**

Replace that block with:

```swift
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }

        // Rotate pixel buffers to portrait so Vision receives portrait-space coordinates.
        // Without this, the sensor delivers landscape buffers and joint x/y axes are swapped.
        if let connection = videoOutput.connection(with: .video),
           connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }

        // Movie file output for full-session recording (added once, used by SessionRecorder)
        let movieOutput = SessionRecorder.shared.movieFileOutput
```

- [ ] **Step 3: Build to confirm no compile errors**

```bash
xcodebuild build -scheme BoxMaxxingFinal -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add BoxMaxxingFinal/RecordingView.swift
git commit -m "fix: set videoOrientation=portrait on AVCaptureVideoDataOutput connection"
```

---

## Task 2: Publish pixel buffer dimensions from SessionManager

**Files:**
- Modify: `BoxMaxxingFinal/Services/SessionManager.swift`

> No unit test — `CVPixelBufferGetWidth/Height` is a Metal/hardware query with no testable pure-logic path. Verified via build + live device.

- [ ] **Step 1: Add `@Published var videoBufferSize` to the Published State section**

In `SessionManager.swift`, find the `// MARK: - Published State` section. After `@Published var currentSkeleton: SkeletonFrame?` (line 17), add:

```swift
    @Published var videoBufferSize: CGSize = CGSize(width: 1080, height: 1920)
```

The default `(1080, 1920)` is the typical `.high` preset front-camera portrait output — the real value overwrites it on the first frame.

- [ ] **Step 2: Update `processFrame` to read buffer dimensions**

Find `func processFrame(_ pixelBuffer: CVPixelBuffer)`. Replace the entire method with:

```swift
    func processFrame(_ pixelBuffer: CVPixelBuffer) {
        guard isRecording else { return }

        // Read dimensions on the camera thread (safe for CVPixelBuffer metadata queries)
        let bufferWidth = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let bufferHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))

        visionProcessor.detectBodyPose(from: pixelBuffer) { [weak self] observations in
            guard let self else { return }
            let prediction = self.mlEngine.predictMove(from: observations)
            let skeleton = self.visionProcessor.extractSkeleton(from: observations)
            DispatchQueue.main.async {
                guard self.isRecording else { return }
                self.videoBufferSize = CGSize(width: bufferWidth, height: bufferHeight)
                self.currentSkeleton = skeleton
                self.currentFramePredictions.append(prediction)
                self.updateLivePunchIfNeeded(prediction: prediction)
            }
        }
    }
```

- [ ] **Step 3: Build and run all tests**

```bash
xcodebuild test -scheme BoxMaxxingFinal -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|FAILED|PASSED|TEST SUCCEEDED|BUILD FAILED" | head -20
```

Expected: `TEST SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add BoxMaxxingFinal/Services/SessionManager.swift
git commit -m "feat: publish videoBufferSize from SessionManager for skeleton coordinate mapping"
```

---

## Task 3: Fix `toScreen` with crop compensation and update call sites + tests

**Files:**
- Modify: `BoxMaxxingFinal/Views/SkeletonOverlayView.swift`
- Modify: `BoxMaxxingFinal/RecordingView.swift` — `SkeletonOverlayView` call site
- Modify: `BoxMaxxingFinalTests/SkeletonOverlayTests.swift`

- [ ] **Step 1: Update the 4 existing `toScreen` tests and add 2 crop tests**

Replace the entire `// MARK: - Coordinate conversion` section in `BoxMaxxingFinalTests/SkeletonOverlayTests.swift` with:

```swift
    // MARK: - Coordinate conversion

    // When bufferSize == canvasSize there is no crop, so behaviour matches the simple mirror+flip.

    func test_toScreen_noCrop_bottomLeftMapsToBottomRight() {
        // Vision (0,0) = bottom-left; x mirrored for front camera → screen bottom-right
        let result = SkeletonOverlayView.toScreen(
            CGPoint(x: 0, y: 0),
            canvasSize: CGSize(width: 100, height: 200),
            bufferSize: CGSize(width: 100, height: 200)
        )
        XCTAssertEqual(result, CGPoint(x: 100, y: 200))
    }

    func test_toScreen_noCrop_topRightMapsToTopLeft() {
        // Vision (1,1) = top-right; x mirrored → screen top-left
        let result = SkeletonOverlayView.toScreen(
            CGPoint(x: 1, y: 1),
            canvasSize: CGSize(width: 100, height: 200),
            bufferSize: CGSize(width: 100, height: 200)
        )
        XCTAssertEqual(result, CGPoint(x: 0, y: 0))
    }

    func test_toScreen_noCrop_centerMapsToCenter() {
        // Center is symmetric — mirror and crop do not shift x=0.5, y=0.5
        let result = SkeletonOverlayView.toScreen(
            CGPoint(x: 0.5, y: 0.5),
            canvasSize: CGSize(width: 100, height: 200),
            bufferSize: CGSize(width: 100, height: 200)
        )
        XCTAssertEqual(result, CGPoint(x: 50, y: 100))
    }

    func test_toScreen_noCrop_topLeftMapsToTopRight() {
        // Vision (0,1) = top-left; x mirrored → screen top-right
        let result = SkeletonOverlayView.toScreen(
            CGPoint(x: 0, y: 1),
            canvasSize: CGSize(width: 100, height: 200),
            bufferSize: CGSize(width: 100, height: 200)
        )
        XCTAssertEqual(result, CGPoint(x: 100, y: 0))
    }

    // Crop tests: buffer 2× wider than canvas → 25% cropped from each x side.

    func test_toScreen_withCrop_centerStaysCenter() {
        // Buffer 200×100, canvas 100×100 → cropX = 0.25, cropY = 0
        // Center (0.5, 0.5) is symmetric → stays at screen center (50, 50)
        let result = SkeletonOverlayView.toScreen(
            CGPoint(x: 0.5, y: 0.5),
            canvasSize: CGSize(width: 100, height: 100),
            bufferSize: CGSize(width: 200, height: 100)
        )
        XCTAssertEqual(result.x, 50, accuracy: 0.5)
        XCTAssertEqual(result.y, 50, accuracy: 0.5)
    }

    func test_toScreen_withCrop_visibleEdgeMapsToScreenEdge() {
        // Buffer 200×100, canvas 100×100 → cropX = 0.25
        // Vision x=0.25 is the left boundary of what's visible in the un-mirrored buffer.
        // After mirror (1-0.25=0.75) that boundary maps to screen x=100 (right edge).
        let result = SkeletonOverlayView.toScreen(
            CGPoint(x: 0.25, y: 0.5),
            canvasSize: CGSize(width: 100, height: 100),
            bufferSize: CGSize(width: 200, height: 100)
        )
        XCTAssertEqual(result.x, 100, accuracy: 0.5)
        XCTAssertEqual(result.y, 50, accuracy: 0.5)
    }
```

- [ ] **Step 2: Run tests — expect compile failure** (`toScreen` signature doesn't match yet)

```bash
xcodebuild build -scheme BoxMaxxingFinal -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head -10
```

Expected: `BUILD FAILED` with "extra argument" or "missing argument" errors on `toScreen` calls.

- [ ] **Step 3: Update `SkeletonOverlayView.swift` with new signature and crop math**

Replace the entire file content with:

```swift
import SwiftUI
import Vision

struct SkeletonOverlayView: View {
    let skeleton: SkeletonFrame?
    let bufferSize: CGSize

    var body: some View {
        Canvas { context, size in
            guard let skeleton else { return }
            drawSkeleton(context: context, size: size, skeleton: skeleton)
        }
        .blendMode(.screen)
        .allowsHitTesting(false)
    }

    // MARK: - Coordinate Conversion

    /// Maps a Vision normalized joint position to a screen point.
    ///
    /// Vision origin is bottom-left (y increases upward). The front-camera preview is
    /// horizontally mirrored. `resizeAspectFill` scales the buffer to fill the canvas,
    /// cropping the overflowing edges — this function compensates for that crop.
    ///
    /// - Parameters:
    ///   - point: Normalized Vision joint position (x,y ∈ [0,1], origin bottom-left).
    ///   - canvasSize: Size of the SwiftUI Canvas (== screen size with ignoresSafeArea).
    ///   - bufferSize: Actual pixel buffer dimensions as delivered by AVCaptureVideoDataOutput
    ///                 after portrait rotation (width = shorter dimension, height = taller).
    static func toScreen(_ point: CGPoint, canvasSize: CGSize, bufferSize: CGSize) -> CGPoint {
        // resizeAspectFill: scale so both buffer dimensions are >= canvas dimensions.
        let scaleX = canvasSize.width / bufferSize.width
        let scaleY = canvasSize.height / bufferSize.height
        let scale = max(scaleX, scaleY)

        // Fraction of the buffer that is cropped from each side.
        let cropX = max(0, (bufferSize.width * scale - canvasSize.width) / 2 / (bufferSize.width * scale))
        let cropY = max(0, (bufferSize.height * scale - canvasSize.height) / 2 / (bufferSize.height * scale))

        // Mirror x for the front camera (preview is mirrored; pixel buffers are not).
        let mirroredX = 1 - point.x

        // Map through crop: only the range [crop, 1-crop] is visible on screen.
        let screenX = (mirroredX - cropX) / (1 - 2 * cropX) * canvasSize.width
        let screenY = ((1 - point.y) - cropY) / (1 - 2 * cropY) * canvasSize.height

        return CGPoint(x: screenX, y: screenY)
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

            let screenA = Self.toScreen(ptA, canvasSize: size, bufferSize: bufferSize)
            let screenB = Self.toScreen(ptB, canvasSize: size, bufferSize: bufferSize)

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
            let screen = Self.toScreen(pt, canvasSize: size, bufferSize: bufferSize)
            let outerRect = CGRect(x: screen.x - 5, y: screen.y - 5, width: 10, height: 10)
            let innerRect = CGRect(x: screen.x - 3, y: screen.y - 3, width: 6, height: 6)
            context.fill(Path(ellipseIn: outerRect), with: .color(red.opacity(0.30)))
            context.fill(Path(ellipseIn: innerRect), with: .color(.white.opacity(0.90)))
        }
    }
}
```

- [ ] **Step 4: Update the `SkeletonOverlayView` call site in `RecordingView.swift`**

Find:
```swift
    if phase == .recording {
        SkeletonOverlayView(skeleton: sessionManager.currentSkeleton)
            .ignoresSafeArea()
    }
```

Replace with:
```swift
    if phase == .recording {
        SkeletonOverlayView(
            skeleton: sessionManager.currentSkeleton,
            bufferSize: sessionManager.videoBufferSize
        )
        .ignoresSafeArea()
    }
```

- [ ] **Step 5: Run all tests — expect PASS**

```bash
xcodebuild test -scheme BoxMaxxingFinal -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|FAILED|PASSED|TEST SUCCEEDED|BUILD FAILED" | head -20
```

Expected: `TEST SUCCEEDED` — all 22 tests pass (2 model + 6 coordinate + existing suites).

- [ ] **Step 6: Commit**

```bash
git add BoxMaxxingFinal/Views/SkeletonOverlayView.swift BoxMaxxingFinal/RecordingView.swift BoxMaxxingFinalTests/SkeletonOverlayTests.swift
git commit -m "fix: compensate for resizeAspectFill crop in skeleton toScreen coordinate mapping"
```

---

## Self-Review

**Spec coverage check:**
- ✅ Root cause 1 (landscape pixel buffers → Vision rotation) — Task 1: `videoOrientation = .portrait` on connection
- ✅ Root cause 2 (`resizeAspectFill` crop not compensated) — Task 3: crop math in `toScreen`
- ✅ Buffer dimensions flow to `toScreen` — Task 2: `videoBufferSize` published from `SessionManager`
- ✅ `toScreen` signature update propagated to call sites — Task 3: `RecordingView` call site updated
- ✅ Tests updated for new signature — Task 3: 4 existing + 2 new crop tests

**Placeholder scan:** None.

**Type consistency:**
- `videoBufferSize: CGSize` defined in Task 2, read in Task 3 at call site — consistent
- `toScreen(_ point: CGPoint, canvasSize: CGSize, bufferSize: CGSize)` defined in Task 3, tested in Task 3 — consistent
- All internal `toScreen` calls inside `drawSkeleton` updated in same Task 3 — consistent
