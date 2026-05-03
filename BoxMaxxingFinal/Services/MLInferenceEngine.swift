import Vision
import CoreML

// MARK: - ML Inference Engine
// PLACEHOLDER — Team to integrate CoreML action classifier model.

final class MLInferenceEngine {

    // TODO: Replace with actual CoreML model instance
    // private var model: YourActionClassifier?

    func loadModel() {
        // TODO: Load YourActionClassifier.mlmodel
        // do {
        //     let config = MLModelConfiguration()
        //     model = try YourActionClassifier(configuration: config)
        // } catch {
        //     print("MLInferenceEngine: Failed to load model — \(error)")
        // }
    }

    // Returns a FramePrediction for each camera frame.
    // `observations` is nil when Vision detected no body in the frame.
    func predictMove(from observations: [VNHumanBodyPoseObservation]?) -> FramePrediction {
        guard let observations, !observations.isEmpty else {
            // Vision found no body — treat as no body detected
            return FramePrediction(label: "no_body_detected", confidence: 0.0)
        }

        // TODO: Convert VNHumanBodyPoseObservation array to model input format
        // TODO: Run inference using model
        // TODO: Extract predicted class label and confidence from model output
        //
        // Expected model output labels: "lj", "rj", "lh", "rh", "lu", "ru"
        // (matching Move.id values in Models.swift)
        //
        // Example (replace with real model call):
        // let input = buildModelInput(from: observations)
        // let output = try? model?.prediction(input: input)
        // return FramePrediction(label: output?.label ?? "no_movement_detected",
        //                        confidence: output?.confidence ?? 0.0)

        // PLACEHOLDER: returns no_movement_detected until model is integrated
        return FramePrediction(label: "no_movement_detected", confidence: 0.0)
    }
}
