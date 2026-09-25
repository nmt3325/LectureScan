import XCTest
import UIKit
@testable import LectureScan

final class CaptureLibraryTests: XCTestCase {
    func testCapturePersistsAndCanBeOpenedForLaterEditing() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LectureScanTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = CaptureLibraryStore(rootDirectory: directory)
        let sourceImage = makeImage(color: .blue, size: CGSize(width: 320, height: 240))
        let processedImage = makeImage(color: .yellow, size: CGSize(width: 200, height: 160))
        let capture = EditableCapture(
            sourceImage: sourceImage,
            automaticQuadrilateral: .fullFrame(sourceSize: sourceImage.size, inset: 0.1)
        )

        try store.save(capture: capture, processedImage: processedImage)
        let sourceURL = directory
            .appendingPathComponent(capture.id.uuidString, isDirectory: true)
            .appendingPathComponent("source.jpg")
        let sourceDataBeforeEditing = try Data(contentsOf: sourceURL)

        let reopenedCapture = try await store.editableCapture(for: capture.id)
        let reopenedProcessedImage = try await store.processedImage(for: capture.id)

        XCTAssertEqual(reopenedCapture.id, capture.id)
        XCTAssertEqual(reopenedCapture.selectedQuadrilateral, capture.selectedQuadrilateral)
        XCTAssertEqual(reopenedCapture.sourceImage.size, sourceImage.size)
        XCTAssertEqual(reopenedProcessedImage.size, processedImage.size)

        let relaunchedStore = CaptureLibraryStore(rootDirectory: directory)
        let captureAfterRelaunch = try await relaunchedStore.editableCapture(for: capture.id)
        XCTAssertEqual(captureAfterRelaunch.id, capture.id)
        XCTAssertEqual(
            captureAfterRelaunch.selectedQuadrilateral,
            capture.selectedQuadrilateral
        )

        let revisedQuadrilateral = capture.selectedQuadrilateral.moving(
            .topLeft,
            to: CGPoint(x: 0.2, y: 0.8)
        )
        let revisedCapture = capture.selecting(revisedQuadrilateral)
        let revisedProcessedImage = makeImage(
            color: .green,
            size: CGSize(width: 180, height: 140)
        )
        try relaunchedStore.save(
            capture: revisedCapture,
            processedImage: revisedProcessedImage
        )

        let captureAfterEditing = try await relaunchedStore.editableCapture(for: capture.id)
        let imageAfterEditing = try await relaunchedStore.processedImage(for: capture.id)
        XCTAssertEqual(captureAfterEditing.selectedQuadrilateral, revisedQuadrilateral)
        XCTAssertEqual(imageAfterEditing.size, revisedProcessedImage.size)
        XCTAssertEqual(
            try Data(contentsOf: sourceURL),
            sourceDataBeforeEditing,
            "Editing must preserve the originally stored source image."
        )

        let indexData = try Data(
            contentsOf: directory.appendingPathComponent("index.json")
        )
        let index = try XCTUnwrap(
            JSONSerialization.jsonObject(with: indexData) as? [[String: Any]]
        )
        XCTAssertEqual(index.count, 1, "Editing must update the existing library item.")
    }

    func testZoomDialClockwiseDragNowZoomsOut() {
        let range = CameraZoomRange(minimum: 0.5, maximum: 8)
        let radiansPerDoubling = CGFloat.pi / 6

        let clockwise = ZoomDialMath.factor(
            from: 2,
            angleDelta: radiansPerDoubling,
            radiansPerDoubling: radiansPerDoubling,
            range: range
        )
        let counterclockwise = ZoomDialMath.factor(
            from: 2,
            angleDelta: -radiansPerDoubling,
            radiansPerDoubling: radiansPerDoubling,
            range: range
        )

        XCTAssertEqual(clockwise, 1, accuracy: 0.001)
        XCTAssertEqual(counterclockwise, 4, accuracy: 0.001)
    }

    private func makeImage(color: UIColor, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
