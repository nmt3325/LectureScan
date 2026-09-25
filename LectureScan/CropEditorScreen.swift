import SwiftUI
import UIKit

struct CropEditorScreen: View {
    @ObservedObject var camera: CameraModel
    let capture: EditableCapture

    @Environment(\.dismiss) private var dismiss
    @State private var quadrilateral: DetectedQuadrilateral

    init(camera: CameraModel, capture: EditableCapture) {
        self.camera = camera
        self.capture = capture
        _quadrilateral = State(
            initialValue: capture.selectedQuadrilateral.withSourceSize(capture.sourceImage.size)
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                CropCanvas(
                    image: capture.sourceImage,
                    quadrilateral: $quadrilateral
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Text("黄色い丸をドラッグして、残したい範囲の四隅に合わせてください。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)

                HStack(spacing: 12) {
                    Button {
                        if let automaticQuadrilateral = capture.automaticQuadrilateral {
                            quadrilateral = automaticQuadrilateral.withSourceSize(capture.sourceImage.size)
                        }
                    } label: {
                        Label("自動検出", systemImage: "viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(capture.automaticQuadrilateral == nil || camera.isApplyingCrop)

                    Button {
                        quadrilateral = .fullFrame(
                            sourceSize: capture.sourceImage.size,
                            inset: 0.015
                        )
                    } label: {
                        Label("画像全体", systemImage: "rectangle.expand.vertical")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(camera.isApplyingCrop)
                }

                Button(action: applyCrop) {
                    HStack(spacing: 10) {
                        if camera.isApplyingCrop {
                            ProgressView()
                                .tint(.black)
                        } else {
                            Image(systemName: "crop.rotate")
                        }
                        Text(camera.isApplyingCrop ? "補正して保存中…" : "この範囲で補正して保存")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.borderedProminent)
                .tint(.yellow)
                .foregroundStyle(.black)
                .disabled(camera.isApplyingCrop || quadrilateral.approximateArea < 0.002)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("切り抜きを修正")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .disabled(camera.isApplyingCrop)
                }
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(camera.isApplyingCrop)
    }

    private func applyCrop() {
        camera.applyManualCrop(quadrilateral) { succeeded in
            if succeeded {
                dismiss()
            }
        }
    }
}

private struct CropCanvas: View {
    let image: UIImage
    @Binding var quadrilateral: DetectedQuadrilateral

    private let coordinateSpaceName = "LectureScanCropCanvas"

    var body: some View {
        GeometryReader { geometry in
            let bounds = CGRect(origin: .zero, size: geometry.size)
            let contentRect = ImageDisplayGeometry.aspectFitRect(
                sourceSize: image.size,
                in: bounds.insetBy(dx: 6, dy: 6)
            )
            let polygon = polygonPath(in: contentRect)

            ZStack {
                Color.black

                Image(uiImage: image)
                    .resizable()
                    .frame(width: contentRect.width, height: contentRect.height)
                    .position(x: contentRect.midX, y: contentRect.midY)

                outsideMask(polygon: polygon, contentRect: contentRect)
                    .fill(
                        Color.black.opacity(0.56),
                        style: FillStyle(eoFill: true)
                    )
                    .allowsHitTesting(false)

                polygon
                    .fill(Color.yellow.opacity(0.10))
                    .allowsHitTesting(false)

                polygon
                    .stroke(
                        Color.yellow,
                        style: StrokeStyle(
                            lineWidth: 3,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .shadow(color: .black.opacity(0.7), radius: 2)
                    .allowsHitTesting(false)

                ForEach(CropCorner.allCases) { corner in
                    handle(for: corner, contentRect: contentRect)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.16), lineWidth: 1)
            }
            .coordinateSpace(name: coordinateSpaceName)
        }
    }

    private func handle(for corner: CropCorner, contentRect: CGRect) -> some View {
        let point = ImageDisplayGeometry.viewPoint(
            fromVisionPoint: quadrilateral.point(for: corner),
            contentRect: contentRect
        )

        return ZStack {
            Circle()
                .fill(.black.opacity(0.72))
                .frame(width: 32, height: 32)
            Circle()
                .fill(.yellow)
                .frame(width: 22, height: 22)
            Circle()
                .stroke(.white, lineWidth: 2)
                .frame(width: 22, height: 22)
        }
        .frame(width: 52, height: 52)
        .contentShape(Circle())
        .position(point)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpaceName))
                .onChanged { value in
                    let normalizedPoint = ImageDisplayGeometry.visionPoint(
                        fromViewPoint: value.location,
                        contentRect: contentRect
                    )
                    quadrilateral = quadrilateral.moving(corner, to: normalizedPoint)
                }
        )
        .accessibilityLabel("\(corner.accessibilityLabel)の切り抜き位置")
        .accessibilityHint("ドラッグして位置を調整")
    }

    private func polygonPath(in contentRect: CGRect) -> Path {
        let topLeft = ImageDisplayGeometry.viewPoint(
            fromVisionPoint: quadrilateral.topLeft,
            contentRect: contentRect
        )
        let topRight = ImageDisplayGeometry.viewPoint(
            fromVisionPoint: quadrilateral.topRight,
            contentRect: contentRect
        )
        let bottomRight = ImageDisplayGeometry.viewPoint(
            fromVisionPoint: quadrilateral.bottomRight,
            contentRect: contentRect
        )
        let bottomLeft = ImageDisplayGeometry.viewPoint(
            fromVisionPoint: quadrilateral.bottomLeft,
            contentRect: contentRect
        )

        return Path { path in
            path.move(to: topLeft)
            path.addLine(to: topRight)
            path.addLine(to: bottomRight)
            path.addLine(to: bottomLeft)
            path.closeSubpath()
        }
    }

    private func outsideMask(polygon: Path, contentRect: CGRect) -> Path {
        var path = Path()
        path.addRect(contentRect)
        path.addPath(polygon)
        return path
    }
}
