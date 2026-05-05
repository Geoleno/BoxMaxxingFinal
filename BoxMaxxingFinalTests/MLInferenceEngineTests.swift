import XCTest
import Vision
@testable import BoxMaxxingFinal

final class MLInferenceEngineTests: XCTestCase {

    func test_labelToMoveId_mapsAllSixClasses() {
        XCTAssertEqual(MLInferenceEngine.labelToMoveId["Jab"],            "lj")
        XCTAssertEqual(MLInferenceEngine.labelToMoveId["Straight"],       "rj")
        XCTAssertEqual(MLInferenceEngine.labelToMoveId["Left Hook"],      "lh")
        XCTAssertEqual(MLInferenceEngine.labelToMoveId["Right Hook"],     "rh")
        XCTAssertEqual(MLInferenceEngine.labelToMoveId["Left Uppercut"],  "lu")
        XCTAssertEqual(MLInferenceEngine.labelToMoveId["Right Uppercut"], "ru")
    }

    func test_jointNames_hasExactly18Entries() {
        XCTAssertEqual(MLInferenceEngine.jointNames.count, 18)
    }

    func test_predictMove_nilObservations_returnsNoBody() {
        let engine = MLInferenceEngine()
        let pred = engine.predictMove(from: nil)
        XCTAssertEqual(pred.label, "no_body_detected")
        XCTAssertEqual(pred.confidence, 0.0)
    }

    func test_predictMove_emptyObservations_returnsNoBody() {
        let engine = MLInferenceEngine()
        let pred = engine.predictMove(from: [])
        XCTAssertEqual(pred.label, "no_body_detected")
        XCTAssertEqual(pred.confidence, 0.0)
    }

    func test_resetBuffer_doesNotCrash_andSubsequentNilPredictionWorks() {
        let engine = MLInferenceEngine()
        engine.resetBuffer()
        let pred = engine.predictMove(from: nil)
        XCTAssertEqual(pred.label, "no_body_detected")
    }
}
