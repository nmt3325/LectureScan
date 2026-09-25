import AVFoundation
import SwiftUI
import UIKit

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let quadrilateral: DetectedQuadrilateral?
    let onFocus: (CGPoint) -> Void

    func makeUIView(context: Context) -> PreviewSurface {
        let view = PreviewSurface()
        view.configure(session: session)
        view.onFocus = onFocus
        return view
    }

    func updateUIView(_ uiView: PreviewSurface, context: Context) {
        uiView.configure(session: session)
        uiView.onFocus = onFocus
        uiView.update(quadrilateral: quadrilateral)
    }
}

final class PreviewSurface: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    private var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    var onFocus: ((CGPoint) -> Void)?

    private let quadrilateralLayer = CAShapeLayer()
    private let focusLayer = CAShapeLayer()
    private var quadrilateral: DetectedQuadrilateral?

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
        layer.addSublayer(quadrilateralLayer)

        focusLayer.fillColor = UIColor.clear.cgColor
        focusLayer.strokeColor = UIColor.systemYellow.cgColor
        focusLayer.lineWidth = 2
        focusLayer.opacity = 0
        layer.addSublayer(focusLayer)

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTap(_:))))
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
        self.quadrilateral = quadrilateral
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        quadrilateralLayer.frame = bounds
        focusLayer.frame = bounds
        drawQuadrilateral()
    }

    private func drawQuadrilateral() {
        guard let quadrilateral else {
            quadrilateralLayer.path = nil
            return
        }

        let path = UIBezierPath()
        path.move(to: layerPoint(from: quadrilateral.topLeft))
        path.addLine(to: layerPoint(from: quadrilateral.topRight))
        path.addLine(to: layerPoint(from: quadrilateral.bottomRight))
        path.addLine(to: layerPoint(from: quadrilateral.bottomLeft))
        path.close()
        quadrilateralLayer.path = path.cgPath
    }

    private func layerPoint(from visionPoint: CGPoint) -> CGPoint {
        let capturePoint = CGPoint(x: visionPoint.x, y: 1 - visionPoint.y)
        return previewLayer.layerPointConverted(fromCaptureDevicePoint: capturePoint)
    }

    @objc private func didTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: point)
        onFocus?(devicePoint)
        showFocusRing(at: point)
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
