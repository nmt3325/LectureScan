import SwiftUI
import UIKit

struct CameraScreen: View {
    @ObservedObject var camera: CameraModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch camera.authorizationState {
            case .checking:
                loadingView
            case .authorized:
                cameraView
            case .denied:
                permissionView
            case .unavailable(let message):
                unavailableView(message)
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear { camera.start() }
    }

    private var cameraView: some View {
        ZStack {
            CameraPreview(
                session: camera.session,
                quadrilateral: camera.detectedQuadrilateral,
                zoomFactor: camera.zoomFactor,
                zoomRange: camera.zoomRange,
                onFocus: camera.focus(at:),
                onZoom: camera.setZoomFactor(_:)
            )
            .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.black.opacity(0.62),
                    Color.clear,
                    Color.clear,
                    Color.black.opacity(0.78)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 14) {
                topBar
                Spacer()

                if let notice = camera.notice {
                    NoticeCard(notice: notice)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                zoomControls

                Text("倍率をタップ／スライド、またはプレビューを2本指で回転・ピンチしてズーム")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.88))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)

                captureControls
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 18)
            .animation(.spring(response: 0.3, dampingFraction: 0.82), value: camera.notice)
        }
    }

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("LectureScan")
                        .font(.title3.bold())
                    Text("授業用ドキュメントカメラ")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                }

                Spacer()

                Button(action: camera.toggleTorch) {
                    Image(systemName: camera.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel(camera.isTorchOn ? "ライトを消す" : "ライトをつける")
            }

            HStack(spacing: 8) {
                StatusPill(
                    icon: "speaker.slash.fill",
                    text: camera.silentCaptureMethod.shortLabel,
                    tint: .green
                )
                StatusPill(
                    icon: camera.detectedQuadrilateral == nil ? "viewfinder" : "rectangle.dashed.badge.record",
                    text: camera.detectedQuadrilateral == nil ? "矩形を探索中" : "矩形を検出",
                    tint: camera.detectedQuadrilateral == nil ? .white : .yellow
                )
                Spacer(minLength: 0)
            }
        }
    }

    private var zoomControls: some View {
        ZoomControl(
            factor: camera.zoomFactor,
            range: camera.zoomRange,
            onChange: camera.setZoomFactor(_:)
        )
        .frame(maxWidth: 340)
        .zIndex(1)
    }

    private var captureControls: some View {
        ZStack {
            HStack {
                if let image = camera.lastImage {
                    Button(action: camera.copyLastImage) {
                        ZStack(alignment: .bottomTrailing) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 62, height: 62)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(.white.opacity(0.8), lineWidth: 1)
                                }

                            Image(systemName: "doc.on.clipboard.fill")
                                .font(.caption2.bold())
                                .foregroundStyle(.black)
                                .padding(5)
                                .background(.yellow, in: Circle())
                                .offset(x: 4, y: 4)
                        }
                    }
                    .accessibilityLabel("最後の画像をもう一度コピー")
                } else {
                    Color.clear.frame(width: 62, height: 62)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.title3)
                    Text("自動コピー")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.white.opacity(0.78))
                .frame(width: 62)
            }

            Button(action: camera.capture) {
                ZStack {
                    Circle()
                        .stroke(.white, lineWidth: 5)
                        .frame(width: 82, height: 82)
                    Circle()
                        .fill(camera.isCapturing ? Color.yellow.opacity(0.7) : Color.white)
                        .frame(width: 66, height: 66)
                    if camera.isCapturing {
                        ProgressView()
                            .tint(.black)
                    }
                }
                .contentShape(Circle())
            }
            .disabled(!camera.isReady || camera.isCapturing)
            .opacity(camera.isReady ? 1 : 0.45)
            .accessibilityLabel("撮影してクリップボードへコピー")
        }
        .frame(height: 90)
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("カメラを準備しています…")
                .font(.headline)
        }
    }

    private var permissionView: some View {
        VStack(spacing: 18) {
            Image(systemName: "camera.fill")
                .font(.system(size: 52))
                .foregroundStyle(.yellow)
            Text("カメラへのアクセスが必要です")
                .font(.title3.bold())
            Text("設定で LectureScan のカメラアクセスを許可してください。写真は端末内で処理されます。")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("設定を開く") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .buttonStyle(.borderedProminent)
            .tint(.yellow)
            .foregroundStyle(.black)
        }
        .padding(32)
    }

    private func unavailableView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("カメラを開始できません")
                .font(.title3.bold())
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("再試行") { camera.start() }
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
    }
}

private struct ZoomControl: View {
    let factor: CGFloat
    let range: CameraZoomRange
    let onChange: (CGFloat) -> Void

    @State private var isDialVisible = false
    @State private var dragStartAngle: CGFloat?
    @State private var dragStartFactor: CGFloat?

    private let radiansPerDoubling = CGFloat.pi / 6
    private let dialCenterOffset: CGFloat = 58

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(
                x: geometry.size.width / 2,
                y: geometry.size.height + dialCenterOffset
            )

            ZStack(alignment: .bottom) {
                if isDialVisible {
                    ZoomArcDial(factor: factor, range: range)
                        .frame(width: geometry.size.width, height: 112)
                        .transition(
                            .opacity.combined(
                                with: .scale(scale: 0.92, anchor: .bottom)
                            )
                        )
                        .allowsHitTesting(false)
                }

                compactPresetRow
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height,
                alignment: .bottom
            )
            .contentShape(Rectangle())
            .simultaneousGesture(rotationDragGesture(center: center))
        }
        .frame(height: 48)
        .animation(.easeOut(duration: 0.16), value: isDialVisible)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ズーム")
        .accessibilityValue(accessibilityZoomLabel)
        .accessibilityHint("倍率を上下に調整できます")
        .accessibilityAdjustableAction { direction in
            let step = CGFloat(pow(2, 1.0 / 6.0))
            switch direction {
            case .increment:
                onChange(range.clamped(factor * step))
            case .decrement:
                onChange(range.clamped(factor / step))
            @unknown default:
                break
            }
        }
    }

    private var compactPresetRow: some View {
        HStack(spacing: 3) {
            ForEach(presetValues, id: \.self) { preset in
                let selected = abs(preset - activePreset) < 0.001

                Button {
                    onChange(preset)
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    Text(compactLabel(for: preset, selected: selected))
                        .font(
                            .system(
                                size: selected ? 15 : 14,
                                weight: selected ? .bold : .semibold,
                                design: .rounded
                            )
                        )
                        .monospacedDigit()
                        .foregroundStyle(selected ? Color.yellow : Color.white.opacity(0.86))
                        .frame(width: 44, height: 44)
                        .background {
                            if selected {
                                Circle()
                                    .fill(Color.black.opacity(0.72))
                                    .overlay {
                                        Circle()
                                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                    }
                            }
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(formatZoom(preset, includesUnit: false))倍")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.24), radius: 8, y: 3)
    }

    private var presetValues: [CGFloat] {
        var values: [CGFloat] = [0.5, 1, 2].filter {
            $0 >= range.minimum - 0.001 && $0 <= range.maximum + 0.001
        }

        if values.isEmpty {
            values.append(range.clamped(1))
        }

        if range.minimum > 1,
           values.allSatisfy({ abs($0 - range.minimum) > 0.05 }) {
            values.append(range.minimum)
        }

        if values.count == 1,
           let onlyValue = values.first,
           range.maximum - onlyValue > 0.15 {
            values.append(range.maximum)
        }

        return values.sorted().reduce(into: []) { result, candidate in
            if result.last.map({ abs($0 - candidate) > 0.02 }) ?? true {
                result.append(candidate)
            }
        }
    }

    private var activePreset: CGFloat {
        presetValues.min { lhs, rhs in
            logarithmicDistance(from: lhs) < logarithmicDistance(from: rhs)
        } ?? factor
    }

    private var accessibilityZoomLabel: String {
        "\(formatZoom(factor, includesUnit: false))倍"
    }

    private func compactLabel(for preset: CGFloat, selected: Bool) -> String {
        formatZoom(selected ? factor : preset, includesUnit: selected)
    }

    private func logarithmicDistance(from value: CGFloat) -> Double {
        abs(log2(Double(max(factor, 0.01) / max(value, 0.01))))
    }

    private func rotationDragGesture(center: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .local)
            .onChanged { value in
                if dragStartAngle == nil {
                    dragStartAngle = touchAngle(value.startLocation, center: center)
                    dragStartFactor = factor
                    isDialVisible = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }

                guard let startAngle = dragStartAngle,
                      let startFactor = dragStartFactor else { return }

                let currentAngle = touchAngle(value.location, center: center)
                let angleDelta = normalizedAngle(currentAngle - startAngle)
                let octaves = angleDelta / radiansPerDoubling
                let multiplier = CGFloat(pow(2, Double(octaves)))
                onChange(range.clamped(startFactor * multiplier))
            }
            .onEnded { _ in
                dragStartAngle = nil
                dragStartFactor = nil
                isDialVisible = false
            }
    }

    private func touchAngle(_ point: CGPoint, center: CGPoint) -> CGFloat {
        CGFloat(atan2(Double(point.y - center.y), Double(point.x - center.x)))
    }

    private func normalizedAngle(_ angle: CGFloat) -> CGFloat {
        var normalized = angle
        while normalized > CGFloat.pi { normalized -= 2 * CGFloat.pi }
        while normalized < -CGFloat.pi { normalized += 2 * CGFloat.pi }
        return normalized
    }

    private func formatZoom(_ value: CGFloat, includesUnit: Bool) -> String {
        let roundedToTenth = (value * 10).rounded() / 10
        var text: String
        if abs(roundedToTenth - roundedToTenth.rounded()) < 0.05 {
            text = "\(Int(roundedToTenth.rounded()))"
        } else {
            text = String(format: "%.1f", Double(roundedToTenth))
            if text.hasPrefix("0.") {
                text.removeFirst()
            }
        }
        return text + (includesUnit ? "×" : "")
    }
}

private struct ZoomArcDial: View {
    let factor: CGFloat
    let range: CameraZoomRange

    private let radiansPerDoubling = CGFloat.pi / 6
    private let visibleStartAngle = -CGFloat.pi * 5 / 6
    private let visibleEndAngle = -CGFloat.pi / 6

    var body: some View {
        GeometryReader { geometry in
            let center = dialCenter(in: geometry.size)

            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)

                Canvas { context, size in
                    drawDial(context: &context, size: size)
                }

                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.yellow)
                    .position(x: center.x, y: 14)

                VStack(spacing: 1) {
                    Text(zoomLabel)
                        .font(.title3.bold())
                        .monospacedDigit()
                    Text("ZOOM")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.yellow)
                .position(x: center.x, y: 70)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        }
        .accessibilityHidden(true)
    }

    private var zoomLabel: String {
        let roundedToTenth = (factor * 10).rounded() / 10
        if abs(roundedToTenth - roundedToTenth.rounded()) < 0.05 {
            return "\(Int(roundedToTenth.rounded()))×"
        }
        var text = String(format: "%.1f", Double(roundedToTenth))
        if text.hasPrefix("0.") {
            text.removeFirst()
        }
        return "\(text)×"
    }

    private func drawDial(context: inout GraphicsContext, size: CGSize) {
        let center = dialCenter(in: size)
        let radius = min(size.width * 0.44, size.height + 30)

        var arc = Path()
        arc.addArc(
            center: center,
            radius: radius,
            startAngle: .radians(Double(visibleStartAngle)),
            endAngle: .radians(Double(visibleEndAngle)),
            clockwise: false
        )
        context.stroke(arc, with: .color(.white.opacity(0.14)), lineWidth: 1)

        let keyValues = labeledValues
        for value in tickValues {
            let angle = angle(for: value)
            guard angle >= visibleStartAngle, angle <= visibleEndAngle else { continue }

            let isKey = keyValues.contains { abs($0 - value) < 0.026 }
            let isHalfStep = abs(value * 2 - (value * 2).rounded()) < 0.026
            let tickLength: CGFloat = isKey ? 20 : (isHalfStep ? 13 : 8)
            let lineWidth: CGFloat = isKey ? 2 : 1
            let color = Color.white.opacity(isKey ? 0.82 : (isHalfStep ? 0.48 : 0.26))

            var tick = Path()
            tick.move(to: point(center: center, radius: radius - tickLength, angle: angle))
            tick.addLine(to: point(center: center, radius: radius, angle: angle))
            context.stroke(tick, with: .color(color), lineWidth: lineWidth)

            guard isKey, abs(angle + CGFloat.pi / 2) > 0.30 else { continue }
            var label = context.resolve(
                Text(formatTick(value))
                    .font(.caption2.weight(.semibold))
            )
            label.shading = .color(.white.opacity(0.72))
            context.draw(
                label,
                at: point(center: center, radius: radius - 36, angle: angle),
                anchor: .center
            )
        }
    }

    private var tickValues: [CGFloat] {
        var values = [range.minimum]
        var value = (range.minimum * 10).rounded(.up) / 10
        var iterations = 0

        while value <= range.maximum + 0.001, iterations < 300 {
            values.append(value)
            let step: CGFloat
            if value < 2 {
                step = 0.1
            } else if value < 4 {
                step = 0.25
            } else {
                step = 0.5
            }
            value += step
            iterations += 1
        }
        values.append(range.maximum)

        return values.sorted().reduce(into: []) { result, candidate in
            if result.last.map({ abs($0 - candidate) > 0.02 }) ?? true {
                result.append(candidate)
            }
        }
    }

    private var labeledValues: [CGFloat] {
        [range.minimum, 0.5, 1, 2, 4, 8, range.maximum]
            .filter { $0 >= range.minimum - 0.001 && $0 <= range.maximum + 0.001 }
            .sorted()
            .reduce(into: []) { result, candidate in
                if result.last.map({ abs($0 - candidate) > 0.02 }) ?? true {
                    result.append(candidate)
                }
            }
    }

    private func angle(for value: CGFloat) -> CGFloat {
        let safeFactor = max(factor, 0.01)
        let octaves = CGFloat(log2(Double(max(value / safeFactor, 0.0001))))
        return -CGFloat.pi / 2 + octaves * radiansPerDoubling
    }

    private func point(center: CGPoint, radius: CGFloat, angle: CGFloat) -> CGPoint {
        CGPoint(
            x: center.x + CGFloat(cos(Double(angle))) * radius,
            y: center.y + CGFloat(sin(Double(angle))) * radius
        )
    }

    private func dialCenter(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: size.height + 58)
    }

    private func formatTick(_ value: CGFloat) -> String {
        if abs(value - value.rounded()) < 0.026 {
            return "\(Int(value.rounded()))"
        }
        var text = String(format: "%.1f", Double(value))
        if text.hasPrefix("0.") {
            text.removeFirst()
        }
        return text
    }
}

private struct StatusPill: View {
    let icon: String
    let text: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
    }
}

private struct NoticeCard: View {
    let notice: CaptureNotice

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: notice.kind == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(notice.kind == .success ? .green : .orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title)
                    .font(.subheadline.bold())
                Text(notice.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
    }
}
