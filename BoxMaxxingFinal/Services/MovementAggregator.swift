import Foundation

// MARK: - Frame Prediction

struct FramePrediction {
    let label: String       // move id or "no_body_detected" / "no_movement_detected"
    let confidence: Float   // 0.0 - 1.0
}

// MARK: - Movement Aggregator

struct MovementAggregator {

    // Valid move IDs matching allMoves in Models.swift
    private static let validMoveIds: Set<String> = ["lj", "rj", "lh", "rh", "lu", "ru"]

    // Called at T=3s with all collected frame predictions from a single window.
    // Returns majority-vote label + average confidence of winning label's frames.
    func aggregate(predictions: [FramePrediction]) -> (label: String, confidence: Float) {
        guard !predictions.isEmpty else {
            return ("no_movement_detected", 0.0)
        }

        // Step 1: Count votes per label
        let labelCounts = Dictionary(grouping: predictions, by: { $0.label })
            .mapValues { $0.count }

        // Step 2: Dominant label by majority vote
        guard let dominantEntry = labelCounts.max(by: { $0.value < $1.value }) else {
            return ("no_movement_detected", 0.0)
        }

        let dominantLabel = dominantEntry.key

        // Step 3: Map any unknown/invalid label to no_movement_detected
        let finalLabel: String
        if Self.validMoveIds.contains(dominantLabel) {
            finalLabel = dominantLabel
        } else if dominantLabel == "no_body_detected" {
            finalLabel = "no_body_detected"
        } else {
            finalLabel = "no_movement_detected"
        }

        // Step 4: Average confidence of all frames that voted for the winning label
        let dominantFrames = predictions.filter { $0.label == dominantLabel }
        let avgConfidence = dominantFrames.map { $0.confidence }.reduce(0, +) / Float(dominantFrames.count)

        return (finalLabel, avgConfidence)
    }
}
