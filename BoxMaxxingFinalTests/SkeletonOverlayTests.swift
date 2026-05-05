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

    // When bufferSize == canvasSize there is no crop, so behaviour matches the simple mirror+flip.

    func test_toScreen_noCrop_bottomLeftMapsToBottomRight() {
        // Vision (0,0) = bottom-left; x mirrored for front camera → screen bottom-right
        let result = SkeletonOverlayView.toScreen(
            CGPoint(x: 0, y: 0),
            canvasSize: CGSize(width: 100, height: 200),
            bufferSize: CGSize(width: 100, height: 200)
        )
        XCTAssertEqual(result, CGPoint(x: 100, y: 200))
    }

    func test_toScreen_noCrop_topRightMapsToTopLeft() {
        // Vision (1,1) = top-right; x mirrored → screen top-left
        let result = SkeletonOverlayView.toScreen(
            CGPoint(x: 1, y: 1),
            canvasSize: CGSize(width: 100, height: 200),
            bufferSize: CGSize(width: 100, height: 200)
        )
        XCTAssertEqual(result, CGPoint(x: 0, y: 0))
    }

    func test_toScreen_noCrop_centerMapsToCenter() {
        // Center is symmetric — mirror and crop do not shift x=0.5, y=0.5
        let result = SkeletonOverlayView.toScreen(
            CGPoint(x: 0.5, y: 0.5),
            canvasSize: CGSize(width: 100, height: 200),
            bufferSize: CGSize(width: 100, height: 200)
        )
        XCTAssertEqual(result, CGPoint(x: 50, y: 100))
    }

    func test_toScreen_noCrop_topLeftMapsToTopRight() {
        // Vision (0,1) = top-left; x mirrored → screen top-right
        let result = SkeletonOverlayView.toScreen(
            CGPoint(x: 0, y: 1),
            canvasSize: CGSize(width: 100, height: 200),
            bufferSize: CGSize(width: 100, height: 200)
        )
        XCTAssertEqual(result, CGPoint(x: 100, y: 0))
    }

    // Crop tests: buffer 2× wider than canvas → 25% cropped from each x side.

    func test_toScreen_withCrop_centerStaysCenter() {
        // Buffer 200×100, canvas 100×100 → cropX = 0.25, cropY = 0
        // Center (0.5, 0.5) is symmetric → stays at screen center (50, 50)
        let result = SkeletonOverlayView.toScreen(
            CGPoint(x: 0.5, y: 0.5),
            canvasSize: CGSize(width: 100, height: 100),
            bufferSize: CGSize(width: 200, height: 100)
        )
        XCTAssertEqual(result.x, 50, accuracy: 0.5)
        XCTAssertEqual(result.y, 50, accuracy: 0.5)
    }

    func test_toScreen_withCrop_visibleEdgeMapsToScreenEdge() {
        // Buffer 200×100, canvas 100×100 → cropX = 0.25
        // Vision x=0.25 is the left boundary of what's visible in the un-mirrored buffer.
        // After mirror (1-0.25=0.75) that boundary maps to screen x=100 (right edge).
        let result = SkeletonOverlayView.toScreen(
            CGPoint(x: 0.25, y: 0.5),
            canvasSize: CGSize(width: 100, height: 100),
            bufferSize: CGSize(width: 200, height: 100)
        )
        XCTAssertEqual(result.x, 100, accuracy: 0.5)
        XCTAssertEqual(result.y, 50, accuracy: 0.5)
    }
}
