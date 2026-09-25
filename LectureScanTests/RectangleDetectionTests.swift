import CoreGraphics
import CoreImage
import XCTest
@testable import LectureScan

final class RectangleResolverTests: XCTestCase {
    private let imageSize = CGSize(width: 1_024, height: 768)
    private let resolver = RectangleResolver()

    func testValidatorFlagsFrameLikeDocumentAndResolverAbstains() {
        let document = candidate(
            DetectedQuadrilateral.fullFrame(inset: 0.004),
            detector: .documentSegmentation,
            confidence: 0.99
        )

        let validation = RectangleValidator().validate(document, imageSize: imageSize)
        let resolution = resolver.resolve(
            batch(document: document),
            prior: nil,
            mode: .still
        )

        XCTAssertTrue(validation.isHardValid)
        XCTAssertGreaterThanOrEqual(validation.distinctBorderSides, 3)
        XCTAssertTrue(validation.frameLikeRisk)
        XCTAssertEqual(resolution, .abstain(.frameLikeDocument))
    }

    func testMediumConfidenceDocumentUsesSecondRectangleForConsensus() throws {
        let target = quadrilateral(left: 0.34, bottom: 0.14, right: 0.76, top: 0.79)
        let document = candidate(
            target,
            detector: .documentSegmentation,
            confidence: 0.50
        )
        let distractor = candidate(
            quadrilateral(left: 0.02, bottom: 0.08, right: 0.31, top: 0.94),
            detector: .rectangle,
            index: 0
        )
        let agreeingRectangle = candidate(
            quadrilateral(left: 0.35, bottom: 0.13, right: 0.75, top: 0.78),
            detector: .rectangle,
            index: 1
        )

        let selection = try XCTUnwrap(resolver.resolve(
            batch(document: document, rectangles: [distractor, agreeingRectangle]),
            prior: nil,
            mode: .still
        ).selection)

        XCTAssertEqual(selection.evidence, .crossDetectorConsensus)
        XCTAssertEqual(selection.candidate, document)
    }

    func testCredibleDisagreeingDocumentBlocksIndependentRectangleAcquisition() {
        let document = candidate(
            quadrilateral(left: 0.05, bottom: 0.10, right: 0.36, top: 0.90),
            detector: .documentSegmentation,
            confidence: 0.50
        )
        let rectangle = candidate(
            quadrilateral(left: 0.58, bottom: 0.14, right: 0.91, top: 0.86),
            detector: .rectangle,
            index: 0
        )

        let resolution = resolver.resolve(
            batch(document: document, rectangles: [rectangle]),
            prior: nil,
            mode: .still
        )

        XCTAssertEqual(resolution, .abstain(.detectorDisagreement))
    }

    func testPriorAssociationWinsOverRectangleRank() throws {
        let distractor = candidate(
            quadrilateral(left: 0.06, bottom: 0.10, right: 0.44, top: 0.88),
            detector: .rectangle,
            index: 0
        )
        let target = candidate(
            quadrilateral(left: 0.56, bottom: 0.16, right: 0.90, top: 0.82),
            detector: .rectangle,
            index: 1
        )
        let prior = RectanglePrior(
            quadrilateral: quadrilateral(left: 0.55, bottom: 0.15, right: 0.89, top: 0.83),
            detector: .rectangle
        )

        let selection = try XCTUnwrap(resolver.resolve(
            batch(rectangles: [distractor, target]),
            prior: prior,
            mode: .liveTracking
        ).selection)

        XCTAssertEqual(selection.evidence, .priorAssociation)
        XCTAssertEqual(selection.candidate, target)
    }

    func testPriorIsNeverReturnedAsAStandaloneCrop() {
        let prior = RectanglePrior(
            quadrilateral: quadrilateral(
                left: 0.08,
                bottom: 0.16,
                right: 0.42,
                top: 0.84
            ),
            detector: .rectangle
        )

        XCTAssertEqual(
            resolver.resolve(batch(), prior: prior, mode: .still),
            .abstain(.noCandidates)
        )
    }

    func testGeometryMetricsRemainStableAcrossPortraitAndLandscapeSizes() {
        let original = quadrilateral(left: 0.18, bottom: 0.14, right: 0.82, top: 0.86)
        let moved = quadrilateral(left: 0.19, bottom: 0.15, right: 0.83, top: 0.87)
        let landscape = RectangleGeometry.association(
            prior: original,
            candidate: moved,
            imageSize: CGSize(width: 1_024, height: 768)
        )
        let portrait = RectangleGeometry.association(
            prior: original,
            candidate: moved,
            imageSize: CGSize(width: 1_080, height: 1_920)
        )

        XCTAssertEqual(
            RectangleGeometry.polygonIoU(original, moved),
            RectangleGeometry.polygonIoU(moved, original),
            accuracy: 0.000_001
        )
        XCTAssertTrue(RectangleGeometry.isSameTarget(
            original,
            moved,
            imageSize: CGSize(width: 1_024, height: 768),
            policy: .productionSeed
        ))
        XCTAssertTrue(RectangleGeometry.isSameTarget(
            original,
            moved,
            imageSize: CGSize(width: 1_080, height: 1_920),
            policy: .productionSeed
        ))
        XCTAssertLessThan(abs(landscape.score - portrait.score), 0.02)
    }

    func testAmbiguousRectangleAcquisitionAbstains() {
        let first = candidate(
            quadrilateral(left: 0.10, bottom: 0.18, right: 0.46, top: 0.82),
            detector: .rectangle,
            index: 0
        )
        let second = candidate(
            quadrilateral(left: 0.54, bottom: 0.18, right: 0.90, top: 0.82),
            detector: .rectangle,
            index: 0
        )

        XCTAssertEqual(
            resolver.resolve(
                batch(rectangles: [first, second]),
                prior: nil,
                mode: .still
            ),
            .abstain(.ambiguousRectangleAcquisition)
        )
    }

    private func batch(
        document: RectangleCandidate? = nil,
        rectangles: [RectangleCandidate] = []
    ) -> RectangleCandidateBatch {
        RectangleCandidateBatch(
            sourceSize: imageSize,
            detectionSize: imageSize,
            document: document,
            rectangles: rectangles
        )
    }

    private func candidate(
        _ quadrilateral: DetectedQuadrilateral,
        detector: RectangleDetectorKind,
        confidence: CGFloat = 1,
        index: Int = 0
    ) -> RectangleCandidate {
        RectangleCandidate(
            quadrilateral: quadrilateral,
            detector: detector,
            confidence: confidence,
            originalIndex: index
        )
    }

    private func quadrilateral(
        left: CGFloat,
        bottom: CGFloat,
        right: CGFloat,
        top: CGFloat
    ) -> DetectedQuadrilateral {
        DetectedQuadrilateral(
            topLeft: CGPoint(x: left, y: top),
            topRight: CGPoint(x: right, y: top),
            bottomLeft: CGPoint(x: left, y: bottom),
            bottomRight: CGPoint(x: right, y: bottom)
        )
    }
}

final class LiveRectangleTrackerTests: XCTestCase {
    private let imageSize = CGSize(width: 1_024, height: 768)

    func testLocksAfterTwoStableFrames() throws {
        var tracker = LiveRectangleTracker()
        let target = candidate(quadrilateral(left: 0.22, bottom: 0.14, right: 0.78, top: 0.86))

        let first = tracker.consume(batch(target), at: 0)
        let second = tracker.consume(batch(target), at: 0.10)

        XCTAssertEqual(first.state, .ambiguous)
        XCTAssertNil(first.rawTrustedCandidate)
        XCTAssertEqual(second.state, .rectangleLocked)
        XCTAssertEqual(second.rawTrustedCandidate, target)
        XCTAssertEqual(second.displayedQuadrilateral, target.quadrilateral)
    }

    func testTargetSwitchRequiresTwoFramesAndDoesNotInterpolateAcrossTargets() throws {
        var tracker = LiveRectangleTracker()
        let firstTarget = candidate(
            quadrilateral(left: 0.08, bottom: 0.18, right: 0.43, top: 0.82)
        )
        let secondTarget = candidate(
            quadrilateral(left: 0.57, bottom: 0.16, right: 0.92, top: 0.84)
        )

        _ = tracker.consume(batch(firstTarget), at: 0)
        let lockedFirst = tracker.consume(batch(firstTarget), at: 0.10)
        let pendingSwitch = tracker.consume(batch(secondTarget), at: 0.20)
        let switched = tracker.consume(batch(secondTarget), at: 0.30)

        XCTAssertEqual(lockedFirst.state, .rectangleLocked)
        XCTAssertEqual(pendingSwitch.state, .ambiguous)
        XCTAssertEqual(pendingSwitch.displayedQuadrilateral, firstTarget.quadrilateral)
        XCTAssertEqual(switched.state, .rectangleLocked)
        XCTAssertTrue(switched.didChangeTarget)
        XCTAssertEqual(switched.rawTrustedCandidate, secondTarget)
        XCTAssertEqual(switched.displayedQuadrilateral, secondTarget.quadrilateral)
    }

    func testSchedulerUsesDualProbeForRectangleLock() {
        var tracker = LiveRectangleTracker()
        let target = candidate(quadrilateral(left: 0.22, bottom: 0.14, right: 0.78, top: 0.86))

        XCTAssertEqual(tracker.nextRequest(at: 0), .dual)
        XCTAssertNil(tracker.nextRequest(at: 0.11))
        tracker.requestDidFinish(at: 0.04)
        _ = tracker.consume(batch(target), at: 0.04)
        _ = tracker.consume(batch(target), at: 0.14)

        XCTAssertEqual(tracker.nextRequest(at: 0.20), .rectangle)
        tracker.requestDidFinish(at: 0.22)
        XCTAssertEqual(tracker.nextRequest(at: 0.60), .dual)
    }

    func testRepeatedAmbiguityTransitionsToLostAndCanRecover() {
        var tracker = LiveRectangleTracker()
        let empty = RectangleCandidateBatch(
            sourceSize: imageSize,
            detectionSize: imageSize,
            document: nil,
            rectangles: []
        )
        let target = candidate(quadrilateral(left: 0.22, bottom: 0.14, right: 0.78, top: 0.86))

        _ = tracker.consume(empty, at: 0)
        _ = tracker.consume(empty, at: 0.10)
        let lost = tracker.consume(empty, at: 0.20)
        let recovering = tracker.consume(batch(target), at: 0.30)
        let recovered = tracker.consume(batch(target), at: 0.40)

        XCTAssertEqual(lost.state, .lost)
        XCTAssertEqual(recovering.state, .ambiguous)
        XCTAssertEqual(recovered.state, .rectangleLocked)
    }

    func testOldGenerationCompletionCannotMutateTrackerState() {
        var tracker = GenerationScopedLiveRectangleTracker()
        let target = candidate(
            quadrilateral(left: 0.22, bottom: 0.14, right: 0.78, top: 0.86)
        )

        XCTAssertTrue(tracker.synchronize(generation: 1, at: 0))
        XCTAssertEqual(tracker.nextRequest(at: 0), .dual)
        XCTAssertTrue(tracker.synchronize(generation: 2, at: 0.05))

        XCTAssertNil(tracker.complete(
            batch(target),
            requestGeneration: 1,
            at: 0.10
        ))
        XCTAssertEqual(tracker.state, .coldStart)

        _ = tracker.complete(batch(target), requestGeneration: 2, at: 0.15)
        let recovered = tracker.complete(
            batch(target),
            requestGeneration: 2,
            at: 0.25
        )
        XCTAssertEqual(recovered?.state, .rectangleLocked)
    }

    func testPersistentDetectorDisagreementExpiresOverlayAndRecovers() {
        var tracker = LiveRectangleTracker()
        let original = candidate(
            quadrilateral(left: 0.05, bottom: 0.16, right: 0.35, top: 0.84)
        )
        let replacement = candidate(
            quadrilateral(left: 0.64, bottom: 0.14, right: 0.94, top: 0.86)
        )
        let document = RectangleCandidate(
            quadrilateral: quadrilateral(
                left: 0.37,
                bottom: 0.10,
                right: 0.59,
                top: 0.92
            ),
            detector: .documentSegmentation,
            confidence: 0.55,
            originalIndex: 0
        )
        let disagreement = RectangleCandidateBatch(
            sourceSize: imageSize,
            detectionSize: imageSize,
            document: document,
            rectangles: [replacement]
        )

        _ = tracker.consume(batch(original), at: 0)
        _ = tracker.consume(batch(original), at: 0.10)
        let held = tracker.consume(disagreement, at: 0.20)
        _ = tracker.consume(disagreement, at: 0.30)
        _ = tracker.consume(disagreement, at: 0.40)
        let lost = tracker.consume(disagreement, at: 0.50)
        let pendingRecovery = tracker.consume(batch(replacement), at: 0.60)
        let recovered = tracker.consume(batch(replacement), at: 0.70)

        XCTAssertEqual(held.state, .ambiguous)
        XCTAssertEqual(held.displayedQuadrilateral, original.quadrilateral)
        XCTAssertEqual(lost.state, .lost)
        XCTAssertNil(lost.displayedQuadrilateral)
        XCTAssertEqual(pendingRecovery.state, .ambiguous)
        XCTAssertEqual(recovered.state, .rectangleLocked)
        XCTAssertEqual(recovered.rawTrustedCandidate, replacement)
    }

    func testCapturePriorRequiresMatchingFreshGeometry() {
        let target = candidate(quadrilateral(left: 0.22, bottom: 0.14, right: 0.78, top: 0.86))
        let source = RectangleFrameMetadata(
            sequence: 10,
            timestamp: 1.0,
            sourceSize: imageSize,
            geometryGeneration: 4,
            hardwareZoomFactor: 2.0,
            rotationAngle: 90
        )
        let snapshot = TrustedRectangleSnapshot(rawCandidate: target, frame: source)
        let eligible = RectangleFrameMetadata(
            sequence: 11,
            timestamp: 1.15,
            sourceSize: imageSize,
            geometryGeneration: 4,
            hardwareZoomFactor: 2.0,
            rotationAngle: 90
        )
        let stale = RectangleFrameMetadata(
            sequence: 12,
            timestamp: 1.21,
            sourceSize: imageSize,
            geometryGeneration: 4,
            hardwareZoomFactor: 2.0,
            rotationAngle: 90
        )
        let changedGeometry = RectangleFrameMetadata(
            sequence: 11,
            timestamp: 1.15,
            sourceSize: imageSize,
            geometryGeneration: 5,
            hardwareZoomFactor: 2.0,
            rotationAngle: 90
        )
        let changedZoom = RectangleFrameMetadata(
            sequence: 11,
            timestamp: 1.15,
            sourceSize: imageSize,
            geometryGeneration: 4,
            hardwareZoomFactor: 2.1,
            rotationAngle: 90
        )

        XCTAssertNotNil(RectangleCapturePriorEligibility.prior(from: snapshot, for: eligible))
        XCTAssertNil(RectangleCapturePriorEligibility.prior(from: snapshot, for: stale))
        XCTAssertNil(RectangleCapturePriorEligibility.prior(from: snapshot, for: changedGeometry))
        XCTAssertNil(RectangleCapturePriorEligibility.prior(from: snapshot, for: changedZoom))
    }

    private func batch(_ candidate: RectangleCandidate) -> RectangleCandidateBatch {
        RectangleCandidateBatch(
            sourceSize: imageSize,
            detectionSize: imageSize,
            document: nil,
            rectangles: [candidate]
        )
    }

    private func candidate(_ quadrilateral: DetectedQuadrilateral) -> RectangleCandidate {
        RectangleCandidate(
            quadrilateral: quadrilateral,
            detector: .rectangle,
            confidence: 1,
            originalIndex: 0
        )
    }

    private func quadrilateral(
        left: CGFloat,
        bottom: CGFloat,
        right: CGFloat,
        top: CGFloat
    ) -> DetectedQuadrilateral {
        DetectedQuadrilateral(
            topLeft: CGPoint(x: left, y: top),
            topRight: CGPoint(x: right, y: top),
            bottomLeft: CGPoint(x: left, y: bottom),
            bottomRight: CGPoint(x: right, y: bottom)
        )
    }
}

final class RectangleDetectionIntegrationTests: XCTestCase {
    private struct RecordedObservation: Decodable {
        struct Point: Decodable {
            let x: CGFloat
            let y: CGFloat

            var cgPoint: CGPoint { CGPoint(x: x, y: y) }
        }

        let confidence: CGFloat
        let topLeft: Point
        let topRight: Point
        let bottomRight: Point
        let bottomLeft: Point

        func candidate(
            detector: RectangleDetectorKind,
            index: Int,
            sourceSize: CGSize
        ) -> RectangleCandidate {
            RectangleCandidate(
                quadrilateral: DetectedQuadrilateral(
                    topLeft: topLeft.cgPoint,
                    topRight: topRight.cgPoint,
                    bottomLeft: bottomLeft.cgPoint,
                    bottomRight: bottomRight.cgPoint,
                    sourceSize: sourceSize
                ),
                detector: detector,
                confidence: confidence,
                originalIndex: index
            )
        }
    }

    private struct RecordedCandidates: Decodable {
        let width: CGFloat
        let height: CGFloat
        let document: RecordedObservation?
        let rectangles: [RecordedObservation]

        var batch: RectangleCandidateBatch {
            let size = CGSize(width: width, height: height)
            return RectangleCandidateBatch(
                sourceSize: size,
                detectionSize: size,
                document: document?.candidate(
                    detector: .documentSegmentation,
                    index: 0,
                    sourceSize: size
                ),
                rectangles: rectangles.enumerated().map {
                    $0.element.candidate(
                        detector: .rectangle,
                        index: $0.offset,
                        sourceSize: size
                    )
                }
            )
        }
    }

    private struct Fixture: Decodable {
        struct Quad: Decodable {
            let topLeft: [CGFloat]
            let topRight: [CGFloat]
            let bottomRight: [CGFloat]
            let bottomLeft: [CGFloat]
        }

        let width: CGFloat
        let height: CGFloat
        let quad: Quad

        var expected: DetectedQuadrilateral {
            DetectedQuadrilateral(
                topLeft: point(quad.topLeft),
                topRight: point(quad.topRight),
                bottomLeft: point(quad.bottomLeft),
                bottomRight: point(quad.bottomRight),
                sourceSize: CGSize(width: width, height: height)
            )
        }

        private func point(_ values: [CGFloat]) -> CGPoint {
            CGPoint(x: values[0], y: values[1])
        }
    }

    private let processor = DocumentProcessor()
    private let resolver = RectangleResolver()

    func testLargerDistractorSelectsTheDocumentTargetWhenSegmentationIsAvailable() throws {
        let result = try detect("paper_with_larger_distractor")

        #if targetEnvironment(simulator)
        // Document segmentation is device-oriented and its Simulator output is
        // nondeterministic (missing, full-frame, or low-quality across runs).
        // Exercise the live request path for safety here; assert strict target
        // selection against recorded device-capable Vision output below.
        assertAcceptableOrAbstained(result.resolution, expected: result.expected)
        #else
        let selected = try XCTUnwrap(result.resolution.selection?.candidate.quadrilateral)
        assertGood(selected, expected: result.expected)
        #endif
    }

    func testRecordedDeviceCapableVisionCandidatesMeetAcceptanceCriteria() throws {
        let candidates = try recordedCandidates()
        for name in [
            "blackboard_wide",
            "paper_small_distant",
            "paper_with_larger_distractor"
        ] {
            let fixture = try fixture(named: name)
            let recorded = try XCTUnwrap(candidates[name])
            let resolution = resolver.resolve(
                recorded.batch,
                prior: nil,
                mode: .still
            )
            if name == "paper_with_larger_distractor" {
                let selected = try XCTUnwrap(
                    resolution.selection?.candidate.quadrilateral,
                    "The document/second-rectangle consensus must beat the larger distractor"
                )
                assertGood(selected, expected: fixture.expected)
            } else {
                assertAcceptableOrAbstained(resolution, expected: fixture.expected)
            }
        }
    }

    func testWideBlackboardNeverProducesHarmfulAutomaticCrop() throws {
        let result = try detect("blackboard_wide")

        assertAcceptableOrAbstained(result.resolution, expected: result.expected)
    }

    func testSmallDistantPaperNeverProducesHarmfulAutomaticCrop() throws {
        let result = try detect("paper_small_distant")

        assertAcceptableOrAbstained(result.resolution, expected: result.expected)
    }

    private func detect(_ name: String) throws -> (
        resolution: RectangleResolution,
        expected: DetectedQuadrilateral,
        batch: RectangleCandidateBatch
    ) {
        let fixture = try fixture(named: name)
        let bundle = Bundle(for: Self.self)
        let imageURL = try XCTUnwrap(
            bundle.url(forResource: name, withExtension: "png", subdirectory: "Fixtures")
                ?? bundle.url(forResource: name, withExtension: "png")
        )
        let image = try XCTUnwrap(CIImage(contentsOf: imageURL))
        let batch = try processor.detectCandidates(in: image, requestSet: .dual)
        return (
            resolver.resolve(batch, prior: nil, mode: .still),
            fixture.expected,
            batch
        )
    }

    private func recordedCandidates() throws -> [String: RecordedCandidates] {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(
                forResource: "vision_candidates",
                withExtension: "json",
                subdirectory: "Fixtures"
            ) ?? bundle.url(forResource: "vision_candidates", withExtension: "json")
        )
        return try JSONDecoder().decode(
            [String: RecordedCandidates].self,
            from: Data(contentsOf: url)
        )
    }

    private func fixture(named name: String) throws -> Fixture {
        let bundle = Bundle(for: Self.self)
        let manifestURL = try XCTUnwrap(
            bundle.url(
                forResource: "ground_truth",
                withExtension: "json",
                subdirectory: "Fixtures"
            ) ?? bundle.url(forResource: "ground_truth", withExtension: "json")
        )
        let fixtures = try JSONDecoder().decode(
            [String: Fixture].self,
            from: Data(contentsOf: manifestURL)
        )
        return try XCTUnwrap(fixtures[name])
    }

    private func assertGood(
        _ actual: DetectedQuadrilateral,
        expected: DetectedQuadrilateral,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertGreaterThanOrEqual(
            RectangleGeometry.polygonIoU(actual, expected),
            0.80,
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            cornerError(actual, expected),
            0.06,
            file: file,
            line: line
        )
    }

    private func assertAcceptableOrAbstained(
        _ resolution: RectangleResolution,
        expected: DetectedQuadrilateral,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let actual = resolution.selection?.candidate.quadrilateral else { return }
        XCTAssertGreaterThanOrEqual(
            RectangleGeometry.polygonIoU(actual, expected),
            0.75,
            "Selected crop must be accurate enough to avoid destructive auto-cropping",
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            cornerError(actual, expected),
            0.08,
            file: file,
            line: line
        )
    }

    private func cornerError(
        _ lhs: DetectedQuadrilateral,
        _ rhs: DetectedQuadrilateral
    ) -> CGFloat {
        zip(RectangleGeometry.points(lhs), RectangleGeometry.points(rhs))
            .reduce(CGFloat.zero) { partial, pair in
                partial + hypot(pair.0.x - pair.1.x, pair.0.y - pair.1.y)
            } / 4
    }
}
