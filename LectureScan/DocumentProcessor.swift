import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Vision

struct ProcessedDocument {
    let image: UIImage
    let sourceImage: UIImage
    let quadrilateral: DetectedQuadrilateral?

    var rectangleFound: Bool { quadrilateral != nil }
}

enum DocumentProcessorError: LocalizedError {
    case emptyImage
    case renderingFailed

    var errorDescription: String? {
        switch self {
        case .emptyImage:
            return "撮影画像が空でした。"
        case .renderingFailed:
            return "画像の生成に失敗しました。"
        }
    }
}

final class DocumentProcessor {
    private let context = CIContext(options: [
        .cacheIntermediates: false,
        .useSoftwareRenderer: false
    ])

    func detectQuadrilateral(
        in image: CIImage,
        maximumDimension: CGFloat? = nil
    ) throws -> DetectedQuadrilateral? {
        let source = normalized(image)
        guard !source.extent.isEmpty else { return nil }

        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 6
        request.minimumConfidence = 0.55
        request.minimumSize = 0.16
        request.minimumAspectRatio = 0.22
        request.maximumAspectRatio = 1.0
        request.quadratureTolerance = 35

        let detectionImage = imageForDetection(
            source,
            maximumDimension: maximumDimension
        )
        let handler = VNImageRequestHandler(ciImage: detectionImage, orientation: .up, options: [:])
        try handler.perform([request])

        guard let observation = request.results?.max(by: { score($0) < score($1) }) else {
            return nil
        }

        return DetectedQuadrilateral(
            topLeft: observation.topLeft,
            topRight: observation.topRight,
            bottomLeft: observation.bottomLeft,
            bottomRight: observation.bottomRight,
            sourceSize: source.extent.size
        )
    }

    func process(
        _ image: CIImage,
        preferredRectangle: DetectedQuadrilateral? = nil,
        detectIfNeeded: Bool = true
    ) throws -> ProcessedDocument {
        let source = normalized(image)
        guard !source.extent.isEmpty else { throw DocumentProcessorError.emptyImage }

        let rectangle: DetectedQuadrilateral?
        if let preferredRectangle {
            rectangle = preferredRectangle.withSourceSize(source.extent.size)
        } else if detectIfNeeded {
            rectangle = try detectQuadrilateral(in: source)
        } else {
            rectangle = nil
        }

        let cropped = rectangle.map { perspectiveCorrect(source, to: $0) } ?? source
        let enhanced = enhance(cropped)

        return ProcessedDocument(
            image: try render(enhanced),
            sourceImage: try render(source),
            quadrilateral: rectangle
        )
    }

    private func normalized(_ image: CIImage) -> CIImage {
        guard image.extent.origin != .zero else { return image }
        return image.transformed(
            by: CGAffineTransform(
                translationX: -image.extent.origin.x,
                y: -image.extent.origin.y
            )
        )
    }

    private func imageForDetection(
        _ image: CIImage,
        maximumDimension: CGFloat?
    ) -> CIImage {
        guard let maximumDimension, maximumDimension > 0 else { return image }
        let longestDimension = max(image.extent.width, image.extent.height)
        guard longestDimension > maximumDimension else { return image }

        let scale = maximumDimension / longestDimension
        return image.transformed(
            by: CGAffineTransform(scaleX: scale, y: scale)
        )
    }

    private func perspectiveCorrect(
        _ image: CIImage,
        to rectangle: DetectedQuadrilateral
    ) -> CIImage {
        let extent = image.extent
        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = image
        filter.topLeft = imagePoint(rectangle.topLeft, in: extent)
        filter.topRight = imagePoint(rectangle.topRight, in: extent)
        filter.bottomLeft = imagePoint(rectangle.bottomLeft, in: extent)
        filter.bottomRight = imagePoint(rectangle.bottomRight, in: extent)
        return filter.outputImage ?? image
    }

    private func enhance(_ image: CIImage) -> CIImage {
        let color = CIFilter.colorControls()
        color.inputImage = image
        color.brightness = 0.01
        color.contrast = 1.08
        color.saturation = 0.97

        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = color.outputImage ?? image
        sharpen.sharpness = 0.30
        sharpen.radius = 1.2
        return sharpen.outputImage ?? color.outputImage ?? image
    }

    private func render(_ image: CIImage) throws -> UIImage {
        let renderBounds = image.extent.integral
        guard !renderBounds.isEmpty,
              let cgImage = context.createCGImage(image, from: renderBounds) else {
            throw DocumentProcessorError.renderingFailed
        }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }

    private func imagePoint(_ normalizedPoint: CGPoint, in extent: CGRect) -> CGPoint {
        CGPoint(
            x: extent.minX + normalizedPoint.x * extent.width,
            y: extent.minY + normalizedPoint.y * extent.height
        )
    }

    private func score(_ observation: VNRectangleObservation) -> CGFloat {
        let area = observation.boundingBox.width * observation.boundingBox.height
        return area * CGFloat(observation.confidence)
    }
}
