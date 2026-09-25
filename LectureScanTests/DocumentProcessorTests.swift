import CoreImage
import XCTest
@testable import LectureScan

final class DocumentProcessorTests: XCTestCase {
    private let processor = DocumentProcessor()

    func testFallsBackToWholeImageWithoutRectangle() throws {
        let source = CIImage(color: CIColor(red: 0.2, green: 0.4, blue: 0.8))
            .cropped(to: CGRect(x: 0, y: 0, width: 320, height: 240))

        let result = try processor.process(
            source,
            preferredRectangle: nil,
            detectIfNeeded: false
        )

        XCTAssertFalse(result.rectangleFound)
        XCTAssertEqual(result.image.size.width, 320, accuracy: 1)
        XCTAssertEqual(result.image.size.height, 240, accuracy: 1)
    }

    func testAutomaticAbstentionKeepsWholeImage() throws {
        let source = CIImage(color: CIColor(red: 0.2, green: 0.4, blue: 0.8))
            .cropped(to: CGRect(x: 0, y: 0, width: 320, height: 240))

        let result = try processor.process(source)

        XCTAssertFalse(result.rectangleFound)
        XCTAssertNil(result.quadrilateral)
        XCTAssertEqual(result.image.size.width, 320, accuracy: 1)
        XCTAssertEqual(result.image.size.height, 240, accuracy: 1)
    }

    func testPerspectiveCorrectionWithKnownQuadrilateral() throws {
        let source = CIImage(color: CIColor(red: 0.95, green: 0.95, blue: 0.95))
            .cropped(to: CGRect(x: 0, y: 0, width: 800, height: 600))
        let rectangle = DetectedQuadrilateral(
            topLeft: CGPoint(x: 0.12, y: 0.90),
            topRight: CGPoint(x: 0.90, y: 0.84),
            bottomLeft: CGPoint(x: 0.18, y: 0.14),
            bottomRight: CGPoint(x: 0.86, y: 0.10)
        )

        let result = try processor.process(
            source,
            preferredRectangle: rectangle,
            detectIfNeeded: false
        )

        XCTAssertTrue(result.rectangleFound)
        XCTAssertEqual(result.quadrilateral?.topLeft.x ?? 0, rectangle.topLeft.x, accuracy: 0.0001)
        XCTAssertEqual(result.sourceImage.size.width, 800, accuracy: 1)
        XCTAssertEqual(result.sourceImage.size.height, 600, accuracy: 1)
        XCTAssertGreaterThan(result.image.size.width, 400)
        XCTAssertGreaterThan(result.image.size.height, 300)
        XCTAssertLessThan(result.image.size.width, 800)
        XCTAssertLessThan(result.image.size.height, 600)
    }

    func testCameraZoomRangeClampsToDeviceLimits() {
        let range = CameraZoomRange(minimum: 1, maximum: 8)

        XCTAssertEqual(range.clamped(0.5), 1, accuracy: 0.0001)
        XCTAssertEqual(range.clamped(3.25), 3.25, accuracy: 0.0001)
        XCTAssertEqual(range.clamped(12), 8, accuracy: 0.0001)
    }

    func testCameraZoomRangeNormalizesInvalidMaximum() {
        let range = CameraZoomRange(minimum: 2, maximum: 1)

        XCTAssertEqual(range.minimum, 2, accuracy: 0.0001)
        XCTAssertEqual(range.maximum, 2, accuracy: 0.0001)
        XCTAssertEqual(range.clamped(1), 2, accuracy: 0.0001)
    }

    func testApproximateArea() {
        let rectangle = DetectedQuadrilateral(
            topLeft: CGPoint(x: 0, y: 1),
            topRight: CGPoint(x: 1, y: 1),
            bottomLeft: CGPoint(x: 0, y: 0),
            bottomRight: CGPoint(x: 1, y: 0)
        )

        XCTAssertEqual(rectangle.approximateArea, 1, accuracy: 0.0001)
    }

    func testAspectFillMappingMatchesPortraitPreviewCrop() {
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 844)
        let contentRect = ImageDisplayGeometry.aspectFillRect(
            sourceSize: CGSize(width: 1_080, height: 1_920),
            in: bounds
        )

        let center = ImageDisplayGeometry.viewPoint(
            fromVisionPoint: CGPoint(x: 0.5, y: 0.5),
            contentRect: contentRect
        )
        let topLeft = ImageDisplayGeometry.viewPoint(
            fromVisionPoint: CGPoint(x: 0, y: 1),
            contentRect: contentRect
        )

        XCTAssertEqual(center.x, bounds.midX, accuracy: 0.001)
        XCTAssertEqual(center.y, bounds.midY, accuracy: 0.001)
        XCTAssertEqual(topLeft.x, contentRect.minX, accuracy: 0.001)
        XCTAssertEqual(topLeft.y, contentRect.minY, accuracy: 0.001)
        XCTAssertLessThan(contentRect.minX, 0)
        XCTAssertEqual(contentRect.height, bounds.height, accuracy: 0.001)
    }

    func testAspectFitPointConversionRoundTrips() {
        let contentRect = ImageDisplayGeometry.aspectFitRect(
            sourceSize: CGSize(width: 4_032, height: 3_024),
            in: CGRect(x: 0, y: 0, width: 360, height: 620)
        )
        let original = CGPoint(x: 0.27, y: 0.81)
        let viewPoint = ImageDisplayGeometry.viewPoint(
            fromVisionPoint: original,
            contentRect: contentRect
        )
        let recovered = ImageDisplayGeometry.visionPoint(
            fromViewPoint: viewPoint,
            contentRect: contentRect
        )

        XCTAssertEqual(recovered.x, original.x, accuracy: 0.0001)
        XCTAssertEqual(recovered.y, original.y, accuracy: 0.0001)
    }

    func testMovingCropCornerPreservesCornerOrdering() {
        let rectangle = DetectedQuadrilateral.fullFrame(inset: 0.1)
        let moved = rectangle.moving(
            .topLeft,
            to: CGPoint(x: 0.95, y: 0.05)
        )

        XCTAssertLessThan(moved.topLeft.x, moved.topRight.x)
        XCTAssertGreaterThan(moved.topLeft.y, moved.bottomLeft.y)
        XCTAssertEqual(moved.topLeft.x, moved.topRight.x - 0.01, accuracy: 0.0001)
        XCTAssertEqual(moved.topLeft.y, moved.bottomLeft.y + 0.01, accuracy: 0.0001)
    }
}
