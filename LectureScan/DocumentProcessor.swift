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
    private let resolver = RectangleResolver(policy: .productionSeed)

    func detectCandidates(
        in image: CIImage,
        requestSet: RectangleRequestSet,
        maximumDimension: CGFloat? = nil,
        quality: RectangleDetectionQuality = .preview
    ) throws -> RectangleCandidateBatch {
        let source = normalized(image)
        guard !source.extent.isEmpty else {
            return RectangleCandidateBatch(
                sourceSize: .zero,
                detectionSize: .zero,
                document: nil,
                rectangles: []
            )
        }

        let detectionMaximumDimension: CGFloat? = {
            switch quality {
            case .preview:
                return maximumDimension
            case .still:
                return maximumDimension ?? 2_048
            }
        }()
        let detectionImage = imageForDetection(
            source,
            maximumDimension: detectionMaximumDimension
        )
        let documentRequest: VNDetectDocumentSegmentationRequest? = {
            guard requestSet == .document || requestSet == .dual else { return nil }
            let request = VNDetectDocumentSegmentationRequest()
            request.revision = VNDetectDocumentSegmentationRequestRevision1
            return request
        }()
        let primaryRectangleRequest: VNDetectRectanglesRequest? = {
            guard requestSet == .rectangle || requestSet == .dual else { return nil }
            return rectangleRequest(profile: .preview)
        }()

        var requests: [VNRequest] = []
        if let documentRequest { requests.append(documentRequest) }
        if let primaryRectangleRequest { requests.append(primaryRectangleRequest) }
        try VNImageRequestHandler(
            ciImage: detectionImage,
            orientation: .up,
            options: [:]
        ).perform(requests)

        var collectedRectangleObservations = primaryRectangleRequest?.results ?? []
        if quality == .still, primaryRectangleRequest != nil {
            for profile in RectangleRequestProfile.stillRecoveryProfiles {
                if let recovered = try? rectangleObservations(
                    in: detectionImage,
                    profile: profile
                ) {
                    collectedRectangleObservations.append(contentsOf: recovered)
                }
            }
            if let recovered = try? rectangleObservations(
                in: recoveryDetectionImage(detectionImage),
                profile: .enhancedRecovery
            ) {
                collectedRectangleObservations.append(contentsOf: recovered)
            }
        }

        let sourceSize = source.extent.size
        let detectionSize = detectionImage.extent.size
        let document = documentRequest?.results?.first.map {
            candidate(
                from: $0,
                detector: .documentSegmentation,
                originalIndex: 0,
                sourceSize: sourceSize
            )
        }
        let rectangles = deduplicatedRectangleCandidates(
            collectedRectangleObservations.enumerated().map {
                candidate(
                    from: $0.element,
                    detector: .rectangle,
                    originalIndex: $0.offset,
                    sourceSize: sourceSize
                )
            },
            imageSize: detectionSize
        )
        return RectangleCandidateBatch(
            sourceSize: sourceSize,
            detectionSize: detectionSize,
            document: document,
            rectangles: rectangles
        )
    }

    func detectQuadrilateral(
        in image: CIImage,
        maximumDimension: CGFloat? = nil,
        prior: RectanglePrior? = nil,
        requestSet: RectangleRequestSet = .dual,
        mode: RectangleResolutionMode = .still
    ) throws -> DetectedQuadrilateral? {
        let batch = try detectCandidates(
            in: image,
            requestSet: requestSet,
            maximumDimension: maximumDimension,
            quality: mode == .still ? .still : .preview
        )
        return resolver.resolve(batch, prior: prior, mode: mode)
            .selection?.candidate.quadrilateral
    }

    func process(
        _ image: CIImage,
        preferredRectangle: DetectedQuadrilateral? = nil,
        detectionPrior: RectanglePrior? = nil,
        detectIfNeeded: Bool = true
    ) throws -> ProcessedDocument {
        let source = normalized(image)
        guard !source.extent.isEmpty else { throw DocumentProcessorError.emptyImage }

        let rectangle: DetectedQuadrilateral?
        if let preferredRectangle {
            rectangle = preferredRectangle.withSourceSize(source.extent.size)
        } else if detectIfNeeded {
            rectangle = try detectQuadrilateral(
                in: source,
                prior: detectionPrior,
                requestSet: .dual,
                mode: .still
            )
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

    private func rectangleRequest(
        profile: RectangleRequestProfile
    ) -> VNDetectRectanglesRequest {
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = profile.maximumObservations
        request.minimumConfidence = profile.minimumConfidence
        request.minimumSize = profile.minimumSize
        request.minimumAspectRatio = profile.minimumAspectRatio
        request.maximumAspectRatio = 1
        request.quadratureTolerance = profile.quadratureTolerance
        return request
    }

    private func rectangleObservations(
        in image: CIImage,
        profile: RectangleRequestProfile
    ) throws -> [VNRectangleObservation] {
        let request = rectangleRequest(profile: profile)
        try VNImageRequestHandler(
            ciImage: image,
            orientation: .up,
            options: [:]
        ).perform([request])
        return request.results ?? []
    }

    private func recoveryDetectionImage(_ image: CIImage) -> CIImage {
        let color = CIFilter.colorControls()
        color.inputImage = image
        color.saturation = 0
        color.contrast = 1.42

        let sharpen = CIFilter.unsharpMask()
        sharpen.inputImage = color.outputImage ?? image
        sharpen.radius = 2
        sharpen.intensity = 0.75
        return (sharpen.outputImage ?? color.outputImage ?? image).cropped(to: image.extent)
    }

    private func deduplicatedRectangleCandidates(
        _ candidates: [RectangleCandidate],
        imageSize: CGSize
    ) -> [RectangleCandidate] {
        candidates.reduce(into: []) { result, candidate in
            let isDuplicate = result.contains {
                RectangleGeometry.isDuplicateObservation(
                    $0.quadrilateral,
                    candidate.quadrilateral,
                    imageSize: imageSize
                )
            }
            if !isDuplicate { result.append(candidate) }
        }
    }

    private func candidate(
        from observation: VNRectangleObservation,
        detector: RectangleDetectorKind,
        originalIndex: Int,
        sourceSize: CGSize
    ) -> RectangleCandidate {
        RectangleCandidate(
            quadrilateral: DetectedQuadrilateral(
                topLeft: observation.topLeft,
                topRight: observation.topRight,
                bottomLeft: observation.bottomLeft,
                bottomRight: observation.bottomRight,
                sourceSize: sourceSize
            ),
            detector: detector,
            confidence: CGFloat(observation.confidence),
            originalIndex: originalIndex
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
        return image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
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
}
