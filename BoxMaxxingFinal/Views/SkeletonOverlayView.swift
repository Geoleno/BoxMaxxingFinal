import SwiftUI
import Vision

struct SkeletonOverlayView: View {
    let skeleton: SkeletonFrame?

    var body: some View {
        Canvas { context, size in
            guard let skeleton else { return }
            drawSkeleton(context: context, size: size, skeleton: skeleton)
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
