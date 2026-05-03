import Foundation

// MARK: - Performance Feedback

enum PerformanceFeedback {

    // Keyed by Move.id ("lj", "rj", "lh", "rh", "lu", "ru")
    private static let moveSuggestions: [String: String] = [
        "lj": "Keep your shoulder back. Extend your arm fully with speed. Return quickly to guard.",
        "rj": "Drive from your hips. Keep your rear hand powered. Maintain balance throughout.",
        "lh": "Rotate your hips. Keep your elbow high. Generate power from your torso.",
        "rh": "Similar to left hook, mirror the mechanics. Turn your shoulders fully.",
        "lu": "Bend your knees. Explode upward with your core. Keep your elbow tight.",
        "ru": "Mirror left uppercut. Maintain balance. Protect your face."
    ]

    static func suggestion(for moveId: String) -> String {
        moveSuggestions[moveId] ?? "Focus on proper form and technique for this movement."
    }

    static func feedback(for confidence: Float, moveId: String) -> String {
        let moveName = findMove(moveId)?.name ?? moveId
        let pct = confidence * 100
        if pct >= 85 {
            return "Great job! Your \(moveName) form is excellent. Keep it up!"
        } else if pct >= 50 {
            return "Your \(moveName) has room for improvement. Review the reference video and adjust your form."
        } else {
            return "Your \(moveName) needs significant improvement. Study the correct technique carefully."
        }
    }

    static func noScanFeedback() -> String {
        "Your body was not detected during this window. Ensure your full body is visible to the camera throughout the entire session."
    }

    static func noMovementFeedback() -> String {
        "No movement was detected during this window. Make sure you execute the move clearly and fully within the 3-second window."
    }
}
