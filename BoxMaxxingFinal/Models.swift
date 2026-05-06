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

// MARK: - Window Result (for live HUD feedback)

struct WindowResult {
    let expectedMoveId: String
    let detectedMoveId: String?
    let confidence: Double
    let matched: Bool
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
