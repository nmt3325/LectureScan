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

enum RectangleDetectionQuality: Equatable {
    case preview
    case still
}

struct RectangleRequestProfile: Equatable {
    let maximumObservations: Int
    let minimumConfidence: Float
    let minimumSize: Float
    let minimumAspectRatio: Float
    let quadratureTolerance: Float

    static let preview = RectangleRequestProfile(
        maximumObservations: 15,
        minimumConfidence: 0.55,
        minimumSize: 0.16,
        minimumAspectRatio: 0.22,
        quadratureTolerance: 35
    )
    static let stillBalanced = RectangleRequestProfile(
        maximumObservations: 20,
        minimumConfidence: 0.30,
        minimumSize: 0.08,
        minimumAspectRatio: 0.12,
        quadratureTolerance: 45
    )
    static let stillRecall = RectangleRequestProfile(
        maximumObservations: 20,
        minimumConfidence: 0.10,
        minimumSize: 0.03,
        minimumAspectRatio: 0.08,
        quadratureTolerance: 45
    )
    static let enhancedRecovery = RectangleRequestProfile(
        maximumObservations: 20,
        minimumConfidence: 0.20,
        minimumSize: 0.05,
        minimumAspectRatio: 0.08,
        quadratureTolerance: 45
    )
    static let stillRecoveryProfiles: [RectangleRequestProfile] = [
        .stillBalanced,
        .stillRecall
    ]
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
    case largestAreaPreference
    case enclosingRectangleRecovery
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
    let acquisitionMinimumAreaRatioToLargest: CGFloat
    let largestRectangleDominanceRatio: CGFloat
    let largestRectangleOverrideRatio: CGFloat
    let largestRectangleOverrideMinimumArea: CGFloat
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
        acquisitionMinimumAreaRatioToLargest: 0.70,
        largestRectangleDominanceRatio: 1.25,
        largestRectangleOverrideRatio: 1.50,
        largestRectangleOverrideMinimumArea: 0.14,
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

    static func isDuplicateObservation(
        _ lhs: DetectedQuadrilateral,
        _ rhs: DetectedQuadrilateral,
        imageSize: CGSize
    ) -> Bool {
        let iou = polygonIoU(lhs, rhs)
        let lhsArea = max(lhs.approximateArea, 0.000_001)
        let rhsArea = max(rhs.approximateArea, 0.000_001)
        let areaRatio = min(lhsArea / rhsArea, rhsArea / lhsArea)
        let lhsBox = boundingBox(lhs)
        let rhsBox = boundingBox(rhs)
        let diagonal = max(min(
            hypot(lhsBox.width * imageSize.width, lhsBox.height * imageSize.height),
            hypot(rhsBox.width * imageSize.width, rhsBox.height * imageSize.height)
        ), 1)
        let cornerDistance = meanCornerDistance(lhs, rhs, imageSize: imageSize) / diagonal
        return iou >= 0.88 || (cornerDistance <= 0.04 && areaRatio >= 0.80)
    }

    static func contains(
        _ outer: DetectedQuadrilateral,
        _ inner: DetectedQuadrilateral,
        tolerance: CGFloat = 0.02
    ) -> Bool {
        let polygon = points(outer)
        let orientation = signedArea(polygon)
        guard abs(orientation) > 0.000_001 else { return false }
        return points(inner).allSatisfy { point in
            polygon.indices.allSatisfy { index in
                let start = polygon[index]
                let end = polygon[(index + 1) % polygon.count]
                let edge = subtract(end, start)
                let signedDistance = cross(edge, subtract(point, start))
                    / max(hypot(edge.x, edge.y), 0.000_001)
                return orientation > 0
                    ? signedDistance >= -tolerance
                    : signedDistance <= tolerance
            }
        }
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
        // A strip attached to three image edges is a common false positive from
        // document segmentation (for example, a desk or wall band). Confidence can
        // still be close to 1, so shape/border evidence must veto it.
        let edgeAttachedRisk = distinctSides >= 3
        let softRisk = area < policy.softMinimumArea
            || fillRatio < policy.softMinimumFillRatio
            || minimumAngle < policy.softMinimumAngleDegrees
            || maximumAngle > policy.softMaximumAngleDegrees
            || slightlyOutside
            || edgeAttachedRisk
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
        let usableRectangles = validRectangles.filter {
            !$0.1.frameLikeRisk && (mode != .still || !$0.1.hasSoftShapeRisk)
        }
        let strictAreaRectangles = usableRectangles.filter { !$0.1.hasSoftShapeRisk }

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
                if let largest = dominantLargestRectangle(
                    strictAreaRectangles,
                    comparedTo: best.1,
                    imageSize: batch.detectionSize,
                    totalCount: batch.rectangles.count
                ) {
                    return .selected(RectangleSelection(
                        candidate: largest,
                        evidence: .largestAreaPreference
                    ))
                }
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
            let consensus = document.1.hasSoftShapeRisk ? agreement : document
            if let largest = dominantLargestRectangle(
                strictAreaRectangles,
                comparedTo: consensus.1,
                imageSize: batch.detectionSize,
                totalCount: batch.rectangles.count
            ) {
                return .selected(RectangleSelection(
                    candidate: largest,
                    evidence: .largestAreaPreference
                ))
            }
            return .selected(RectangleSelection(
                candidate: consensus.0,
                evidence: .crossDetectorConsensus
            ))
        }

        if mode == .still,
           let document = validDocument,
           document.0.confidence >= policy.documentMediumConfidence,
           !document.1.frameLikeRisk,
           let enclosing = enclosingRectangle(
            around: document,
            rectangles: strictAreaRectangles
           ) {
            return .selected(RectangleSelection(
                candidate: enclosing,
                evidence: .enclosingRectangleRecovery
            ))
        }

        if let document = validDocument,
           document.0.confidence >= policy.documentHighConfidence,
           !document.1.frameLikeRisk,
           !document.1.hasSoftShapeRisk,
           (validRectangles.isEmpty
                || (mode == .still && documentContainsSubstructure(
                    document,
                    rectangles: validRectangles
                ))) {
            return .selected(RectangleSelection(
                candidate: document.0,
                evidence: .highConfidenceDocument
            ))
        }

        // A geometrically credible document observation that disagrees with the
        // rectangle detector is ambiguity, not permission to choose a rectangle
        // independently. Frame-like and low-confidence document observations do
        // not block the rectangle fallback because they are weak evidence.
        if let document = validDocument,
           document.0.confidence >= policy.documentMediumConfidence,
           !document.1.frameLikeRisk,
           let largest = dominantLargestRectangle(
            strictAreaRectangles,
            comparedTo: document.1,
            imageSize: batch.detectionSize,
            totalCount: batch.rectangles.count
           ) {
            return .selected(RectangleSelection(
                candidate: largest,
                evidence: .largestAreaPreference
            ))
        }

        let documentBlocksIndependentAcquisition = validDocument.map {
            $0.0.confidence >= policy.documentMediumConfidence && !$0.1.frameLikeRisk
        } ?? false
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

    private func documentContainsSubstructure(
        _ document: (RectangleCandidate, RectangleValidation),
        rectangles: [(RectangleCandidate, RectangleValidation)]
    ) -> Bool {
        rectangles.contains { candidate, validation in
            validation.polygonArea >= max(0.02, document.1.polygonArea * 0.08)
                && validation.polygonArea <= document.1.polygonArea * 0.92
                && !validation.frameLikeRisk
                && RectangleGeometry.contains(
                    document.0.quadrilateral,
                    candidate.quadrilateral,
                    tolerance: 0.025
                )
        }
    }

    private func enclosingRectangle(
        around document: (RectangleCandidate, RectangleValidation),
        rectangles: [(RectangleCandidate, RectangleValidation)]
    ) -> RectangleCandidate? {
        rectangles.filter { candidate, validation in
            validation.polygonArea >= max(0.08, document.1.polygonArea * 1.08)
                && !validation.frameLikeRisk
                && RectangleGeometry.contains(
                    candidate.quadrilateral,
                    document.0.quadrilateral,
                    tolerance: 0.025
                )
        }.sorted { lhs, rhs in
            if abs(lhs.1.polygonArea - rhs.1.polygonArea) > 0.000_001 {
                return lhs.1.polygonArea > rhs.1.polygonArea
            }
            return lhs.0.originalIndex < rhs.0.originalIndex
        }.first?.0
    }

    private func acquireRectangle(
        _ rectangles: [(RectangleCandidate, RectangleValidation)],
        imageSize: CGSize,
        totalCount: Int
    ) -> RectangleCandidate? {
        let distinctTargets = distinctRectangleTargets(rectangles, imageSize: imageSize)
        guard let maximumArea = distinctTargets.map({ $0.1.polygonArea }).max() else {
            return nil
        }

        if let dominant = dominantLargestRectangle(
            distinctTargets.filter { !$0.1.hasSoftShapeRisk },
            comparedTo: nil,
            imageSize: imageSize,
            totalCount: totalCount
        ) {
            return dominant
        }

        let areaTier = distinctTargets.filter {
            $0.1.polygonArea >= maximumArea * policy.acquisitionMinimumAreaRatioToLargest
        }
        let ranked = areaTier.map { entry in
            (entry.0, entry.1, acquisitionScore(
                candidate: entry.0,
                validation: entry.1,
                maximumArea: maximumArea,
                imageSize: imageSize,
                totalCount: totalCount
            ))
        }.sorted { lhs, rhs in
            if abs(lhs.2 - rhs.2) > 0.000_001 { return lhs.2 > rhs.2 }
            if abs(lhs.1.polygonArea - rhs.1.polygonArea) > 0.000_001 {
                return lhs.1.polygonArea > rhs.1.polygonArea
            }
            return lhs.0.originalIndex < rhs.0.originalIndex
        }
        guard let best = ranked.first, best.2 >= policy.acquisitionMinimumScore else {
            return nil
        }
        if ranked.count > 1,
           best.2 - ranked[1].2 < policy.acquisitionMinimumMargin {
            return nil
        }
        return best.0
    }

    /// Returns the largest geometrically safe rectangle only when it is clearly
    /// larger than every other distinct target. When replacing document or prior
    /// evidence, the candidate must also cover enough of the frame and exceed the
    /// referenced target by a larger ratio. This keeps a near-tie ambiguous while
    /// preventing a centered, high-ranked small rectangle from winning.
    private func dominantLargestRectangle(
        _ rectangles: [(RectangleCandidate, RectangleValidation)],
        comparedTo reference: RectangleValidation?,
        imageSize: CGSize,
        totalCount: Int
    ) -> RectangleCandidate? {
        let targets = distinctRectangleTargets(rectangles, imageSize: imageSize)
        guard let best = targets.first else { return nil }
        let bestArea = best.1.polygonArea

        if targets.count > 1,
           bestArea < targets[1].1.polygonArea * policy.largestRectangleDominanceRatio {
            return nil
        }
        if let reference {
            guard bestArea >= policy.largestRectangleOverrideMinimumArea,
                  bestArea >= reference.polygonArea * policy.largestRectangleOverrideRatio else {
                return nil
            }
        }
        let score = acquisitionScore(
            candidate: best.0,
            validation: best.1,
            maximumArea: bestArea,
            imageSize: imageSize,
            totalCount: totalCount
        )
        guard score >= policy.acquisitionMinimumScore else { return nil }
        return best.0
    }

    private func distinctRectangleTargets(
        _ rectangles: [(RectangleCandidate, RectangleValidation)],
        imageSize: CGSize
    ) -> [(RectangleCandidate, RectangleValidation)] {
        let ordered = rectangles.sorted { lhs, rhs in
            if abs(lhs.1.polygonArea - rhs.1.polygonArea) > 0.000_001 {
                return lhs.1.polygonArea > rhs.1.polygonArea
            }
            return lhs.0.originalIndex < rhs.0.originalIndex
        }
        return ordered.reduce(into: []) { result, entry in
            let duplicatesExistingTarget = result.contains { existing in
                RectangleGeometry.isDuplicateObservation(
                    existing.0.quadrilateral,
                    entry.0.quadrilateral,
                    imageSize: imageSize
                )
            }
            if !duplicatesExistingTarget { result.append(entry) }
        }
    }

    private func acquisitionScore(
        candidate: RectangleCandidate,
        validation: RectangleValidation,
        maximumArea: CGFloat,
        imageSize: CGSize,
        totalCount: Int
    ) -> CGFloat {
        let edgeRatio = validation.minimumEdgePixels / max(min(imageSize.width, imageSize.height), 1)
        let sizeUtility = smoothstep(0.08, 0.25, edgeRatio)
        let relativeAreaUtility = min(max(
            validation.polygonArea / max(maximumArea, 0.000_001), 0
        ), 1)
        let absoluteAreaUtility = smoothstep(0.03, 0.40, validation.polygonArea)
        let fillUtility = min(max(
            (validation.fillRatio - policy.softMinimumFillRatio)
                / (1 - policy.softMinimumFillRatio), 0
        ), 1)
        let rankUtility = min(max(
            1 - CGFloat(candidate.originalIndex) / CGFloat(max(totalCount - 1, 1)), 0
        ), 1)
        let center = RectangleGeometry.centroid(candidate.quadrilateral)
        let centerDistance = hypot(center.x - 0.5, center.y - 0.5) / sqrt(0.5)
        let centerUtility = 1 - min(max(centerDistance, 0), 1)
        return 0.35 * relativeAreaUtility + 0.25 * absoluteAreaUtility
            + 0.15 * sizeUtility + 0.10 * fillUtility
            + 0.05 * rankUtility + 0.10 * centerUtility
    }

    private func smoothstep(_ lower: CGFloat, _ upper: CGFloat, _ value: CGFloat) -> CGFloat {
        guard upper > lower else { return value >= upper ? 1 : 0 }
        let t = min(max((value - lower) / (upper - lower), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
