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

    // MARK: - Coordinate conversion

    func test_toScreen_visionOriginBottomLeft_mapsToScreenBottomRight() {
        // Vision (0,0) = bottom-left; x is mirrored for front camera → screen bottom-right = (width, height)
        let result = SkeletonOverlayView.toScreen(CGPoint(x: 0, y: 0), size: CGSize(width: 100, height: 200))
        XCTAssertEqual(result, CGPoint(x: 100, y: 200))
    }

    func test_toScreen_visionTopRight_mapsToScreenTopLeft() {
        // Vision (1,1) = top-right; x is mirrored for front camera → screen top-left = (0, 0)
        let result = SkeletonOverlayView.toScreen(CGPoint(x: 1, y: 1), size: CGSize(width: 100, height: 200))
        XCTAssertEqual(result, CGPoint(x: 0, y: 0))
    }

    func test_toScreen_center_mapsToCenter() {
        // Center is symmetric — mirror does not affect x=0.5
        let result = SkeletonOverlayView.toScreen(CGPoint(x: 0.5, y: 0.5), size: CGSize(width: 100, height: 200))
        XCTAssertEqual(result, CGPoint(x: 50, y: 100))
    }

    func test_toScreen_visionTopLeft_mapsToScreenTopRight() {
        // Vision (0,1) = top-left; x is mirrored for front camera → screen top-right = (width, 0)
        let result = SkeletonOverlayView.toScreen(CGPoint(x: 0, y: 1), size: CGSize(width: 100, height: 200))
        XCTAssertEqual(result, CGPoint(x: 100, y: 0))
    }
}
