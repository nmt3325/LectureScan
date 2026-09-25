import CoreGraphics
import Foundation
import UIKit

enum CropCorner: String, CaseIterable, Identifiable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var id: String { rawValue }

    var accessibilityLabel: String {
        switch self {
        case .topLeft:
            return "左上"
        case .topRight:
            return "右上"
        case .bottomLeft:
            return "左下"
        case .bottomRight:
            return "右下"
        }
    }
}

struct DetectedQuadrilateral: Equatable, Codable {
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomLeft: CGPoint
    let bottomRight: CGPoint
    let sourceSize: CGSize?

    init(
        topLeft: CGPoint,
        topRight: CGPoint,
        bottomLeft: CGPoint,
        bottomRight: CGPoint,
        sourceSize: CGSize? = nil
    ) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomLeft = bottomLeft
        self.bottomRight = bottomRight
        self.sourceSize = sourceSize
    }

    static func fullFrame(
        sourceSize: CGSize? = nil,
        inset: CGFloat = 0
    ) -> DetectedQuadrilateral {
        let clampedInset = min(max(inset, 0), 0.45)
        return DetectedQuadrilateral(
            topLeft: CGPoint(x: clampedInset, y: 1 - clampedInset),
            topRight: CGPoint(x: 1 - clampedInset, y: 1 - clampedInset),
            bottomLeft: CGPoint(x: clampedInset, y: clampedInset),
            bottomRight: CGPoint(x: 1 - clampedInset, y: clampedInset),
            sourceSize: sourceSize
        )
    }

    var approximateArea: CGFloat {
        let points = [topLeft, topRight, bottomRight, bottomLeft]
        let doubledArea = zip(points, points.dropFirst() + [points[0]])
            .reduce(CGFloat.zero) { partial, pair in
                partial + (pair.0.x * pair.1.y) - (pair.1.x * pair.0.y)
            }
        return abs(doubledArea) / 2
    }

    func point(for corner: CropCorner) -> CGPoint {
        switch corner {
        case .topLeft:
            return topLeft
        case .topRight:
            return topRight
        case .bottomLeft:
            return bottomLeft
        case .bottomRight:
            return bottomRight
        }
    }

    func withSourceSize(_ size: CGSize?) -> DetectedQuadrilateral {
        DetectedQuadrilateral(
            topLeft: topLeft,
            topRight: topRight,
            bottomLeft: bottomLeft,
            bottomRight: bottomRight,
            sourceSize: size
        )
    }

    func interpolated(
        toward target: DetectedQuadrilateral,
        amount: CGFloat
    ) -> DetectedQuadrilateral {
        let weight = min(max(amount, 0), 1)
        return DetectedQuadrilateral(
            topLeft: topLeft.interpolated(toward: target.topLeft, amount: weight),
            topRight: topRight.interpolated(toward: target.topRight, amount: weight),
            bottomLeft: bottomLeft.interpolated(toward: target.bottomLeft, amount: weight),
            bottomRight: bottomRight.interpolated(toward: target.bottomRight, amount: weight),
            sourceSize: target.sourceSize ?? sourceSize
        )
    }

    func moving(_ corner: CropCorner, to requestedPoint: CGPoint) -> DetectedQuadrilateral {
        let point = CGPoint(
            x: min(max(requestedPoint.x, 0), 1),
            y: min(max(requestedPoint.y, 0), 1)
        )
        let minimumGap: CGFloat = 0.01

        switch corner {
        case .topLeft:
            return DetectedQuadrilateral(
                topLeft: CGPoint(
                    x: min(point.x, topRight.x - minimumGap),
                    y: max(point.y, bottomLeft.y + minimumGap)
                ),
                topRight: topRight,
                bottomLeft: bottomLeft,
                bottomRight: bottomRight,
                sourceSize: sourceSize
            )
        case .topRight:
            return DetectedQuadrilateral(
                topLeft: topLeft,
                topRight: CGPoint(
                    x: max(point.x, topLeft.x + minimumGap),
                    y: max(point.y, bottomRight.y + minimumGap)
                ),
                bottomLeft: bottomLeft,
                bottomRight: bottomRight,
                sourceSize: sourceSize
            )
        case .bottomLeft:
            return DetectedQuadrilateral(
                topLeft: topLeft,
                topRight: topRight,
                bottomLeft: CGPoint(
                    x: min(point.x, bottomRight.x - minimumGap),
                    y: min(point.y, topLeft.y - minimumGap)
                ),
                bottomRight: bottomRight,
                sourceSize: sourceSize
            )
        case .bottomRight:
            return DetectedQuadrilateral(
                topLeft: topLeft,
                topRight: topRight,
                bottomLeft: bottomLeft,
                bottomRight: CGPoint(
                    x: max(point.x, bottomLeft.x + minimumGap),
                    y: min(point.y, topRight.y - minimumGap)
                ),
                sourceSize: sourceSize
            )
        }
    }
}

struct EditableCapture: Identifiable {
    let id: UUID
    let sourceImage: UIImage
    let automaticQuadrilateral: DetectedQuadrilateral?
    let selectedQuadrilateral: DetectedQuadrilateral

    init(
        id: UUID = UUID(),
        sourceImage: UIImage,
        automaticQuadrilateral: DetectedQuadrilateral?,
        selectedQuadrilateral: DetectedQuadrilateral? = nil
    ) {
        self.id = id
        self.sourceImage = sourceImage
        self.automaticQuadrilateral = automaticQuadrilateral?.withSourceSize(sourceImage.size)
        self.selectedQuadrilateral = (
            selectedQuadrilateral
                ?? automaticQuadrilateral
                ?? DetectedQuadrilateral.fullFrame(sourceSize: sourceImage.size, inset: 0.015)
        ).withSourceSize(sourceImage.size)
    }

    func selecting(_ quadrilateral: DetectedQuadrilateral) -> EditableCapture {
        EditableCapture(
            id: id,
            sourceImage: sourceImage,
            automaticQuadrilateral: automaticQuadrilateral,
            selectedQuadrilateral: quadrilateral.withSourceSize(sourceImage.size)
        )
    }
}

enum ImageDisplayGeometry {
    static func aspectFillRect(sourceSize: CGSize, in bounds: CGRect) -> CGRect {
        fittedRect(sourceSize: sourceSize, in: bounds, usesMaximumScale: true)
    }

    static func aspectFitRect(sourceSize: CGSize, in bounds: CGRect) -> CGRect {
        fittedRect(sourceSize: sourceSize, in: bounds, usesMaximumScale: false)
    }

    static func viewPoint(fromVisionPoint point: CGPoint, contentRect: CGRect) -> CGPoint {
        CGPoint(
            x: contentRect.minX + point.x * contentRect.width,
            y: contentRect.minY + (1 - point.y) * contentRect.height
        )
    }

    static func visionPoint(fromViewPoint point: CGPoint, contentRect: CGRect) -> CGPoint {
        guard contentRect.width > 0, contentRect.height > 0 else { return .zero }
        return CGPoint(
            x: min(max((point.x - contentRect.minX) / contentRect.width, 0), 1),
            y: min(max(1 - ((point.y - contentRect.minY) / contentRect.height), 0), 1)
        )
    }

    private static func fittedRect(
        sourceSize: CGSize,
        in bounds: CGRect,
        usesMaximumScale: Bool
    ) -> CGRect {
        guard sourceSize.width > 0,
              sourceSize.height > 0,
              bounds.width > 0,
              bounds.height > 0 else {
            return bounds
        }

        let horizontalScale = bounds.width / sourceSize.width
        let verticalScale = bounds.height / sourceSize.height
        let scale = usesMaximumScale
            ? max(horizontalScale, verticalScale)
            : min(horizontalScale, verticalScale)
        let size = CGSize(
            width: sourceSize.width * scale,
            height: sourceSize.height * scale
        )
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

enum CameraAuthorizationState: Equatable {
    case checking
    case authorized
    case denied
    case unavailable(String)
}

struct CameraZoomRange: Equatable {
    let minimum: CGFloat
    let maximum: CGFloat

    init(minimum: CGFloat, maximum: CGFloat) {
        let safeMinimum = max(minimum, 0.01)
        self.minimum = safeMinimum
        self.maximum = max(maximum, safeMinimum)
    }

    func clamped(_ factor: CGFloat) -> CGFloat {
        min(max(factor, minimum), maximum)
    }
}

enum ZoomDialMath {
    static func factor(
        from startFactor: CGFloat,
        angleDelta: CGFloat,
        radiansPerDoubling: CGFloat,
        range: CameraZoomRange
    ) -> CGFloat {
        guard radiansPerDoubling > 0 else { return range.clamped(startFactor) }
        let octaves = -angleDelta / radiansPerDoubling
        let multiplier = CGFloat(pow(2, Double(octaves)))
        return range.clamped(startFactor * multiplier)
    }
}

enum SilentCaptureMethod: Equatable {
    case preparing
    case publicPhotoSuppression
    case videoFrame

    var shortLabel: String {
        switch self {
        case .preparing:
            return "無音準備中"
        case .publicPhotoSuppression:
            return "高画質・無音"
        case .videoFrame:
            return "無音フレーム"
        }
    }

    var explanation: String {
        switch self {
        case .preparing:
            return "カメラを準備しています"
        case .publicPhotoSuppression:
            return "iOS の公開シャッター音抑制 API を使用"
        case .videoFrame:
            return "映像フレームを取得するためシャッター音を再生しません"
        }
    }
}

struct CaptureNotice: Identifiable, Equatable {
    enum Kind: Equatable {
        case success
        case error
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let detail: String
}

private extension CGPoint {
    func interpolated(toward target: CGPoint, amount: CGFloat) -> CGPoint {
        CGPoint(
            x: x + (target.x - x) * amount,
            y: y + (target.y - y) * amount
        )
    }
}
