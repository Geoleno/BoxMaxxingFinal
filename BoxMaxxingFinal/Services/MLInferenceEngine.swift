import Vision
import CoreML

final class MLInferenceEngine {

    // MARK: - Constants

    /// Fixed joint order — must match the order Create ML used during training.
    static let jointNames: [VNHumanBodyPoseObservation.JointName] = [
        .nose,
        .leftEye,  .rightEye,
        .leftEar,  .rightEar,
        .leftShoulder,  .rightShoulder,
        .leftElbow,     .rightElbow,
        .leftWrist,     .rightWrist,
        .leftHip,       .rightHip,
        .leftKnee,      .rightKnee,
        .leftAnkle,     .rightAnkle,
        .neck
    ]

    static let labelToMoveId: [String: String] = [
        "Jab":            "lj",
        "Straight":       "rj",
        "Left Hook":      "lh",
        "Right Hook":     "rh",
        "Left Uppercut":  "lu",
        "Right Uppercut": "ru",
    ]

    private static let windowSize = 60   // frames — matches model's Prediction Window Size

    // MARK: - State

    private var model: MLModel?
    // Rolling buffer: each entry is 54 floats — 18 joints × [x, y, confidence]
    private var frameBuffer: [[Float]] = []

    // MARK: - Setup

    func loadModel() {
        do {
            guard let url = Bundle.main.url(forResource: "80 epoch", withExtension: "mlmodel") else {
                print("MLInferenceEngine: Model file not found in bundle")
                return
            }
            model = try MLModel(contentsOf: url, configuration: MLModelConfiguration())
        } catch {
            print("MLInferenceEngine: Failed to load model — \(error)")
        }
    }

    func resetBuffer() {
        frameBuffer = []
    }

    // MARK: - Per-frame inference

    func predictMove(from observations: [VNHumanBodyPoseObservation]?) -> FramePrediction {
        guard let observations, !observations.isEmpty else {
            return FramePrediction(label: "no_body_detected", confidence: 0.0)
        }

        // Extract joint values from the highest-confidence observation (Vision sorts desc)
        let allPoints = (try? observations[0].recognizedPoints(.all)) ?? [:]
        var frameValues = [Float](repeating: 0, count: 54)  // 18 joints × 3
        for (i, name) in Self.jointNames.enumerated() {
            if let pt = allPoints[name] {
                frameValues[i * 3]     = Float(pt.location.x)
                frameValues[i * 3 + 1] = Float(pt.location.y)
                frameValues[i * 3 + 2] = Float(pt.confidence)
            }
            // missing joint stays (0, 0, 0)
        }

        // Slide buffer: append new frame, drop oldest when over window size
        frameBuffer.append(frameValues)
        if frameBuffer.count > Self.windowSize {
            frameBuffer.removeFirst()
        }

        // Need a full 60-frame window before running inference
        guard frameBuffer.count == Self.windowSize, let model else {
            return FramePrediction(label: "no_movement_detected", confidence: 0.0)
        }

        // Build MLMultiArray with shape [60, 3, 18]
        guard let multiArray = try? MLMultiArray(shape: [60, 3, 18] as [NSNumber], dataType: .float32) else {
            return FramePrediction(label: "no_movement_detected", confidence: 0.0)
        }
        for frameIdx in 0..<Self.windowSize {
            let frame = frameBuffer[frameIdx]
            for jointIdx in 0..<18 {
                let base = jointIdx * 3
                multiArray[[frameIdx, 0, jointIdx] as [NSNumber]] = NSNumber(value: frame[base])
                multiArray[[frameIdx, 1, jointIdx] as [NSNumber]] = NSNumber(value: frame[base + 1])
                multiArray[[frameIdx, 2, jointIdx] as [NSNumber]] = NSNumber(value: frame[base + 2])
            }
        }

        // Run inference
        guard let input  = try? MLDictionaryFeatureProvider(dictionary: ["poses": MLFeatureValue(multiArray: multiArray)]),
              let output = try? model.prediction(from: input) else {
            return FramePrediction(label: "no_movement_detected", confidence: 0.0)
        }

        let rawLabel   = output.featureValue(for: "label")?.stringValue ?? ""
        let probs      = output.featureValue(for: "labelProbabilities")?.dictionaryValue as? [String: NSNumber]
        let confidence = Float(probs?[rawLabel]?.doubleValue ?? 0)
        let moveId     = Self.labelToMoveId[rawLabel] ?? "no_movement_detected"

        return FramePrediction(label: moveId, confidence: confidence)
    }
}
