import XCTest
import Vision
@testable import BoxMaxxingFinal

final class SkeletonOverlayTests: XCTestCase {

    func test_skeletonFrame_storesJointsAndConfidence() {
        let joints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [
            .leftWrist: CGPoint(x: 0.3, y: 0.7)
        ]
        let confidence: [VNHumanBodyPoseObservation.JointName: Float] = [
            .leftWrist: 0.9
        ]
        let frame = SkeletonFrame(joints: joints, confidence: confidence)
        XCTAssertEqual(frame.joints[.leftWrist], CGPoint(x: 0.3, y: 0.7))
        XCTAssertEqual(frame.confidence[.leftWrist], 0.9)
    }

    func test_skeletonFrame_emptyJointsIsValid() {
        let frame = SkeletonFrame(joints: [:], confidence: [:])
        XCTAssertTrue(frame.joints.isEmpty)
    }
}
