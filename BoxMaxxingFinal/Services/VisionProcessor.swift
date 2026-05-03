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
}
