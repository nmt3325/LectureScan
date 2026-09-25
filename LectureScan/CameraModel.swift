import AVFoundation
import CoreImage
import Foundation
import UIKit
import UniformTypeIdentifiers

final class CameraModel: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published private(set) var authorizationState: CameraAuthorizationState = .checking
    @Published private(set) var detectedQuadrilateral: DetectedQuadrilateral?
    @Published private(set) var lastImage: UIImage?
    @Published private(set) var notice: CaptureNotice?
    @Published private(set) var isReady = false
    @Published private(set) var isCapturing = false
    @Published private(set) var isTorchOn = false
    @Published private(set) var zoomFactor: CGFloat = 1
    @Published private(set) var zoomRange = CameraZoomRange(minimum: 1, maximum: 1)
    @Published private(set) var silentCaptureMethod: SilentCaptureMethod = .preparing

    private let sessionQueue = DispatchQueue(label: "dev.nmt3325.LectureScan.session", qos: .userInitiated)
    private let videoQueue = DispatchQueue(label: "dev.nmt3325.LectureScan.video", qos: .userInteractive)
    private let processingQueue = DispatchQueue(label: "dev.nmt3325.LectureScan.processing", qos: .userInitiated)
    private let frameLock = NSLock()

    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let processor = DocumentProcessor()

    private var videoDevice: AVCaptureDevice?
    private var latestPixelBuffer: CVPixelBuffer?
    private var isConfigured = false
    private var lastDetectionTime: CFTimeInterval = 0
    private var consecutiveDetectionMisses = 0

    func start() {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            publish {
                self.authorizationState = .unavailable("ユニットテスト実行中です。")
                self.isReady = false
            }
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            publish { self.authorizationState = .authorized }
            configureAndStart()
        case .notDetermined:
            publish { self.authorizationState = .checking }
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                if granted {
                    self.publish { self.authorizationState = .authorized }
                    self.configureAndStart()
                } else {
                    self.publish { self.authorizationState = .denied }
                }
            }
        case .denied, .restricted:
            publish { self.authorizationState = .denied }
        @unknown default:
            publish { self.authorizationState = .unavailable("カメラの権限状態を確認できませんでした。") }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
            self.publish {
                self.isReady = false
                self.isTorchOn = false
            }
        }
    }

    func capture() {
        guard isReady, !isCapturing else { return }
        isCapturing = true
        notice = nil

        sessionQueue.async { [weak self] in
            guard let self else { return }

            if #available(iOS 18.0, *), self.photoOutput.isShutterSoundSuppressionSupported {
                let settings = AVCapturePhotoSettings()
                settings.flashMode = .off
                settings.photoQualityPrioritization = .quality
                settings.isShutterSoundSuppressionEnabled = true
                if self.photoOutput.maxPhotoDimensions.width > 0 {
                    settings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions
                }
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            } else {
                self.captureLatestVideoFrame()
            }
        }
    }

    func copyLastImage() {
        guard let image = lastImage else { return }
        processingQueue.async { [weak self] in
            guard let self, let data = image.jpegData(compressionQuality: 0.96) else { return }
            self.publish {
                UIPasteboard.general.setData(data, forPasteboardType: UTType.jpeg.identifier)
                self.showNotice(
                    CaptureNotice(
                        kind: .success,
                        title: "もう一度コピーしました",
                        detail: "JPEG をクリップボードに保存しました"
                    )
                )
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }

    func focus(at devicePoint: CGPoint) {
        sessionQueue.async { [weak self] in
            guard let device = self?.videoDevice else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }

                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = .continuousAutoExposure
                }
            } catch {
                self?.fail("フォーカスを設定できませんでした。")
            }
        }
    }

    func setZoomFactor(_ requestedFactor: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDevice else { return }
            let range = self.availableZoomRange(for: device)
            let displayMultiplier = self.displayZoomFactorMultiplier(for: device)
            let targetDisplayFactor = range.clamped(requestedFactor)
            let targetHardwareFactor = min(
                max(targetDisplayFactor / displayMultiplier, device.minAvailableVideoZoomFactor),
                device.maxAvailableVideoZoomFactor
            )

            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }

                device.videoZoomFactor = targetHardwareFactor
                let appliedDisplayFactor = range.clamped(
                    device.videoZoomFactor * displayMultiplier
                )

                self.publish {
                    self.zoomRange = range
                    self.zoomFactor = appliedDisplayFactor
                }
            } catch {
                self.failZoom(error.localizedDescription)
            }
        }
    }

    func changeZoom(by delta: CGFloat) {
        setZoomFactor(zoomRange.clamped(zoomFactor + delta))
    }

    func resetZoom() {
        setZoomFactor(zoomRange.clamped(1))
    }

    func toggleTorch() {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDevice, device.hasTorch else { return }
            do {
                try device.lockForConfiguration()
                let turnOn = device.torchMode == .off
                if turnOn {
                    try device.setTorchModeOn(level: min(0.35, AVCaptureDevice.maxAvailableTorchLevel))
                } else {
                    device.torchMode = .off
                }
                device.unlockForConfiguration()
                self.publish { self.isTorchOn = turnOn }
            } catch {
                self.fail("ライトを切り替えられませんでした。")
            }
        }
    }

    private func configureAndStart() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            if !self.isConfigured {
                do {
                    try self.configureSession()
                    self.isConfigured = true
                } catch {
                    self.publish {
                        self.authorizationState = .unavailable(error.localizedDescription)
                        self.isReady = false
                    }
                    return
                }
            }

            guard !self.session.isRunning else {
                self.publish { self.isReady = true }
                return
            }

            self.session.startRunning()
            let method: SilentCaptureMethod
            if #available(iOS 18.0, *), self.photoOutput.isShutterSoundSuppressionSupported {
                method = .publicPhotoSuppression
            } else {
                method = .videoFrame
            }
            self.publish {
                self.silentCaptureMethod = method
                self.isReady = true
            }
        }
    }

    private func configureSession() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo

        guard let device = bestBackCamera() else {
            throw CameraConfigurationError.noCamera
        }
        videoDevice = device

        let initialZoomRange = availableZoomRange(for: device)
        let initialZoomFactor = initialZoomRange.clamped(
            device.videoZoomFactor * displayZoomFactorMultiplier(for: device)
        )
        publish {
            self.zoomRange = initialZoomRange
            self.zoomFactor = initialZoomFactor
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw CameraConfigurationError.cannotAddInput
        }
        session.addInput(input)

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        guard session.canAddOutput(videoOutput) else {
            throw CameraConfigurationError.cannotAddVideoOutput
        }
        session.addOutput(videoOutput)

        guard session.canAddOutput(photoOutput) else {
            throw CameraConfigurationError.cannotAddPhotoOutput
        }
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .quality

        if let largestDimensions = device.activeFormat.supportedMaxPhotoDimensions.max(by: {
            Int64($0.width) * Int64($0.height) < Int64($1.width) * Int64($1.height)
        }) {
            photoOutput.maxPhotoDimensions = largestDimensions
        }

        applyPortraitRotation(to: videoOutput.connection(with: .video))
        applyPortraitRotation(to: photoOutput.connection(with: .video))
    }

    private func availableZoomRange(for device: AVCaptureDevice) -> CameraZoomRange {
        let qualityZoomLimit: CGFloat = 8
        let displayMultiplier = displayZoomFactorMultiplier(for: device)
        return CameraZoomRange(
            minimum: device.minAvailableVideoZoomFactor * displayMultiplier,
            maximum: min(
                device.maxAvailableVideoZoomFactor * displayMultiplier,
                qualityZoomLimit
            )
        )
    }

    private func displayZoomFactorMultiplier(for device: AVCaptureDevice) -> CGFloat {
        if #available(iOS 18.0, *) {
            return max(device.displayVideoZoomFactorMultiplier, 0.01)
        }
        return 1
    }

    private func applyPortraitRotation(to connection: AVCaptureConnection?) {
        guard let connection else { return }
        if connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }

    private func bestBackCamera() -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInTripleCamera,
                .builtInDualWideCamera,
                .builtInWideAngleCamera
            ],
            mediaType: .video,
            position: .back
        )
        return discovery.devices.first
    }

    private func captureLatestVideoFrame() {
        frameLock.lock()
        let pixelBuffer = latestPixelBuffer
        frameLock.unlock()

        guard let pixelBuffer else {
            fail("カメラ映像の準備ができていません。")
            return
        }

        let image = CIImage(cvPixelBuffer: pixelBuffer)
        process(image, method: .videoFrame)
    }

    private func process(_ image: CIImage, method: SilentCaptureMethod) {
        processingQueue.async { [weak self] in
            guard let self else { return }
            do {
                let result = try self.processor.process(image)
                guard let jpegData = result.image.jpegData(compressionQuality: 0.96) else {
                    throw DocumentProcessorError.renderingFailed
                }
                self.finish(
                    image: result.image,
                    jpegData: jpegData,
                    rectangleFound: result.rectangleFound,
                    method: method
                )
            } catch {
                self.fail(error.localizedDescription)
            }
        }
    }

    private func finish(
        image: UIImage,
        jpegData: Data,
        rectangleFound: Bool,
        method: SilentCaptureMethod
    ) {
        publish {
            UIPasteboard.general.setData(jpegData, forPasteboardType: UTType.jpeg.identifier)
            self.lastImage = image
            self.isCapturing = false
            self.showNotice(
                CaptureNotice(
                    kind: .success,
                    title: rectangleFound ? "矩形補正してコピーしました" : "画像をコピーしました",
                    detail: rectangleFound
                        ? "傾きを補正した JPEG をクリップボードへ保存"
                        : "矩形が見つからなかったため全体をコピー（\(method.shortLabel)）"
                )
            )
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func fail(_ message: String) {
        publish {
            self.isCapturing = false
            self.showNotice(
                CaptureNotice(
                    kind: .error,
                    title: "撮影できませんでした",
                    detail: message
                )
            )
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func failZoom(_ message: String) {
        publish {
            self.showNotice(
                CaptureNotice(
                    kind: .error,
                    title: "ズームを変更できませんでした",
                    detail: message
                )
            )
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func showNotice(_ newNotice: CaptureNotice) {
        notice = newNotice
        let id = newNotice.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { [weak self] in
            guard self?.notice?.id == id else { return }
            self?.notice = nil
        }
    }

    private func publish(_ update: @escaping () -> Void) {
        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async(execute: update)
        }
    }
}

extension CameraModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        frameLock.lock()
        latestPixelBuffer = pixelBuffer
        frameLock.unlock()

        let now = CACurrentMediaTime()
        guard now - lastDetectionTime >= 0.24 else { return }
        lastDetectionTime = now

        do {
            let quadrilateral = try processor.detectQuadrilateral(in: CIImage(cvPixelBuffer: pixelBuffer))
            if let quadrilateral {
                consecutiveDetectionMisses = 0
                publish { self.detectedQuadrilateral = quadrilateral }
            } else {
                consecutiveDetectionMisses += 1
                if consecutiveDetectionMisses >= 3 {
                    publish { self.detectedQuadrilateral = nil }
                }
            }
        } catch {
            consecutiveDetectionMisses += 1
        }
    }
}

extension CameraModel: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            fail(error.localizedDescription)
            return
        }

        guard let data = photo.fileDataRepresentation(),
              let image = CIImage(
                data: data,
                options: [.applyOrientationProperty: true]
              ) else {
            fail("写真データを読み込めませんでした。")
            return
        }

        process(image, method: .publicPhotoSuppression)
    }
}

private enum CameraConfigurationError: LocalizedError {
    case noCamera
    case cannotAddInput
    case cannotAddVideoOutput
    case cannotAddPhotoOutput

    var errorDescription: String? {
        switch self {
        case .noCamera:
            return "背面カメラが見つかりません。"
        case .cannotAddInput:
            return "カメラ入力を追加できません。"
        case .cannotAddVideoOutput:
            return "映像出力を追加できません。"
        case .cannotAddPhotoOutput:
            return "写真出力を追加できません。"
        }
    }
}
