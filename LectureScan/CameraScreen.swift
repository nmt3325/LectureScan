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
                onFocus: camera.focus(at:)
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

                Text("黄色い枠に書類・黒板・スクリーンを合わせて撮影")
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
