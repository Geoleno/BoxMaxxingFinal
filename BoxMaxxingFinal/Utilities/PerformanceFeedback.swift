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

// MARK: - Form Cues

struct FormCue { let title: String; let detail: String }

func formCues(for kind: Move.MoveKind) -> [FormCue] {
    switch kind {
    case .jab:
        return [
            FormCue(title: "Full extension",  detail: "Extend your arm completely and snap the wrist on impact — a half-extended jab loses both speed and power."),
            FormCue(title: "Chin down",        detail: "Keep your chin tucked behind your lead shoulder throughout the punch to protect your jaw."),
            FormCue(title: "Quick retraction", detail: "Pull the fist back along the exact same line it traveled out — this resets your guard and sets up the next punch."),
        ]
    case .hook:
        return [
            FormCue(title: "Pivot the lead foot", detail: "Rotate on the ball of your foot as you throw — hip rotation is the main power source for the hook."),
            FormCue(title: "Elbow parallel",      detail: "Keep the elbow at shoulder height and parallel to the floor. High or low elbows telegraph the punch and reduce power."),
            FormCue(title: "Rear hand stays up",  detail: "Keep the rear glove high on your cheek while the lead arm swings — don't leave your head exposed."),
        ]
    case .uppercut:
        return [
            FormCue(title: "Dip the shoulder first", detail: "Lower your same-side shoulder slightly before driving up — this loads the punch and hides the tell."),
            FormCue(title: "Drive with the legs",    detail: "Push through the floor and extend the knees. Power comes from the ground up, not from the arm alone."),
            FormCue(title: "Tight elbow path",       detail: "Keep the elbow close to your body as the fist rises — a wide elbow wastes energy and exposes your ribs."),
        ]
    }
}
