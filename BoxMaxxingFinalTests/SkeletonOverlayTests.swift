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

    func test_toScreen_visionOriginBottomLeft_mapsToScreenBottomLeft() {
        // Vision (0,0) = bottom-left → screen bottom-left = (0, height)
        let result = SkeletonOverlayView.toScreen(CGPoint(x: 0, y: 0), size: CGSize(width: 100, height: 200))
        XCTAssertEqual(result, CGPoint(x: 0, y: 200))
    }

    func test_toScreen_visionTopRight_mapsToScreenTopRight() {
        // Vision (1,1) = top-right → screen top-right = (width, 0)
        let result = SkeletonOverlayView.toScreen(CGPoint(x: 1, y: 1), size: CGSize(width: 100, height: 200))
        XCTAssertEqual(result, CGPoint(x: 100, y: 0))
    }

    func test_toScreen_center_mapsToCenter() {
        let result = SkeletonOverlayView.toScreen(CGPoint(x: 0.5, y: 0.5), size: CGSize(width: 100, height: 200))
        XCTAssertEqual(result, CGPoint(x: 50, y: 100))
    }

    func test_toScreen_visionTopLeft_mapsToScreenTopLeft() {
        // Vision (0,1) = top-left → screen (0, 0)
        let result = SkeletonOverlayView.toScreen(CGPoint(x: 0, y: 1), size: CGSize(width: 100, height: 200))
        XCTAssertEqual(result, CGPoint(x: 0, y: 0))
    }
}
