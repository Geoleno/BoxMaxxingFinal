import Foundation
import Combine
import CoreMedia

final class SessionStore: ObservableObject {
    static let shared = SessionStore()
    private init() {}

    @Published private(set) var wrongMovements: [WrongMovement] = []
    private(set) var videoURL: URL?
    private(set) var sessionStartDate: Date?
    private(set) var sessionDuration: TimeInterval = 0

    @MainActor
    func save(movements: [WrongMovement], videoURL: URL?,
              startDate: Date, duration: TimeInterval) {
        wrongMovements       = movements
        self.videoURL        = videoURL
        sessionStartDate     = startDate
        sessionDuration      = duration
    }

    @MainActor
    func clear() {
        wrongMovements   = []
        videoURL         = nil
        sessionStartDate = nil
        sessionDuration  = 0
    }
}
