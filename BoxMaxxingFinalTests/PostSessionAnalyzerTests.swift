import XCTest
@testable import BoxMaxxingFinal

final class PostSessionAnalyzerTests: XCTestCase {

    let analyzer = PostSessionAnalyzer.shared
    let sampleURL = URL(fileURLWithPath: "/tmp/test_session.mov")

    // MARK: - groupWindows

    func test_groupWindows_emptyInput_returnsEmpty() {
        XCTAssertTrue(analyzer.groupWindows([]).isEmpty)
    }

    func test_groupWindows_singlePrediction_returnsSingleGroup() {
        let p = WindowPrediction(label: "lj", confidence: 0.6, startTime: 0.0, endTime: 2.0)
        let groups = analyzer.groupWindows([p])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].count, 1)
    }

    func test_groupWindows_sameLabelSmallGap_groupedTogether() {
        // Gap = p2.startTime (2.3) - p1.endTime (2.0) = 0.3s < 0.5 → same group
        let p1 = WindowPrediction(label: "lj", confidence: 0.6, startTime: 0.0, endTime: 2.0)
        let p2 = WindowPrediction(label: "lj", confidence: 0.7, startTime: 2.3, endTime: 4.3)
        let groups = analyzer.groupWindows([p1, p2])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].count, 2)
    }

    func test_groupWindows_sameLabelLargeGap_splitIntoTwoGroups() {
        // Gap = p2.startTime (3.0) - p1.endTime (2.0) = 1.0s > 0.5 → new group
        let p1 = WindowPrediction(label: "lj", confidence: 0.6, startTime: 0.0, endTime: 2.0)
        let p2 = WindowPrediction(label: "lj", confidence: 0.7, startTime: 3.0, endTime: 5.0)
        let groups = analyzer.groupWindows([p1, p2])
        XCTAssertEqual(groups.count, 2)
    }

    func test_groupWindows_differentLabels_splitIntoTwoGroups() {
        let p1 = WindowPrediction(label: "lj", confidence: 0.6, startTime: 0.0, endTime: 2.0)
        let p2 = WindowPrediction(label: "rj", confidence: 0.7, startTime: 2.3, endTime: 4.3)
        let groups = analyzer.groupWindows([p1, p2])
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0][0].label, "lj")
        XCTAssertEqual(groups[1][0].label, "rj")
    }

    func test_groupWindows_threeWindowsSameLabel_oneGroup() {
        let p1 = WindowPrediction(label: "lh", confidence: 0.4, startTime: 0.0, endTime: 2.0)
        let p2 = WindowPrediction(label: "lh", confidence: 0.6, startTime: 2.1, endTime: 4.1)
        let p3 = WindowPrediction(label: "lh", confidence: 0.5, startTime: 4.2, endTime: 6.2)
        let groups = analyzer.groupWindows([p1, p2, p3])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].count, 3)
    }

    // MARK: - selectRepresentative

    func test_selectRepresentative_returnsHighestConfidence() {
        let p1 = WindowPrediction(label: "lj", confidence: 0.40, startTime: 0.0, endTime: 2.0)
        let p2 = WindowPrediction(label: "lj", confidence: 0.71, startTime: 2.0, endTime: 4.0)
        let p3 = WindowPrediction(label: "lj", confidence: 0.55, startTime: 4.0, endTime: 6.0)
        let rep = analyzer.selectRepresentative(from: [p1, p2, p3])
        XCTAssertEqual(rep.confidence, 0.71, accuracy: 0.001)
    }

    func test_selectRepresentative_singleElement_returnsThatElement() {
        let p = WindowPrediction(label: "rj", confidence: 0.65, startTime: 5.0, endTime: 7.0)
        let rep = analyzer.selectRepresentative(from: [p])
        XCTAssertEqual(rep, p)
    }

    // MARK: - buildEvent

    func test_buildEvent_yellowConfidence_statusIsUnclear_clipURLSet() {
        let p = WindowPrediction(label: "lj", confidence: 0.65, startTime: 10.0, endTime: 12.0)
        let event = analyzer.buildEvent(from: p, videoDuration: 120.0, sessionURL: sampleURL)
        XCTAssertEqual(event.status, .unclear)
        XCTAssertEqual(event.time, 10)
        XCTAssertEqual(event.clipURL, sampleURL)
    }

    func test_buildEvent_redConfidence_statusIsWrong_clipURLSet() {
        let p = WindowPrediction(label: "rj", confidence: 0.35, startTime: 5.0, endTime: 7.0)
        let event = analyzer.buildEvent(from: p, videoDuration: 120.0, sessionURL: sampleURL)
        XCTAssertEqual(event.status, .wrong)
        XCTAssertEqual(event.clipURL, sampleURL)
    }

    func test_buildEvent_greenConfidence_statusIsCorrect_clipURLIsNil() {
        let p = WindowPrediction(label: "lh", confidence: 0.90, startTime: 30.0, endTime: 32.0)
        let event = analyzer.buildEvent(from: p, videoDuration: 120.0, sessionURL: sampleURL)
        XCTAssertEqual(event.status, .correct)
        XCTAssertNil(event.clipURL)
    }

    func test_buildEvent_usesWindowStartTimeAsEventTime() {
        let p = WindowPrediction(label: "lu", confidence: 0.55, startTime: 47.5, endTime: 49.5)
        let event = analyzer.buildEvent(from: p, videoDuration: 120.0, sessionURL: sampleURL)
        XCTAssertEqual(event.time, 47)   // Int(47.5) truncates to 47
    }

    func test_buildEvent_unknownMoveId_fallsBackToFirstMove() {
        let p = WindowPrediction(label: "unknown_move", confidence: 0.55, startTime: 5.0, endTime: 7.0)
        let event = analyzer.buildEvent(from: p, videoDuration: 120.0, sessionURL: sampleURL)
        XCTAssertEqual(event.move.id, allMoves[0].id)
    }
}
