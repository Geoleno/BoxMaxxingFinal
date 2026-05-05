import Vision
import CoreML

// MARK: - ML Inference Engine
// PLACEHOLDER — Team to integrate CoreML action classifier model.

final class MLInferenceEngine {
    private var model: MLModel?

    func loadModel() {
        do {
            guard let url = Bundle.main.url(forResource: "80 epoch", withExtension: "mlmodel") else {
                print("MLInferenceEngine: Model file not found in bundle")
                return
            }
            let config = MLModelConfiguration()
            model = try MLModel(contentsOf: url, configuration: config)
        } catch {
            print("MLInferenceEngine: Failed to load model — \(error)")
        }
    }

    // Returns a FramePrediction for each camera frame.
    // `observations` is nil when Vision detected no body in the frame.
    func predictMove(from observations: [VNHumanBodyPoseObservation]?) -> FramePrediction {
        guard let observations, !observations.isEmpty else {
            return FramePrediction(label: "no_body_detected", confidence: 0.0)
        }

        guard let model else {
            return FramePrediction(label: "model_not_loaded", confidence: 0.0)
        }

        // TODO: Convert VNHumanBodyPoseObservation array to model input format
        // TODO: Run inference using model.prediction()
        // TODO: Extract predicted class label and confidence from model output
        //
        // Expected model output labels: "lj", "rj", "lh", "rh", "lu", "ru"
        // (matching Move.id values in Models.swift)

        return FramePrediction(label: "no_movement_detected", confidence: 0.0)
    }
}
