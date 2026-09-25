import CoreGraphics
import Foundation

struct DetectedQuadrilateral: Equatable {
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomLeft: CGPoint
    let bottomRight: CGPoint

    var approximateArea: CGFloat {
        let points = [topLeft, topRight, bottomRight, bottomLeft]
        let doubledArea = zip(points, points.dropFirst() + [points[0]])
            .reduce(CGFloat.zero) { partial, pair in
                partial + (pair.0.x * pair.1.y) - (pair.1.x * pair.0.y)
            }
        return abs(doubledArea) / 2
    }
}

enum CameraAuthorizationState: Equatable {
    case checking
    case authorized
    case denied
    case unavailable(String)
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
