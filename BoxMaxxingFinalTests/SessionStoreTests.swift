import XCTest
import CoreMedia
@testable import BoxMaxxingFinal

@MainActor
final class SessionStoreTests: XCTestCase {

    override func setUp() {
        super.setUp()
        SessionStore.shared.clear()
    }

    override func tearDown() {
        SessionStore.shared.clear()
        super.tearDown()
    }

    // MARK: - New API: wrongMovements + videoURL

    func test_saveMovements_storesWrongMovements() {
        let m = WrongMovement(timestamp: CMTime(seconds: 5, preferredTimescale: 600),
                              expectedMove: allMoves[0],
                              detectedMoveId: "rj",
                              confidence: 0.9)
        SessionStore.shared.save(movements: [m], videoURL: nil, startDate: Date(), duration: 60)
        XCTAssertEqual(SessionStore.shared.wrongMovements.count, 1)
        XCTAssertEqual(SessionStore.shared.wrongMovements[0].detectedMoveId, "rj")
    }

    func test_saveMovements_storesVideoURL() {
        let url = URL(fileURLWithPath: "/tmp/session.mov")
        SessionStore.shared.save(movements: [], videoURL: url, startDate: Date(), duration: 60)
        XCTAssertEqual(SessionStore.shared.videoURL, url)
    }

    func test_saveMovements_nilVideoURL_storesNil() {
        SessionStore.shared.save(movements: [], videoURL: nil, startDate: Date(), duration: 60)
        XCTAssertNil(SessionStore.shared.videoURL)
    }

    func test_clear_resetsWrongMovementsAndVideoURL() {
        let url = URL(fileURLWithPath: "/tmp/session.mov")
        let m = WrongMovement(timestamp: CMTime(seconds: 1, preferredTimescale: 600),
                              expectedMove: allMoves[0],
                              detectedMoveId: "lj",
                              confidence: 0.5)
        SessionStore.shared.save(movements: [m], videoURL: url, startDate: Date(), duration: 60)
        SessionStore.shared.clear()
        XCTAssertTrue(SessionStore.shared.wrongMovements.isEmpty)
        XCTAssertNil(SessionStore.shared.videoURL)
    }

    func test_saveMovements_multipleMovements_preservesOrder() {
        let m1 = WrongMovement(timestamp: CMTime(seconds: 1, preferredTimescale: 600),
                               expectedMove: allMoves[0], detectedMoveId: "rj", confidence: 0.9)
        let m2 = WrongMovement(timestamp: CMTime(seconds: 2, preferredTimescale: 600),
                               expectedMove: allMoves[1], detectedMoveId: "lh", confidence: 0.7)
        SessionStore.shared.save(movements: [m1, m2], videoURL: nil, startDate: Date(), duration: 60)
        XCTAssertEqual(SessionStore.shared.wrongMovements.count, 2)
        XCTAssertEqual(SessionStore.shared.wrongMovements[1].detectedMoveId, "lh")
    }
}
