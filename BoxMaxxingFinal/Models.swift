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
    var clipURL: URL? = nil  // pre-assigned clip for demo; nil uses full session video + seek

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

// MARK: - Session Statistics

struct SessionStatistics {
    let wrongTechniqueCount: Int
    let badExecutionCount: Int
    let avgConfidence: Int

    init(movements: [WrongMovement]) {
        wrongTechniqueCount = movements.filter { $0.isWrongTechnique }.count
        badExecutionCount   = movements.filter { !$0.isWrongTechnique }.count
        let sum = movements.reduce(0.0) { $0 + Double($1.confidence) }
        avgConfidence = movements.isEmpty ? 0 : Int(sum / Double(movements.count) * 100)
    }
}

// MARK: - Static Data

let allMoves: [Move] = [
    Move(id: "lj", name: "Jab",      short: "J",  kind: .jab, side: .left),
    Move(id: "rj", name: "Straight", short: "S",  kind: .jab, side: .right),
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

    // Clip pools — files live in BoxMaxxingFinal/Video/Test_Clip/ and must be added to the Xcode target.
    let jabClips      = ["Jab-1", "Jab-2", "Jab-3", "Jab-4"]
    let straightClips = ["Straight-1", "Straight-3", "Straight-5", "Straight-6"]

    func randomClip(for moveId: String) -> URL? {
        let pool = moveId == "lj" ? jabClips : straightClips
        guard let name = pool.randomElement() else { return nil }
        return Bundle.main.url(forResource: name, withExtension: "mp4")
    }

    // Timestamps match the 3-second combo window rhythm across 2 minutes.
    // Red (wrong technique): conf < 40% — detected a different punch entirely.
    // Yellow (bad execution): conf 50–79% — right punch, below the 80% quality threshold.
    let entries: [(secs: Int, expectedId: String, detectedId: String, conf: Float)] = [
        (3,   "lj", "rj",  Float.random(in: 0.18...0.38)),
        (9,   "rj", "rj",  Float.random(in: 0.52...0.72)),
        (18,  "lj", "lj",  Float.random(in: 0.55...0.75)),
        (30,  "rj", "lj",  Float.random(in: 0.20...0.36)),
        (45,  "lj", "lj",  Float.random(in: 0.50...0.70)),
        (60,  "rj", "rj",  Float.random(in: 0.53...0.73)),
        (78,  "lj", "rj",  Float.random(in: 0.15...0.35)),
        (93,  "rj", "lj",  Float.random(in: 0.22...0.38)),
        (108, "lj", "lj",  Float.random(in: 0.51...0.69)),
        (117, "rj", "rj",  Float.random(in: 0.54...0.74)),
    ]

    return entries.map { entry in
        let expected = entry.expectedId == "lj" ? lj : rj
        return WrongMovement(
            timestamp:      CMTime(seconds: Double(entry.secs), preferredTimescale: 600),
            expectedMove:   expected,
            detectedMoveId: entry.detectedId,
            confidence:     entry.conf,
            clipURL:        randomClip(for: entry.expectedId)
        )
    }
}
