import Foundation
import Combine

final class SessionStore: ObservableObject {
    static let shared = SessionStore()
    private init() {}

    @Published private(set) var currentEvents: [SessionEvent] = []
    private(set) var sessionStartDate: Date?
    private(set) var sessionDuration: TimeInterval = 0

    @MainActor
    func save(events: [SessionEvent], startDate: Date, duration: TimeInterval) {
        currentEvents = events
        sessionStartDate = startDate
        sessionDuration = duration
    }

    /// Replaces the event matching `eventId` with an updated copy that has `clipURL` set.
    /// Must be called on the main queue.
    @MainActor
    func updateClip(eventId: String, url: URL) {
        guard let idx = currentEvents.firstIndex(where: { $0.id == eventId }) else { return }
        let old = currentEvents[idx]
        currentEvents[idx] = SessionEvent(
            id: old.id, time: old.time, move: old.move,
            status: old.status, confidence: old.confidence,
            detectedAs: old.detectedAs, note: old.note,
            clipURL: url
        )
    }

    @MainActor
    func clear() {
        currentEvents = []
        sessionStartDate = nil
        sessionDuration = 0
    }
}
