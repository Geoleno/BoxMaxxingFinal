import Foundation

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

    enum EventStatus { case wrong, unclear }
}

// MARK: - Live Punch (for recording HUD)

struct LivePunch: Identifiable {
    let id = UUID()
    let move: Move
    let confidence: Double
    let timestamp: Date
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
