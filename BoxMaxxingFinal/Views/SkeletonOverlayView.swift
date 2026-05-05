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
