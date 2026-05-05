import XCTest
@testable import BoxMaxxingFinal

@MainActor
final class SessionStoreTests: XCTestCase {

    override func setUp() {
        super.setUp()
        SessionStore.shared.clear()
    }

    func test_updateClip_setsURLOnMatchingEvent() {
        let event = SessionEvent(id: "e1", time: 10, move: allMoves[0],
                                 status: .wrong, confidence: 0.4,
                                 detectedAs: nil, note: "", clipURL: nil)
        SessionStore.shared.save(events: [event], startDate: Date(), duration: 120)
        let url = URL(fileURLWithPath: "/tmp/clip.mov")
        SessionStore.shared.updateClip(eventId: "e1", url: url)
        XCTAssertEqual(SessionStore.shared.currentEvents.first?.clipURL, url)
    }

    func test_updateClip_doesNotAffectOtherEvents() {
        let e1 = SessionEvent(id: "e1", time: 10, move: allMoves[0],
                              status: .wrong, confidence: 0.4,
                              detectedAs: nil, note: "", clipURL: nil)
        let e2 = SessionEvent(id: "e2", time: 20, move: allMoves[1],
                              status: .unclear, confidence: 0.6,
                              detectedAs: nil, note: "", clipURL: nil)
        SessionStore.shared.save(events: [e1, e2], startDate: Date(), duration: 120)
        SessionStore.shared.updateClip(eventId: "e1", url: URL(fileURLWithPath: "/tmp/clip.mov"))
        XCTAssertNil(SessionStore.shared.currentEvents.first { $0.id == "e2" }?.clipURL)
        // Verify the updated event preserved its non-clipURL fields
        let updatedEvent = SessionStore.shared.currentEvents.first { $0.id == "e1" }
        XCTAssertEqual(updatedEvent?.time, 10)
        XCTAssertEqual(updatedEvent?.confidence, 0.4)
        XCTAssertEqual(updatedEvent?.status, .wrong)
        XCTAssertNil(updatedEvent?.detectedAs)
    }

    func test_updateClip_unknownId_doesNothing() {
        let event = SessionEvent(id: "e1", time: 10, move: allMoves[0],
                                 status: .wrong, confidence: 0.4,
                                 detectedAs: nil, note: "", clipURL: nil)
        SessionStore.shared.save(events: [event], startDate: Date(), duration: 120)
        SessionStore.shared.updateClip(eventId: "unknown", url: URL(fileURLWithPath: "/tmp/clip.mov"))
        XCTAssertNil(SessionStore.shared.currentEvents.first?.clipURL)
    }
}
