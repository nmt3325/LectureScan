import AVFoundation
import SwiftUI
import UIKit

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let quadrilateral: DetectedQuadrilateral?
    let zoomFactor: CGFloat
    let zoomRange: CameraZoomRange
    let onFocus: (CGPoint) -> Void
    let onZoom: (CGFloat) -> Void

    func makeUIView(context: Context) -> PreviewSurface {
        let view = PreviewSurface()
        view.configure(session: session)
        view.onFocus = onFocus
        view.onZoom = onZoom
        view.update(quadrilateral: quadrilateral)
        view.updateZoom(factor: zoomFactor, range: zoomRange)
        return view
    }

    func updateUIView(_ uiView: PreviewSurface, context: Context) {
        uiView.configure(session: session)
        uiView.onFocus = onFocus
        uiView.onZoom = onZoom
        uiView.update(quadrilateral: quadrilateral)
        uiView.updateZoom(factor: zoomFactor, range: zoomRange)
    }
}

final class PreviewSurface: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    private var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    var onFocus: ((CGPoint) -> Void)?
    var onZoom: ((CGFloat) -> Void)?

    private let quadrilateralLayer = CAShapeLayer()
    private let focusLayer = CAShapeLayer()
    private var quadrilateral: DetectedQuadrilateral?
    private var zoomFactor: CGFloat = 1
    private var zoomRange = CameraZoomRange(minimum: 1, maximum: 1)
    private var pinchStartZoomFactor: CGFloat = 1
    private var rotationStartZoomFactor: CGFloat = 1

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        previewLayer.videoGravity = .resizeAspectFill

        quadrilateralLayer.fillColor = UIColor.systemYellow.withAlphaComponent(0.14).cgColor
        quadrilateralLayer.strokeColor = UIColor.systemYellow.cgColor
        quadrilateralLayer.lineWidth = 3
        quadrilateralLayer.lineJoin = .round
        quadrilateralLayer.shadowColor = UIColor.black.cgColor
        quadrilateralLayer.shadowOpacity = 0.45
        quadrilateralLayer.shadowRadius = 2
        quadrilateralLayer.shadowOffset = .zero
        quadrilateralLayer.contentsScale = UIScreen.main.scale
        layer.addSublayer(quadrilateralLayer)

        focusLayer.fillColor = UIColor.clear.cgColor
        focusLayer.strokeColor = UIColor.systemYellow.cgColor
        focusLayer.lineWidth = 2
        focusLayer.opacity = 0
        focusLayer.contentsScale = UIScreen.main.scale
        layer.addSublayer(focusLayer)

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTap(_:))))
        addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(didPinch(_:))))
        addGestureRecognizer(UIRotationGestureRecognizer(target: self, action: #selector(didRotate(_:))))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(session: AVCaptureSession) {
        if previewLayer.session !== session {
            previewLayer.session = session
        }
        if let connection = previewLayer.connection,
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }

    func update(quadrilateral: DetectedQuadrilateral?) {
        guard self.quadrilateral != quadrilateral else { return }
        self.quadrilateral = quadrilateral
        drawQuadrilateral()
    }

    func updateZoom(factor: CGFloat, range: CameraZoomRange) {
        zoomRange = range
        zoomFactor = range.clamped(factor)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        quadrilateralLayer.frame = bounds
        focusLayer.frame = bounds
        drawQuadrilateral()
    }

    private func drawQuadrilateral() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        guard let quadrilateral else {
            quadrilateralLayer.path = nil
            return
        }

        let path = UIBezierPath()
        path.move(to: layerPoint(from: quadrilateral.topLeft, quadrilateral: quadrilateral))
        path.addLine(to: layerPoint(from: quadrilateral.topRight, quadrilateral: quadrilateral))
        path.addLine(to: layerPoint(from: quadrilateral.bottomRight, quadrilateral: quadrilateral))
        path.addLine(to: layerPoint(from: quadrilateral.bottomLeft, quadrilateral: quadrilateral))
        path.close()
        quadrilateralLayer.path = path.cgPath
    }

    private func layerPoint(
        from visionPoint: CGPoint,
        quadrilateral: DetectedQuadrilateral
    ) -> CGPoint {
        if let sourceSize = quadrilateral.sourceSize,
           sourceSize.width > 0,
           sourceSize.height > 0 {
            let contentRect = ImageDisplayGeometry.aspectFillRect(
                sourceSize: sourceSize,
                in: quadrilateralLayer.bounds
            )
            return ImageDisplayGeometry.viewPoint(
                fromVisionPoint: visionPoint,
                contentRect: contentRect
            )
        }

        let capturePoint = CGPoint(x: visionPoint.x, y: 1 - visionPoint.y)
        return previewLayer.layerPointConverted(fromCaptureDevicePoint: capturePoint)
    }

    @objc private func didTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: point)
        onFocus?(devicePoint)
        showFocusRing(at: point)
    }

    @objc private func didPinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            pinchStartZoomFactor = zoomFactor
        case .changed, .ended:
            let targetFactor = zoomRange.clamped(pinchStartZoomFactor * gesture.scale)
            zoomFactor = targetFactor
            onZoom?(targetFactor)
        default:
            break
        }
    }

    @objc private func didRotate(_ gesture: UIRotationGestureRecognizer) {
        switch gesture.state {
        case .began:
            rotationStartZoomFactor = zoomFactor
        case .changed, .ended:
            let radiansPerDoubling = CGFloat.pi / 3
            let octaves = gesture.rotation / radiansPerDoubling
            let multiplier = CGFloat(pow(2, Double(octaves)))
            let targetFactor = zoomRange.clamped(rotationStartZoomFactor * multiplier)
            zoomFactor = targetFactor
            onZoom?(targetFactor)
        default:
            break
        }
    }

    private func showFocusRing(at point: CGPoint) {
        let side: CGFloat = 72
        let rect = CGRect(
            x: point.x - side / 2,
            y: point.y - side / 2,
            width: side,
            height: side
        )
        focusLayer.path = UIBezierPath(roundedRect: rect, cornerRadius: 10).cgPath
        focusLayer.removeAllAnimations()
        focusLayer.opacity = 1

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.25
        scale.toValue = 1
        scale.duration = 0.18
        focusLayer.add(scale, forKey: "focusScale")

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.beginTime = CACurrentMediaTime() + 0.55
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = 0.35
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        focusLayer.add(fade, forKey: "focusFade")
    }
}
