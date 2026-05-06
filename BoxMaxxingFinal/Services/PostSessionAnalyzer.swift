import AVFoundation
import Vision
import Foundation

// MARK: - Future scaffolding
// PostSessionAnalyzer is not called anywhere in the live recording path.
// analyze() is a stub reserved for an optional offline re-analysis pass.
// groupWindows() and selectRepresentative() are tested utilities kept for that future use.

struct WindowPrediction: Equatable {
    let label: String
    let confidence: Float
    let startTime: Double
    let endTime: Double
}

final class PostSessionAnalyzer {

    static let shared = PostSessionAnalyzer()
    private init() {}

    let clipPaddingSeconds: Double = 0.5
    let windowSize = 60
    let strideSize  = 15

    func analyze(videoURL: URL) async -> [WrongMovement] {
        return []
    }

    func groupWindows(_ predictions: [WindowPrediction]) -> [[WindowPrediction]] {
        var groups: [[WindowPrediction]] = []
        var current: [WindowPrediction] = []

        for prediction in predictions {
            if current.isEmpty {
                current.append(prediction)
            } else if let last = current.last,
                      last.label == prediction.label,
                      (prediction.startTime - last.endTime) < 0.5 {
                current.append(prediction)
            } else {
                groups.append(current)
                current = [prediction]
            }
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }

    func selectRepresentative(from group: [WindowPrediction]) -> WindowPrediction {
        group.max(by: { $0.confidence < $1.confidence })!
    }
}
