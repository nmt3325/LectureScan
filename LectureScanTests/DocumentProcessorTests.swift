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
}
