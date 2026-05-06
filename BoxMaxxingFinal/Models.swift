import Foundation
import CoreMedia
import Vision

// MARK: - Move

struct Move: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let short: String
    let kind: MoveKind
    let side: MoveSide

    enum MoveKind { case jab, hook, uppercut }
    enum MoveSide { case left, right }
}

// MARK: - Frame Prediction

struct FramePrediction {
    let label: String
    let confidence: Float
}

// MARK: - Combo

struct Combo: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let moveIds: [String]
}

// MARK: - Wrong Movement

struct WrongMovement: Identifiable {
    let id = UUID()
    let timestamp: CMTime
    let expectedMove: Move
    let detectedMoveId: String
    let confidence: Float

    var isWrongTechnique: Bool { detectedMoveId != expectedMove.id }
}

// MARK: - Live Punch (for recording HUD)

struct LivePunch: Identifiable {
    let id = UUID()
    let move: Move
    let confidence: Double
    let timestamp: Date
}

// MARK: - Skeleton Frame (for live overlay)

struct SkeletonFrame {
    let joints: [VNHumanBodyPoseObservation.JointName: CGPoint]
    let confidence: [VNHumanBodyPoseObservation.JointName: Float]
}

// MARK: - Session State

struct SessionState {
    var selectedComboId: String? = nil
    var selectedMoveIds: [String] = []
    var sessionLength: Int = 2
}

// MARK: - Static Data

let allMoves: [Move] = [
    Move(id: "lj", name: "Left Jab",       short: "LJ", kind: .jab,      side: .left),
    Move(id: "rj", name: "Right Jab",      short: "RJ", kind: .jab,      side: .right),
    Move(id: "lh", name: "Left Hook",      short: "LH", kind: .hook,     side: .left),
    Move(id: "rh", name: "Right Hook",     short: "RH", kind: .hook,     side: .right),
    Move(id: "lu", name: "Left Uppercut",  short: "LU", kind: .uppercut, side: .left),
    Move(id: "ru", name: "Right Uppercut", short: "RU", kind: .uppercut, side: .right),
]

let allCombos: [Combo] = [
    Combo(id: "c1", name: "The 1-2",        subtitle: "Jab · Cross",         moveIds: ["lj", "rj"]),
    Combo(id: "c2", name: "Jab Cross Hook", subtitle: "Classic combination", moveIds: ["lj", "rj", "lh"]),
    Combo(id: "c3", name: "Body to Head",   subtitle: "Mix elevations",      moveIds: ["lj", "lu", "rh"]),
    Combo(id: "c4", name: "Power Finisher", subtitle: "High impact",         moveIds: ["rj", "lh", "ru"]),
]

func findMove(_ id: String) -> Move? {
    allMoves.first { $0.id == id }
}

func formatTime(_ seconds: Int) -> String {
    String(format: "%02d:%02d", seconds / 60, seconds % 60)
}

// MARK: - Demo Data

/// Generates 10 dummy wrong movements across a 2-minute session for demo/presentation.
/// Red = wrong technique (detected different move). Yellow = bad execution (right move, low confidence).
func generateDemoWrongMovements() -> [WrongMovement] {
    let lj = findMove("lj")!
    let rj = findMove("rj")!

    // Timestamps match the 3-second combo window rhythm across 2 minutes
    let entries: [(secs: Int, expectedId: String, detectedId: String, conf: Float)] = [
        (3,   "lj", "rj",  Float.random(in: 0.72...0.92)),  // red  — wrong side
        (9,   "rj", "rj",  Float.random(in: 0.42...0.68)),  // yellow — weak execution
        (18,  "lj", "lj",  Float.random(in: 0.50...0.72)),  // yellow — low confidence
        (30,  "rj", "lj",  Float.random(in: 0.75...0.90)),  // red  — wrong side
        (45,  "lj", "lj",  Float.random(in: 0.38...0.62)),  // yellow — very low confidence
        (60,  "rj", "rj",  Float.random(in: 0.48...0.70)),  // yellow
        (78,  "lj", "rj",  Float.random(in: 0.68...0.88)),  // red
        (93,  "rj", "lj",  Float.random(in: 0.70...0.85)),  // red
        (108, "lj", "lj",  Float.random(in: 0.44...0.66)),  // yellow
        (117, "rj", "rj",  Float.random(in: 0.40...0.60)),  // yellow
    ]

    return entries.map { entry in
        let expected = entry.expectedId == "lj" ? lj : rj
        return WrongMovement(
            timestamp:      CMTime(seconds: Double(entry.secs), preferredTimescale: 600),
            expectedMove:   expected,
            detectedMoveId: entry.detectedId,
            confidence:     entry.conf
        )
    }
}
