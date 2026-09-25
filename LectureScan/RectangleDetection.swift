import CoreGraphics
import Foundation

enum RectangleDetectorKind: Equatable {
    case documentSegmentation
    case rectangle
}

enum RectangleRequestSet: Equatable {
    case document
    case rectangle
    case dual
}

struct RectangleCandidate: Equatable {
    let quadrilateral: DetectedQuadrilateral
    let detector: RectangleDetectorKind
    let confidence: CGFloat
    let originalIndex: Int
}

struct RectangleCandidateBatch: Equatable {
    let sourceSize: CGSize
    let detectionSize: CGSize
    let document: RectangleCandidate?
    let rectangles: [RectangleCandidate]

    var allCandidates: [RectangleCandidate] {
        (document.map { [$0] } ?? []) + rectangles
    }
}

enum RectangleResolutionMode: Equatable {
    case liveAcquisition
    case liveTracking
    case still
}

struct RectanglePrior: Equatable {
    let quadrilateral: DetectedQuadrilateral
    let detector: RectangleDetectorKind
}

enum RectangleSelectionEvidence: Equatable {
    case priorAssociation
    case crossDetectorConsensus
    case highConfidenceDocument
    case rectangleAcquisition
}

struct RectangleSelection: Equatable {
    let candidate: RectangleCandidate
    let evidence: RectangleSelectionEvidence
}

enum RectangleAbstainReason: Equatable {
    case noCandidates
    case invalidCandidates
    case detectorDisagreement
    case insufficientEvidence
    case ambiguousRectangleAcquisition
    case frameLikeDocument
}

enum RectangleResolution: Equatable {
    case selected(RectangleSelection)
    case abstain(RectangleAbstainReason)

    var selection: RectangleSelection? {
        guard case .selected(let value) = self else { return nil }
        return value
    }
}

struct RectangleDetectionPolicy {
    let minimumNormalizedArea: CGFloat
    let minimumEdgePixels: CGFloat
    let minimumAngleDegrees: CGFloat
    let maximumAngleDegrees: CGFloat
    let softMinimumArea: CGFloat
    let softMinimumFillRatio: CGFloat
    let softMinimumAngleDegrees: CGFloat
    let softMaximumAngleDegrees: CGFloat
    let documentHighConfidence: CGFloat
    let documentMediumConfidence: CGFloat
    let frameLikeMinimumArea: CGFloat
    let frameLikeMinimumBorderSides: Int
    let frameLikeMaximumCornerRMS: CGFloat
    let consensusMinimumIoU: CGFloat
    let consensusMaximumCornerDistance: CGFloat
    let consensusMinimumAreaRatio: CGFloat
    let associationMinimumScore: CGFloat
    let associationMinimumIoU: CGFloat
    let associationMaximumCornerDistance: CGFloat
    let associationMinimumAreaRatio: CGFloat
    let acquisitionMinimumScore: CGFloat
    let acquisitionMinimumMargin: CGFloat
    let singleRequestSpacing: CFTimeInterval
    let dualRequestSpacing: CFTimeInterval
    let minimumPostCompletionGap: CFTimeInterval
    let documentProbeInterval: CFTimeInterval
    let pendingTTL: CFTimeInterval
    let overlayHoldDuration: CFTimeInterval
    let ambiguousDeadline: CFTimeInterval
    let maximumDualEvaluations: Int
    let longFrameGap: CFTimeInterval
    let smoothingAmount: CGFloat
    let capturePriorMaximumAge: CFTimeInterval
    let capturePriorMaximumZoomLogDifference: CGFloat

    static let productionSeed = RectangleDetectionPolicy(
        minimumNormalizedArea: 0.003,
        minimumEdgePixels: 8,
        minimumAngleDegrees: 5,
        maximumAngleDegrees: 175,
        softMinimumArea: 0.02,
        softMinimumFillRatio: 0.45,
        softMinimumAngleDegrees: 12,
        softMaximumAngleDegrees: 168,
        documentHighConfidence: 0.65,
        documentMediumConfidence: 0.40,
        frameLikeMinimumArea: 0.65,
        frameLikeMinimumBorderSides: 3,
        frameLikeMaximumCornerRMS: 0.18,
        consensusMinimumIoU: 0.60,
        consensusMaximumCornerDistance: 0.12,
        consensusMinimumAreaRatio: 0.60,
        associationMinimumScore: 0.65,
        associationMinimumIoU: 0.40,
        associationMaximumCornerDistance: 0.12,
        associationMinimumAreaRatio: 0.50,
        acquisitionMinimumScore: 0.55,
        acquisitionMinimumMargin: 0.12,
        singleRequestSpacing: 0.10,
        dualRequestSpacing: 0.12,
        minimumPostCompletionGap: 0.02,
        documentProbeInterval: 0.60,
        pendingTTL: 0.40,
        overlayHoldDuration: 0.35,
        ambiguousDeadline: 0.45,
        maximumDualEvaluations: 3,
        longFrameGap: 0.50,
        smoothingAmount: 0.58,
        capturePriorMaximumAge: 0.20,
        capturePriorMaximumZoomLogDifference: 0.01
    )
}

struct RectangleValidation: Equatable {
    let isHardValid: Bool
    let polygonArea: CGFloat
    let fillRatio: CGFloat
    let minimumEdgePixels: CGFloat
    let minimumAngleDegrees: CGFloat
    let maximumAngleDegrees: CGFloat
    let distinctBorderSides: Int
    let frameCornerRMS: CGFloat
    let frameLikeRisk: Bool
    let hasSoftShapeRisk: Bool
}

struct RectangleAssociation: Equatable {
    let score: CGFloat
    let polygonIoU: CGFloat
    let normalizedCornerDistance: CGFloat
    let areaRatio: CGFloat
    let normalizedCenterDistance: CGFloat
}

enum RectangleGeometry {
    static func points(_ quadrilateral: DetectedQuadrilateral) -> [CGPoint] {
        [quadrilateral.topLeft, quadrilateral.topRight,
         quadrilateral.bottomRight, quadrilateral.bottomLeft]
    }

    static func pixelPoints(
        _ quadrilateral: DetectedQuadrilateral,
        imageSize: CGSize
    ) -> [CGPoint] {
        points(quadrilateral).map {
            CGPoint(x: $0.x * imageSize.width, y: $0.y * imageSize.height)
        }
    }

    static func boundingBox(_ quadrilateral: DetectedQuadrilateral) -> CGRect {
        let values = points(quadrilateral)
        guard let first = values.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in values.dropFirst() {
            minX = min(minX, point.x); maxX = max(maxX, point.x)
            minY = min(minY, point.y); maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func centroid(_ quadrilateral: DetectedQuadrilateral) -> CGPoint {
        let values = points(quadrilateral)
        return CGPoint(
            x: values.reduce(0) { $0 + $1.x } / CGFloat(values.count),
            y: values.reduce(0) { $0 + $1.y } / CGFloat(values.count)
        )
    }

    static func polygonIoU(
        _ lhs: DetectedQuadrilateral,
        _ rhs: DetectedQuadrilateral
    ) -> CGFloat {
        let left = points(lhs), right = points(rhs)
        let intersectionArea = abs(signedArea(clip(subject: left, by: right)))
        let union = abs(signedArea(left)) + abs(signedArea(right)) - intersectionArea
        guard union > 0 else { return 0 }
        return min(max(intersectionArea / union, 0), 1)
    }

    static func meanCornerDistance(
        _ lhs: DetectedQuadrilateral,
        _ rhs: DetectedQuadrilateral,
        imageSize: CGSize
    ) -> CGFloat {
        let left = pixelPoints(lhs, imageSize: imageSize)
        let right = pixelPoints(rhs, imageSize: imageSize)
        return zip(left, right).reduce(CGFloat.zero) { $0 + distance($1.0, $1.1) }
            / CGFloat(left.count)
    }

    static func isSameTarget(
        _ lhs: DetectedQuadrilateral,
        _ rhs: DetectedQuadrilateral,
        imageSize: CGSize,
        policy: RectangleDetectionPolicy
    ) -> Bool {
        let value = association(prior: lhs, candidate: rhs, imageSize: imageSize)
        return value.score >= policy.associationMinimumScore
            && (value.polygonIoU >= policy.associationMinimumIoU
                || value.normalizedCornerDistance <= policy.associationMaximumCornerDistance)
            && value.areaRatio >= policy.associationMinimumAreaRatio
    }

    static func association(
        prior: DetectedQuadrilateral,
        candidate: DetectedQuadrilateral,
        imageSize: CGSize
    ) -> RectangleAssociation {
        let iou = polygonIoU(prior, candidate)
        let priorBox = boundingBox(prior)
        let diagonal = max(
            hypot(priorBox.width * imageSize.width, priorBox.height * imageSize.height), 1
        )
        let cornerDistance = meanCornerDistance(prior, candidate, imageSize: imageSize) / diagonal
        let cornerSimilarity = exp(-0.5 * pow(cornerDistance / 0.20, 2))
        let priorArea = max(prior.approximateArea, 0.000_001)
        let candidateArea = max(candidate.approximateArea, 0.000_001)
        let areaRatio = min(candidateArea / priorArea, priorArea / candidateArea)
        let priorCenter = centroid(prior), candidateCenter = centroid(candidate)
        let centerDistance = hypot(
            (priorCenter.x - candidateCenter.x) * imageSize.width,
            (priorCenter.y - candidateCenter.y) * imageSize.height
        ) / diagonal
        let centerSimilarity = exp(-0.5 * pow(centerDistance / 0.25, 2))
        return RectangleAssociation(
            score: 0.55 * iou + 0.25 * cornerSimilarity
                + 0.10 * areaRatio + 0.10 * centerSimilarity,
            polygonIoU: iou,
            normalizedCornerDistance: cornerDistance,
            areaRatio: areaRatio,
            normalizedCenterDistance: centerDistance
        )
    }

    static func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    static func signedArea(_ values: [CGPoint]) -> CGFloat {
        guard values.count >= 3 else { return 0 }
        var total: CGFloat = 0
        for index in values.indices {
            let next = values[(index + 1) % values.count]
            total += values[index].x * next.y - next.x * values[index].y
        }
        return total / 2
    }

    static func cross(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        lhs.x * rhs.y - lhs.y * rhs.x
    }

    static func subtract(_ lhs: CGPoint, _ rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    private static func clip(subject: [CGPoint], by clipPolygon: [CGPoint]) -> [CGPoint] {
        guard subject.count >= 3, clipPolygon.count >= 3 else { return [] }
        var output = subject
        let orientation = signedArea(clipPolygon)
        for index in clipPolygon.indices {
            let edgeStart = clipPolygon[index]
            let edgeEnd = clipPolygon[(index + 1) % clipPolygon.count]
            let input = output
            output = []
            guard var previous = input.last else { break }
            var previousInside = inside(
                previous, edgeStart: edgeStart, edgeEnd: edgeEnd, orientation: orientation
            )
            for current in input {
                let currentInside = inside(
                    current, edgeStart: edgeStart, edgeEnd: edgeEnd, orientation: orientation
                )
                if currentInside != previousInside,
                   let point = intersection(
                    segmentStart: previous, segmentEnd: current,
                    lineStart: edgeStart, lineEnd: edgeEnd
                   ) {
                    output.append(point)
                }
                if currentInside { output.append(current) }
                previous = current
                previousInside = currentInside
            }
        }
        return output
    }

    private static func inside(
        _ point: CGPoint,
        edgeStart: CGPoint,
        edgeEnd: CGPoint,
        orientation: CGFloat
    ) -> Bool {
        let value = cross(subtract(edgeEnd, edgeStart), subtract(point, edgeStart))
        return orientation >= 0 ? value >= -0.000_001 : value <= 0.000_001
    }

    private static func intersection(
        segmentStart: CGPoint,
        segmentEnd: CGPoint,
        lineStart: CGPoint,
        lineEnd: CGPoint
    ) -> CGPoint? {
        let segment = subtract(segmentEnd, segmentStart)
        let line = subtract(lineEnd, lineStart)
        let denominator = cross(segment, line)
        guard abs(denominator) > 0.000_001 else { return nil }
        let t = cross(subtract(lineStart, segmentStart), line) / denominator
        return CGPoint(x: segmentStart.x + t * segment.x, y: segmentStart.y + t * segment.y)
    }
}

struct RectangleValidator {
    let policy: RectangleDetectionPolicy

    init(policy: RectangleDetectionPolicy = .productionSeed) {
        self.policy = policy
    }

    func validate(_ candidate: RectangleCandidate, imageSize: CGSize) -> RectangleValidation {
        let normalized = RectangleGeometry.points(candidate.quadrilateral)
        let pixels = RectangleGeometry.pixelPoints(candidate.quadrilateral, imageSize: imageSize)
        let finite = normalized.allSatisfy { $0.x.isFinite && $0.y.isFinite }
        let inOuterBounds = normalized.allSatisfy {
            $0.x >= -0.10 && $0.x <= 1.10 && $0.y >= -0.10 && $0.y <= 1.10
        }
        let area = candidate.quadrilateral.approximateArea
        let box = RectangleGeometry.boundingBox(candidate.quadrilateral)
        let fillRatio = min(max(area / max(box.width * box.height, 0.000_001), 0), 1)
        let edges = pixels.indices.map {
            RectangleGeometry.distance(pixels[$0], pixels[($0 + 1) % pixels.count])
        }
        let minimumEdge = edges.min() ?? 0
        let angles = interiorAngles(points: pixels)
        let minimumAngle = angles.min() ?? 0
        let maximumAngle = angles.max() ?? 180
        let selfIntersects = segmentsIntersect(normalized[0], normalized[1], normalized[2], normalized[3])
            || segmentsIntersect(normalized[1], normalized[2], normalized[3], normalized[0])
        let epsilonX = min(max(8 / max(imageSize.width, 1), 0.005), 0.015)
        let epsilonY = min(max(8 / max(imageSize.height, 1), 0.005), 0.015)
        let distinctSides = [
            box.minX <= epsilonX, box.maxX >= 1 - epsilonX,
            box.minY <= epsilonY, box.maxY >= 1 - epsilonY
        ].filter { $0 }.count
        let frameCorners = [
            CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1),
            CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 0)
        ]
        let meanSquared = zip(normalized, frameCorners).reduce(CGFloat.zero) {
            $0 + pow($1.0.x - $1.1.x, 2) + pow($1.0.y - $1.1.y, 2)
        } / CGFloat(frameCorners.count)
        let frameRMS = sqrt(meanSquared)
        let frameLike = area >= policy.frameLikeMinimumArea
            && distinctSides >= policy.frameLikeMinimumBorderSides
            && frameRMS <= policy.frameLikeMaximumCornerRMS
        let slightlyOutside = normalized.contains {
            $0.x < 0 || $0.x > 1 || $0.y < 0 || $0.y > 1
        }
        let softRisk = area < policy.softMinimumArea
            || fillRatio < policy.softMinimumFillRatio
            || minimumAngle < policy.softMinimumAngleDegrees
            || maximumAngle > policy.softMaximumAngleDegrees
            || slightlyOutside
        let hardValid = imageSize.width > 0 && imageSize.height > 0
            && finite && inOuterBounds && !selfIntersects && isConvex(points: normalized)
            && area >= policy.minimumNormalizedArea
            && minimumEdge >= policy.minimumEdgePixels
            && minimumAngle > policy.minimumAngleDegrees
            && maximumAngle < policy.maximumAngleDegrees
        return RectangleValidation(
            isHardValid: hardValid,
            polygonArea: area,
            fillRatio: fillRatio,
            minimumEdgePixels: minimumEdge,
            minimumAngleDegrees: minimumAngle,
            maximumAngleDegrees: maximumAngle,
            distinctBorderSides: distinctSides,
            frameCornerRMS: frameRMS,
            frameLikeRisk: frameLike,
            hasSoftShapeRisk: softRisk
        )
    }

    private func isConvex(points: [CGPoint]) -> Bool {
        guard points.count == 4 else { return false }
        var sign: CGFloat = 0
        for index in points.indices {
            let value = RectangleGeometry.cross(
                RectangleGeometry.subtract(points[(index + 1) % 4], points[index]),
                RectangleGeometry.subtract(points[(index + 2) % 4], points[(index + 1) % 4])
            )
            guard abs(value) > 0.000_001 else { return false }
            if sign == 0 { sign = value } else if value * sign < 0 { return false }
        }
        return true
    }

    private func interiorAngles(points: [CGPoint]) -> [CGFloat] {
        points.indices.map { index in
            let current = points[index]
            let lhs = RectangleGeometry.subtract(points[(index + 3) % 4], current)
            let rhs = RectangleGeometry.subtract(points[(index + 1) % 4], current)
            let lhsLength = max(hypot(lhs.x, lhs.y), 0.000_001)
            let rhsLength = max(hypot(rhs.x, rhs.y), 0.000_001)
            let cosine = min(max(
                (lhs.x * rhs.x + lhs.y * rhs.y) / (lhsLength * rhsLength), -1
            ), 1)
            return acos(cosine) * 180 / .pi
        }
    }

    private func segmentsIntersect(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Bool {
        func orientation(_ p: CGPoint, _ q: CGPoint, _ r: CGPoint) -> CGFloat {
            RectangleGeometry.cross(
                RectangleGeometry.subtract(q, p), RectangleGeometry.subtract(r, p)
            )
        }
        let first = orientation(a, b, c), second = orientation(a, b, d)
        let third = orientation(c, d, a), fourth = orientation(c, d, b)
        return first * second < 0 && third * fourth < 0
    }
}

struct RectangleResolver {
    let policy: RectangleDetectionPolicy
    private let validator: RectangleValidator

    init(policy: RectangleDetectionPolicy = .productionSeed) {
        self.policy = policy
        validator = RectangleValidator(policy: policy)
    }

    func resolve(
        _ batch: RectangleCandidateBatch,
        prior: RectanglePrior?,
        mode: RectangleResolutionMode
    ) -> RectangleResolution {
        let documentEntry = batch.document.map {
            ($0, validator.validate($0, imageSize: batch.detectionSize))
        }
        let rectangleEntries = batch.rectangles.map {
            ($0, validator.validate($0, imageSize: batch.detectionSize))
        }
        let validRectangles = rectangleEntries.filter { $0.1.isHardValid }
        let validDocument = documentEntry.flatMap { $0.1.isHardValid ? $0 : nil }
        let hasAnyCandidate = batch.document != nil || !batch.rectangles.isEmpty

        if let prior {
            let entries = ([validDocument].compactMap { $0 } + validRectangles)
            let associated = entries.compactMap {
                entry -> (RectangleCandidate, RectangleValidation, RectangleAssociation)? in
                let value = RectangleGeometry.association(
                    prior: prior.quadrilateral,
                    candidate: entry.0.quadrilateral,
                    imageSize: batch.detectionSize
                )
                guard isStrongAssociation(value) else { return nil }
                return (entry.0, entry.1, value)
            }.sorted { lhs, rhs in
                if abs(lhs.2.score - rhs.2.score) > 0.000_001 {
                    return lhs.2.score > rhs.2.score
                }
                if abs(lhs.2.polygonIoU - rhs.2.polygonIoU) > 0.000_001 {
                    return lhs.2.polygonIoU > rhs.2.polygonIoU
                }
                if abs(lhs.2.normalizedCornerDistance - rhs.2.normalizedCornerDistance) > 0.000_001 {
                    return lhs.2.normalizedCornerDistance < rhs.2.normalizedCornerDistance
                }
                return lhs.0.originalIndex < rhs.0.originalIndex
            }
            if let best = associated.first {
                if best.0.detector == .documentSegmentation,
                   (best.1.frameLikeRisk || best.1.hasSoftShapeRisk),
                   let rectangle = associated.first(where: { $0.0.detector == .rectangle }) {
                    return .selected(RectangleSelection(
                        candidate: rectangle.0,
                        evidence: .priorAssociation
                    ))
                }
                if best.0.detector == .rectangle
                    || (best.0.confidence >= policy.documentMediumConfidence
                        && !best.1.frameLikeRisk) {
                    return .selected(RectangleSelection(
                        candidate: best.0,
                        evidence: .priorAssociation
                    ))
                }
            }
        }

        if let document = validDocument,
           document.0.confidence >= policy.documentMediumConfidence,
           !document.1.frameLikeRisk,
           let agreement = bestAgreement(
            document: document,
            rectangles: validRectangles,
            imageSize: batch.detectionSize
           ) {
            return .selected(RectangleSelection(
                candidate: document.1.hasSoftShapeRisk ? agreement.0 : document.0,
                evidence: .crossDetectorConsensus
            ))
        }

        if let document = validDocument,
           document.0.confidence >= policy.documentHighConfidence,
           !document.1.frameLikeRisk,
           !document.1.hasSoftShapeRisk,
           validRectangles.isEmpty {
            return .selected(RectangleSelection(
                candidate: document.0,
                evidence: .highConfidenceDocument
            ))
        }

        // A geometrically credible document observation that disagrees with the
        // rectangle detector is ambiguity, not permission to choose a rectangle
        // independently. Frame-like and low-confidence document observations do
        // not block the rectangle fallback because they are weak evidence.
        let documentBlocksIndependentAcquisition = validDocument.map {
            $0.0.confidence >= policy.documentMediumConfidence && !$0.1.frameLikeRisk
        } ?? false
        let usableRectangles = validRectangles.filter {
            !$0.1.frameLikeRisk && (mode != .still || !$0.1.hasSoftShapeRisk)
        }
        if !documentBlocksIndependentAcquisition,
           let acquisition = acquireRectangle(
            usableRectangles,
            imageSize: batch.detectionSize,
            totalCount: batch.rectangles.count
           ) {
            return .selected(RectangleSelection(
                candidate: acquisition,
                evidence: .rectangleAcquisition
            ))
        }

        if !hasAnyCandidate { return .abstain(.noCandidates) }
        if validDocument == nil && validRectangles.isEmpty {
            return .abstain(.invalidCandidates)
        }
        if let document = validDocument, document.1.frameLikeRisk {
            return .abstain(.frameLikeDocument)
        }
        if validDocument != nil && !validRectangles.isEmpty {
            return .abstain(.detectorDisagreement)
        }
        if validRectangles.count >= 2 {
            return .abstain(.ambiguousRectangleAcquisition)
        }
        return .abstain(.insufficientEvidence)
    }

    func isSameTarget(
        _ lhs: RectangleCandidate,
        _ rhs: RectangleCandidate,
        imageSize: CGSize
    ) -> Bool {
        RectangleGeometry.isSameTarget(
            lhs.quadrilateral,
            rhs.quadrilateral,
            imageSize: imageSize,
            policy: policy
        )
    }

    private func isStrongAssociation(_ value: RectangleAssociation) -> Bool {
        value.score >= policy.associationMinimumScore
            && (value.polygonIoU >= policy.associationMinimumIoU
                || value.normalizedCornerDistance <= policy.associationMaximumCornerDistance)
            && value.areaRatio >= policy.associationMinimumAreaRatio
    }

    private func bestAgreement(
        document: (RectangleCandidate, RectangleValidation),
        rectangles: [(RectangleCandidate, RectangleValidation)],
        imageSize: CGSize
    ) -> (RectangleCandidate, RectangleValidation)? {
        rectangles.compactMap { rectangle -> ((RectangleCandidate, RectangleValidation), CGFloat)? in
            let iou = RectangleGeometry.polygonIoU(
                document.0.quadrilateral, rectangle.0.quadrilateral
            )
            let documentBox = RectangleGeometry.boundingBox(document.0.quadrilateral)
            let rectangleBox = RectangleGeometry.boundingBox(rectangle.0.quadrilateral)
            let referenceDiagonal = max(min(
                hypot(documentBox.width * imageSize.width, documentBox.height * imageSize.height),
                hypot(rectangleBox.width * imageSize.width, rectangleBox.height * imageSize.height)
            ), 1)
            let cornerDistance = RectangleGeometry.meanCornerDistance(
                document.0.quadrilateral,
                rectangle.0.quadrilateral,
                imageSize: imageSize
            ) / referenceDiagonal
            let documentArea = max(document.1.polygonArea, 0.000_001)
            let rectangleArea = max(rectangle.1.polygonArea, 0.000_001)
            let areaRatio = min(documentArea / rectangleArea, rectangleArea / documentArea)
            guard iou >= policy.consensusMinimumIoU
                    || (cornerDistance <= policy.consensusMaximumCornerDistance
                        && areaRatio >= policy.consensusMinimumAreaRatio) else {
                return nil
            }
            return ((rectangle.0, rectangle.1), max(iou, 1 - cornerDistance))
        }.max { $0.1 < $1.1 }?.0
    }

    private func acquireRectangle(
        _ rectangles: [(RectangleCandidate, RectangleValidation)],
        imageSize: CGSize,
        totalCount: Int
    ) -> RectangleCandidate? {
        let ranked = rectangles.map { entry in
            (entry.0, acquisitionScore(
                candidate: entry.0,
                validation: entry.1,
                imageSize: imageSize,
                totalCount: totalCount
            ))
        }.sorted { lhs, rhs in
            if abs(lhs.1 - rhs.1) > 0.000_001 { return lhs.1 > rhs.1 }
            return lhs.0.originalIndex < rhs.0.originalIndex
        }
        guard let best = ranked.first, best.1 >= policy.acquisitionMinimumScore else {
            return nil
        }
        if ranked.count > 1,
           best.1 - ranked[1].1 < policy.acquisitionMinimumMargin {
            return nil
        }
        return best.0
    }

    private func acquisitionScore(
        candidate: RectangleCandidate,
        validation: RectangleValidation,
        imageSize: CGSize,
        totalCount: Int
    ) -> CGFloat {
        let edgeRatio = validation.minimumEdgePixels / max(min(imageSize.width, imageSize.height), 1)
        let sizeUtility = smoothstep(0.08, 0.25, edgeRatio)
        let fillUtility = min(max(
            (validation.fillRatio - policy.softMinimumFillRatio)
                / (1 - policy.softMinimumFillRatio), 0
        ), 1)
        let rankUtility = 1 - CGFloat(candidate.originalIndex) / CGFloat(max(totalCount - 1, 1))
        let center = RectangleGeometry.centroid(candidate.quadrilateral)
        let centerDistance = hypot(center.x - 0.5, center.y - 0.5) / sqrt(0.5)
        let centerUtility = 1 - min(max(centerDistance, 0), 1)
        return 0.45 * sizeUtility + 0.30 * fillUtility
            + 0.15 * rankUtility + 0.10 * centerUtility
    }

    private func smoothstep(_ lower: CGFloat, _ upper: CGFloat, _ value: CGFloat) -> CGFloat {
        guard upper > lower else { return value >= upper ? 1 : 0 }
        let t = min(max((value - lower) / (upper - lower), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
