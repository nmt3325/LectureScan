import CoreGraphics
import Foundation

enum LiveDetectionState: Equatable {
    case coldStart
    case documentLocked
    case rectangleLocked
    case ambiguous
    case lost
}

struct LiveRectangleUpdate: Equatable {
    let state: LiveDetectionState
    let displayedQuadrilateral: DetectedQuadrilateral?
    let rawTrustedCandidate: RectangleCandidate?
    let didChangeTarget: Bool
}

struct LiveRectangleTracker {
    private struct Pending: Equatable {
        var selection: RectangleSelection
        var count: Int
        var firstSeenAt: CFTimeInterval
    }

    private(set) var state: LiveDetectionState = .coldStart
    private let policy: RectangleDetectionPolicy
    private let resolver: RectangleResolver
    private var lockedCandidate: RectangleCandidate?
    private var displayedQuadrilateral: DetectedQuadrilateral?
    private var pending: Pending?
    private var stateEnteredAt: CFTimeInterval?
    private var lastTrustedAt: CFTimeInterval?
    private var lastDocumentProbeAt: CFTimeInterval = -.infinity
    private var lastRequestStartedAt: CFTimeInterval = -.infinity
    private var lastRequestFinishedAt: CFTimeInterval = -.infinity
    private var lastConsumedAt: CFTimeInterval?
    private var dualEvaluations = 0
    private var previousLockedState: LiveDetectionState?
    private var lastSourceAspect: CGFloat?

    init(policy: RectangleDetectionPolicy = .productionSeed) {
        self.policy = policy
        resolver = RectangleResolver(policy: policy)
    }

    mutating func nextRequest(at time: CFTimeInterval) -> RectangleRequestSet? {
        if let lastConsumedAt,
           time - lastConsumedAt > policy.longFrameGap,
           state != .coldStart,
           state != .lost {
            reset(at: time)
        }
        let request = plannedRequest(at: time)
        let spacing = request == .dual
            ? policy.dualRequestSpacing
            : policy.singleRequestSpacing
        let nextEligible = max(
            lastRequestStartedAt + spacing,
            lastRequestFinishedAt + policy.minimumPostCompletionGap
        )
        guard time >= nextEligible else { return nil }
        lastRequestStartedAt = time
        if request == .dual { lastDocumentProbeAt = time }
        return request
    }

    mutating func requestDidFinish(at time: CFTimeInterval) {
        lastRequestFinishedAt = time
    }

    mutating func consume(
        _ batch: RectangleCandidateBatch,
        at time: CFTimeInterval
    ) -> LiveRectangleUpdate {
        if stateEnteredAt == nil { stateEnteredAt = time }
        let aspect = batch.sourceSize.width / max(batch.sourceSize.height, 1)
        if let lastSourceAspect,
           abs(log(aspect / max(lastSourceAspect, 0.000_001))) > 0.015 {
            reset(at: time)
        }
        lastSourceAspect = aspect
        lastConsumedAt = time

        let prior = lockedCandidate.map {
            RectanglePrior(quadrilateral: $0.quadrilateral, detector: $0.detector)
        }
        let mode: RectangleResolutionMode = lockedCandidate == nil
            ? .liveAcquisition
            : .liveTracking
        let selection = resolver.resolve(batch, prior: prior, mode: mode).selection

        switch state {
        case .coldStart:
            dualEvaluations += 1
            if let selection {
                pending = Pending(selection: selection, count: 1, firstSeenAt: time)
                state = .ambiguous
                stateEnteredAt = time
                previousLockedState = nil
            } else if shouldExpireAmbiguity(at: time) {
                enterLost(at: time)
            }
            return output(at: time, didChangeTarget: false)

        case .documentLocked, .rectangleLocked:
            guard let lockedCandidate else {
                enterLost(at: time)
                return output(at: time, didChangeTarget: false)
            }
            if let selection,
               resolver.isSameTarget(
                lockedCandidate,
                selection.candidate,
                imageSize: batch.detectionSize
               ),
               selection.candidate.detector == lockedCandidate.detector {
                acceptSameTarget(selection.candidate, at: time)
                return output(at: time, didChangeTarget: false)
            }
            previousLockedState = state
            state = .ambiguous
            stateEnteredAt = time
            dualEvaluations = 0
            pending = selection.map { Pending(selection: $0, count: 1, firstSeenAt: time) }
            return output(at: time, didChangeTarget: false)

        case .ambiguous:
            dualEvaluations += 1
            if let lockedCandidate,
               let selection,
               resolver.isSameTarget(
                lockedCandidate,
                selection.candidate,
                imageSize: batch.detectionSize
               ),
               selection.candidate.detector == lockedCandidate.detector {
                acceptSameTarget(selection.candidate, at: time)
                state = previousLockedState ?? lockedState(for: selection.candidate.detector)
                clearPending()
                return output(at: time, didChangeTarget: false)
            }

            if let selection {
                let continued: Bool
                if let pending,
                   time - pending.firstSeenAt <= policy.pendingTTL {
                    continued = resolver.isSameTarget(
                        pending.selection.candidate,
                        selection.candidate,
                        imageSize: batch.detectionSize
                    ) && pending.selection.candidate.detector == selection.candidate.detector
                } else {
                    continued = false
                }
                if continued, var value = pending {
                    value.count += 1
                    value.selection = selection
                    pending = value
                } else {
                    pending = Pending(selection: selection, count: 1, firstSeenAt: time)
                }
                if let pending, pending.count >= 2 {
                    let changedTarget = lockedCandidate.map {
                        !resolver.isSameTarget(
                            $0,
                            pending.selection.candidate,
                            imageSize: batch.detectionSize
                        )
                    } ?? false
                    lock(
                        pending.selection.candidate,
                        imageSize: batch.detectionSize,
                        at: time,
                        changedTarget: changedTarget
                    )
                    return output(at: time, didChangeTarget: changedTarget)
                }
            }

            if shouldExpireAmbiguity(at: time) { enterLost(at: time) }
            return output(at: time, didChangeTarget: false)

        case .lost:
            if let selection {
                pending = Pending(selection: selection, count: 1, firstSeenAt: time)
                state = .ambiguous
                stateEnteredAt = time
                dualEvaluations = 0
                previousLockedState = nil
            }
            return output(at: time, didChangeTarget: false)
        }
    }

    mutating func reset(at time: CFTimeInterval) {
        state = .coldStart
        lockedCandidate = nil
        displayedQuadrilateral = nil
        pending = nil
        stateEnteredAt = time
        lastTrustedAt = nil
        dualEvaluations = 0
        previousLockedState = nil
        lastSourceAspect = nil
    }

    private func plannedRequest(at time: CFTimeInterval) -> RectangleRequestSet {
        switch state {
        case .coldStart, .ambiguous:
            return .dual
        case .documentLocked:
            return .document
        case .rectangleLocked, .lost:
            return time - lastDocumentProbeAt >= policy.documentProbeInterval
                ? .dual
                : .rectangle
        }
    }

    private mutating func acceptSameTarget(
        _ candidate: RectangleCandidate,
        at time: CFTimeInterval
    ) {
        lockedCandidate = candidate
        displayedQuadrilateral = displayedQuadrilateral?.interpolated(
            toward: candidate.quadrilateral,
            amount: policy.smoothingAmount
        ) ?? candidate.quadrilateral
        lastTrustedAt = time
        pending = nil
        dualEvaluations = 0
    }

    private mutating func lock(
        _ candidate: RectangleCandidate,
        imageSize: CGSize,
        at time: CFTimeInterval,
        changedTarget: Bool
    ) {
        let sameAsOld = lockedCandidate.map {
            resolver.isSameTarget($0, candidate, imageSize: imageSize)
        } ?? false
        lockedCandidate = candidate
        if sameAsOld && !changedTarget {
            displayedQuadrilateral = displayedQuadrilateral?.interpolated(
                toward: candidate.quadrilateral,
                amount: policy.smoothingAmount
            ) ?? candidate.quadrilateral
        } else {
            displayedQuadrilateral = candidate.quadrilateral
        }
        state = lockedState(for: candidate.detector)
        lastTrustedAt = time
        clearPending()
    }

    private func lockedState(for detector: RectangleDetectorKind) -> LiveDetectionState {
        detector == .documentSegmentation ? .documentLocked : .rectangleLocked
    }

    private func shouldExpireAmbiguity(at time: CFTimeInterval) -> Bool {
        dualEvaluations >= policy.maximumDualEvaluations
            || time - (stateEnteredAt ?? time) >= policy.ambiguousDeadline
    }

    private mutating func enterLost(at time: CFTimeInterval) {
        state = .lost
        lockedCandidate = nil
        displayedQuadrilateral = nil
        lastTrustedAt = nil
        stateEnteredAt = time
        clearPending()
    }

    private mutating func clearPending() {
        pending = nil
        dualEvaluations = 0
        previousLockedState = nil
    }

    private func output(at time: CFTimeInterval, didChangeTarget: Bool) -> LiveRectangleUpdate {
        let isFresh = lastTrustedAt.map { time - $0 <= policy.overlayHoldDuration } ?? false
        return LiveRectangleUpdate(
            state: state,
            displayedQuadrilateral: isFresh ? displayedQuadrilateral : nil,
            rawTrustedCandidate: isFresh ? lockedCandidate : nil,
            didChangeTarget: didChangeTarget
        )
    }
}

/// Owns live-tracker state for exactly one camera geometry generation.
/// Results from an older generation are rejected before they can change pending
/// counts, smoothing, lock state, or the trusted capture prior.
struct GenerationScopedLiveRectangleTracker {
    private var tracker: LiveRectangleTracker
    private(set) var generation: UInt64?

    init(policy: RectangleDetectionPolicy = .productionSeed) {
        tracker = LiveRectangleTracker(policy: policy)
    }

    var state: LiveDetectionState { tracker.state }

    @discardableResult
    mutating func synchronize(
        generation newGeneration: UInt64,
        at time: CFTimeInterval
    ) -> Bool {
        guard generation != newGeneration else { return false }
        tracker.reset(at: time)
        generation = newGeneration
        return true
    }

    mutating func nextRequest(at time: CFTimeInterval) -> RectangleRequestSet? {
        tracker.nextRequest(at: time)
    }

    mutating func complete(
        _ batch: RectangleCandidateBatch,
        requestGeneration: UInt64,
        at time: CFTimeInterval
    ) -> LiveRectangleUpdate? {
        guard generation == requestGeneration else { return nil }
        tracker.requestDidFinish(at: time)
        return tracker.consume(batch, at: time)
    }
}

struct RectangleFrameMetadata: Equatable {
    let sequence: UInt64
    let timestamp: CFTimeInterval
    let sourceSize: CGSize
    let geometryGeneration: UInt64
    let hardwareZoomFactor: CGFloat
    let rotationAngle: CGFloat
}

struct TrustedRectangleSnapshot: Equatable {
    let rawCandidate: RectangleCandidate
    let frame: RectangleFrameMetadata
}

enum RectangleCapturePriorEligibility {
    static func prior(
        from snapshot: TrustedRectangleSnapshot?,
        for frame: RectangleFrameMetadata,
        policy: RectangleDetectionPolicy = .productionSeed
    ) -> RectanglePrior? {
        guard let snapshot,
              snapshot.frame.geometryGeneration == frame.geometryGeneration,
              snapshot.frame.sourceSize == frame.sourceSize,
              abs(snapshot.frame.rotationAngle - frame.rotationAngle) <= 0.001,
              frame.timestamp >= snapshot.frame.timestamp,
              frame.timestamp - snapshot.frame.timestamp <= policy.capturePriorMaximumAge,
              snapshot.frame.hardwareZoomFactor > 0,
              frame.hardwareZoomFactor > 0,
              abs(log(frame.hardwareZoomFactor / snapshot.frame.hardwareZoomFactor))
                <= policy.capturePriorMaximumZoomLogDifference else {
            return nil
        }
        return RectanglePrior(
            quadrilateral: snapshot.rawCandidate.quadrilateral,
            detector: snapshot.rawCandidate.detector
        )
    }
}
