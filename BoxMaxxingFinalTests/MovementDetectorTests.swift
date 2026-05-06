import XCTest
import CoreMedia
@testable import BoxMaxxingFinal

final class MovementDetectorTests: XCTestCase {

    var detector: MovementDetector!

    override func setUp() {
        super.setUp()
        detector = MovementDetector()
    }

    override func tearDown() {
        detector = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func ts(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 600)
    }

    private func pred(_ label: String, _ confidence: Float) -> FramePrediction {
        FramePrediction(label: label, confidence: confidence)
    }

    // MARK: - Idle → Confirming → nil (not yet confirmed)

    func test_idle_validMove_returnsNil() {
        let result = detector.process(prediction: pred("lj", 0.9), timestamp: ts(0.0), expectedMoveId: "rj")
        XCTAssertNil(result)
    }

    func test_idle_invalidLabel_returnsNil() {
        let result = detector.process(prediction: pred("no_body_detected", 0.9), timestamp: ts(0.0), expectedMoveId: "lj")
        XCTAssertNil(result)
    }

    func test_twoFramesSameLabel_returnsNil() {
        _ = detector.process(prediction: pred("rj", 0.9), timestamp: ts(0.0), expectedMoveId: "lj")
        let result = detector.process(prediction: pred("rj", 0.9), timestamp: ts(0.1), expectedMoveId: "lj")
        XCTAssertNil(result)
    }

    // MARK: - Confirmation

    func test_threeFramesWrongTechnique_returnsWrongMovement() {
        _ = detector.process(prediction: pred("rj", 0.9), timestamp: ts(0.0), expectedMoveId: "lj")
        _ = detector.process(prediction: pred("rj", 0.9), timestamp: ts(0.1), expectedMoveId: "lj")
        let result = detector.process(prediction: pred("rj", 0.9), timestamp: ts(0.2), expectedMoveId: "lj")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.detectedMoveId, "rj")
        XCTAssertEqual(result?.expectedMove.id, "lj")
        XCTAssertTrue(result?.isWrongTechnique ?? false)
    }

    func test_threeFramesLowConfidenceCorrectMove_returnsWrongMovement() {
        // detectedMoveId == expectedMoveId but confidence < 0.80 → wrong movement
        _ = detector.process(prediction: pred("lj", 0.5), timestamp: ts(0.0), expectedMoveId: "lj")
        _ = detector.process(prediction: pred("lj", 0.5), timestamp: ts(0.1), expectedMoveId: "lj")
        let result = detector.process(prediction: pred("lj", 0.5), timestamp: ts(0.2), expectedMoveId: "lj")
        XCTAssertNotNil(result)
        XCTAssertFalse(result?.isWrongTechnique ?? true)
        XCTAssertLessThan(result?.confidence ?? 1.0, 0.80)
    }

    func test_threeFramesHighConfidenceCorrectMove_returnsNil() {
        // detectedMoveId == expectedMoveId AND confidence ≥ 0.80 → correct, no emission
        _ = detector.process(prediction: pred("lj", 0.85), timestamp: ts(0.0), expectedMoveId: "lj")
        _ = detector.process(prediction: pred("lj", 0.85), timestamp: ts(0.1), expectedMoveId: "lj")
        let result = detector.process(prediction: pred("lj", 0.85), timestamp: ts(0.2), expectedMoveId: "lj")
        XCTAssertNil(result)
    }

    func test_confirmedMovement_timestampIsFirstFrame() {
        _ = detector.process(prediction: pred("rj", 0.9), timestamp: ts(1.0), expectedMoveId: "lj")
        _ = detector.process(prediction: pred("rj", 0.9), timestamp: ts(1.1), expectedMoveId: "lj")
        let result = detector.process(prediction: pred("rj", 0.9), timestamp: ts(1.2), expectedMoveId: "lj")
        XCTAssertEqual(CMTimeGetSeconds(result?.timestamp ?? .zero), 1.0, accuracy: 0.001)
    }

    func test_confirmedMovement_averagesConfidence() {
        _ = detector.process(prediction: pred("rj", 0.6), timestamp: ts(0.0), expectedMoveId: "lj")
        _ = detector.process(prediction: pred("rj", 0.8), timestamp: ts(0.1), expectedMoveId: "lj")
        let result = detector.process(prediction: pred("rj", 1.0), timestamp: ts(0.2), expectedMoveId: "lj")
        XCTAssertEqual(result?.confidence ?? 0, (0.6 + 0.8 + 1.0) / 3.0, accuracy: 0.001)
    }

    // MARK: - Label change resets to idle

    func test_labelChangeDuringConfirming_resetsToIdle() {
        _ = detector.process(prediction: pred("rj", 0.9), timestamp: ts(0.0), expectedMoveId: "lj")
        _ = detector.process(prediction: pred("lh", 0.9), timestamp: ts(0.1), expectedMoveId: "lj") // different label
        let result = detector.process(prediction: pred("rj", 0.9), timestamp: ts(0.2), expectedMoveId: "lj")
        XCTAssertNil(result) // Only 1 frame with "rj" after reset, not 3
    }

    // MARK: - Cooldown

    func test_cooldown_blocksNextEmissionImmediately() {
        // Confirm a wrong movement
        _ = detector.process(prediction: pred("rj", 0.9), timestamp: ts(0.0), expectedMoveId: "lj")
        _ = detector.process(prediction: pred("rj", 0.9), timestamp: ts(0.1), expectedMoveId: "lj")
        _ = detector.process(prediction: pred("rj", 0.9), timestamp: ts(0.2), expectedMoveId: "lj") // emits

        // Immediately after: 3 more frames should not emit (cooldown active, ~1.5s)
        _ = detector.process(prediction: pred("rh", 0.9), timestamp: ts(0.3), expectedMoveId: "lj")
        _ = detector.process(prediction: pred("rh", 0.9), timestamp: ts(0.4), expectedMoveId: "lj")
        let result = detector.process(prediction: pred("rh", 0.9), timestamp: ts(0.5), expectedMoveId: "lj")
        XCTAssertNil(result)
    }

    func test_cooldown_resumesAfterDuration() {
        // Confirm once at t=0
        _ = detector.process(prediction: pred("rj", 0.9), timestamp: ts(0.0), expectedMoveId: "lj")
        _ = detector.process(prediction: pred("rj", 0.9), timestamp: ts(0.1), expectedMoveId: "lj")
        _ = detector.process(prediction: pred("rj", 0.9), timestamp: ts(0.2), expectedMoveId: "lj") // emits

        // Frames during cooldown (< 1.5s from t=0.2) return nil
        _ = detector.process(prediction: pred("lh", 0.9), timestamp: ts(1.0), expectedMoveId: "lj")

        // After cooldown ends (t=0.2+1.5 = 1.7), a fresh 3-frame confirmation should emit
        _ = detector.process(prediction: pred("lh", 0.9), timestamp: ts(1.8), expectedMoveId: "lj") // cooldown expired
        _ = detector.process(prediction: pred("lh", 0.9), timestamp: ts(1.9), expectedMoveId: "lj")
        let result = detector.process(prediction: pred("lh", 0.9), timestamp: ts(2.0), expectedMoveId: "lj")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.detectedMoveId, "lh")
    }

    // MARK: - Reset

    func test_reset_clearsState() {
        _ = detector.process(prediction: pred("rj", 0.9), timestamp: ts(0.0), expectedMoveId: "lj")
        _ = detector.process(prediction: pred("rj", 0.9), timestamp: ts(0.1), expectedMoveId: "lj")
        detector.reset()
        // After reset, needs 3 fresh frames
        _ = detector.process(prediction: pred("rj", 0.9), timestamp: ts(0.2), expectedMoveId: "lj")
        _ = detector.process(prediction: pred("rj", 0.9), timestamp: ts(0.3), expectedMoveId: "lj")
        let result = detector.process(prediction: pred("rj", 0.9), timestamp: ts(0.4), expectedMoveId: "lj")
        XCTAssertNotNil(result) // Still emits after 3 fresh frames
    }
}
