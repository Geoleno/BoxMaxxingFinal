import Vision
import CoreVideo

// MARK: - Vision Processor

final class VisionProcessor {

    // Detects human body pose from a pixel buffer and returns observations via completion.
    // Completion is called on a background queue.
    func detectBodyPose(
        from pixelBuffer: CVPixelBuffer,
        completion: @escaping ([VNHumanBodyPoseObservation]?) -> Void
    ) {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        DispatchQueue.global(qos: .userInteractive).async {
            do {
                try handler.perform([request])
                completion(request.results)
            } catch {
                completion(nil)
            }
        }
    }

    func isBodyDetected(_ observations: [VNHumanBodyPoseObservation]?) -> Bool {
        guard let observations, !observations.isEmpty else { return false }
        return true
    }

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
}
