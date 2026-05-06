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
    let label: String       // move id or "no_body_detected" / "no_movement_detected"
    let confidence: Float   // 0.0 - 1.0
}

// MARK: - Combo

struct Combo: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let moveIds: [String]
}

// MARK: - Session Event

struct SessionEvent: Identifiable {
    let id: String
    let time: Int
    let move: Move
    let status: EventStatus
    let confidence: Double
    let detectedAs: String?
    let note: String
    let clipURL: URL?

    enum EventStatus { case wrong, unclear, correct }

    init(id: String, time: Int, move: Move, status: EventStatus,
         confidence: Double, detectedAs: String?, note: String, clipURL: URL? = nil) {
        self.id = id; self.time = time; self.move = move; self.status = status
        self.confidence = confidence; self.detectedAs = detectedAs
        self.note = note; self.clipURL = clipURL
    }
}

// MARK: - Session Event Extensions

extension SessionEvent {
    var confidencePercentage: Double { confidence * 100 }
    var hasClip: Bool { clipURL != nil }

    var movementState: MovementState {
        if let label = detectedAs {
            if label == "body not detected" { return .noScan }
            if label == "no movement"       { return .noMovement }
        }
        switch status {
        case .correct:
            return .excellent
        case .unclear:
            if confidence == 0 { return .noScan }
            return confidence * 100 >= 50 ? .fair : .poor
        case .wrong:
            return confidence * 100 >= 50 ? .fair : .poor
        }
    }
}

// MARK: - Live Punch (for recording HUD)

struct LivePunch: Identifiable {
    let id = UUID()
    let move: Move
    let confidence: Double
    let timestamp: Date
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

// MARK: - Window Result (for live HUD feedback)

struct WindowResult {
    let expectedMoveId: String
    let detectedMoveId: String?   // nil when no valid move detected
    let confidence: Double         // 0.0–1.0
    let matched: Bool              // detectedMoveId == expectedMoveId
}

// MARK: - Skeleton Frame (for live overlay)

struct SkeletonFrame {
    /// Normalized joint positions (x: 0–1, y: 0–1, Vision origin: bottom-left)
    let joints: [VNHumanBodyPoseObservation.JointName: CGPoint]
    /// Per-joint detection confidence (0.0–1.0)
    let confidence: [VNHumanBodyPoseObservation.JointName: Float]
}

// MARK: - Session State

struct SessionState {
    var selectedComboId: String? = nil
    var selectedMoveIds: [String] = []
    var sessionLength: Int = 2
}

// MARK: - Session State Extensions (computed stats over SessionStore events)

extension SessionState {
    var totalMovements: Int { SessionStore.shared.currentEvents.count }
    var accurateMovements: Int { SessionStore.shared.currentEvents.filter { $0.status == .correct }.count }
    var movementErrors: Int { SessionStore.shared.currentEvents.filter { $0.status != .correct }.count }

    var averageConfidence: Double {
        let events = SessionStore.shared.currentEvents
        guard !events.isEmpty else { return 0 }
        return events.map { $0.confidence }.reduce(0, +) / Double(events.count)
    }
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

func generateEvents(state: SessionState) -> [SessionEvent] {
    let total = state.sessionLength * 60
    guard !state.selectedMoveIds.isEmpty else { return [] }
    let count = Int.random(in: 5...8)
    var events: [SessionEvent] = []

    for i in 0..<count {
        let base = Double(i + 1) / Double(count + 1) * Double(total)
        let jitter = Double.random(in: -8...8)
        let t = max(2, min(total - 2, Int(base + jitter)))
        let moveId = state.selectedMoveIds.randomElement()!
        guard let move = findMove(moveId) else { continue }
        let conf = Double.random(in: 0.45...0.95)
        let status: SessionEvent.EventStatus = conf < 0.65 ? .unclear : (Bool.random() ? .wrong : .unclear)
        let detected: String?
        if status == .wrong, let idx = allMoves.firstIndex(where: { $0.id == moveId }) {
            detected = allMoves[(idx + 1) % allMoves.count].name
        } else {
            detected = nil
        }
        events.append(SessionEvent(
            id: "e\(i)",
            time: t,
            move: move,
            status: status,
            confidence: conf,
            detectedAs: detected,
            note: status == .wrong
                ? "Elbow flared — punch traveled outside the line"
                : "Form ambiguous — partial occlusion or fast motion"
        ))
    }
    return events.sorted { $0.time < $1.time }
}

func formatTime(_ seconds: Int) -> String {
    String(format: "%02d:%02d", seconds / 60, seconds % 60)
}
