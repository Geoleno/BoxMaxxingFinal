import Foundation

// MARK: - Session Store

final class SessionStore {
    static let shared = SessionStore()
    private init() {}

    private(set) var currentEvents: [SessionEvent] = []
    private(set) var sessionStartDate: Date?
    private(set) var sessionDuration: TimeInterval = 0

    func save(events: [SessionEvent], startDate: Date, duration: TimeInterval) {
        currentEvents = events
        sessionStartDate = startDate
        sessionDuration = duration
    }

    func clear() {
        currentEvents = []
        sessionStartDate = nil
        sessionDuration = 0
    }
}
