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

    /// Extracts normalized 2D joint positions from the first body pose observation (Vision sorts by confidence desc,
    /// so index 0 is the best detection when multiple people are in frame).
    /// Joints with confidence ≤ 0.3 are excluded from the returned frame; if all joints
    /// fall below this threshold, returns nil.
    func extractSkeleton(from observations: [VNHumanBodyPoseObservation]?) -> SkeletonFrame? {
        guard let observation = observations?.first,
              let allPoints = try? observation.recognizedPoints(.all) else { return nil }

        let filtered = allPoints.filter { $0.value.confidence > 0.3 }
        guard !filtered.isEmpty else { return nil }

        return SkeletonFrame(
            joints: filtered.mapValues { $0.location },
            confidence: filtered.mapValues { $0.confidence }
        )
    }
}
