import AVFoundation
import Photos
import SwiftUI

final class CameraModel: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published private(set) var isConfigured = false
    @Published private(set) var isRunning = false
    @Published private(set) var isCapturing = false
    @Published private(set) var zoomFactor: CGFloat = 1.0
    @Published private(set) var deviceZoomFactor: CGFloat = 1.0
    @Published private(set) var depthCaptureAvailable = false
    @Published private(set) var portraitMatteAvailable = false
    @Published var permissionDenied = false
    @Published var statusMessage: String?

    private let sessionQueue = DispatchQueue(label: "com.privateportrait.camera.session")
    private let photoOutput = AVCapturePhotoOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var deviceMaxZoomFactor: CGFloat = 1.0
    private let displayMaxZoomFactor: CGFloat = 3.0
    private var isSessionConfigured = false

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureIfNeeded()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.configureIfNeeded()
                } else {
                    DispatchQueue.main.async { self?.permissionDenied = true }
                }
            }
        default:
            DispatchQueue.main.async { self.permissionDenied = true }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.session.isRunning else { return }
            self.session.stopRunning()
            DispatchQueue.main.async { self.isRunning = false }
        }
    }

    func capturePhoto() {
        guard isConfigured, !isCapturing else { return }

        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.session.isRunning else {
                self.finishCapture(with: "Camera is not ready")
                return
            }
            guard self.photoOutput.captureReadiness == .ready else {
                self.finishCapture(with: "Camera is preparing")
                return
            }

            DispatchQueue.main.async { self.isCapturing = true }

            // Let AVFoundation choose the compatible still-image codec. A
            // forced HEVC settings dictionary can reject auxiliary depth/matte
            // streams on some device/OS combinations.
            let settings = AVCapturePhotoSettings()

            if self.videoInput?.device.hasFlash == true,
               self.photoOutput.supportedFlashModes.contains(.off) {
                settings.flashMode = .off
            }

            settings.photoQualityPrioritization = .quality
            settings.isHighResolutionPhotoEnabled = true

            // These flags are set only after the output has advertised support.
            // Do not assume every codec/format supports every auxiliary stream.
            let useDepth = self.photoOutput.isDepthDataDeliverySupported && self.photoOutput.isDepthDataDeliveryEnabled
            if useDepth {
                settings.isDepthDataDeliveryEnabled = true
                settings.embedsDepthDataInPhoto = true
            }
            let usePortraitMatte = useDepth
                && self.photoOutput.isPortraitEffectsMatteDeliverySupported
                && self.photoOutput.isPortraitEffectsMatteDeliveryEnabled
            if usePortraitMatte {
                settings.isPortraitEffectsMatteDeliveryEnabled = true
                settings.embedsPortraitEffectsMatteInPhoto = true
            }

            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func setZoomFactor(_ requestedFactor: CGFloat) {
        let desired = min(max(requestedFactor, 1.0), displayMaxZoomFactor)

        // Update the UI immediately, including on devices where AVFoundation
        // exposes only a 1x hardware range. The preview layer supplies the
        // remaining digital crop in that case.
        DispatchQueue.main.async { [weak self] in
            self?.zoomFactor = desired
        }

        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoInput?.device else { return }
            let hardwareZoom = min(desired, self.deviceMaxZoomFactor)
            do {
                try device.lockForConfiguration()
                if device.videoZoomFactor != hardwareZoom {
                    device.videoZoomFactor = hardwareZoom
                }
                device.unlockForConfiguration()
                DispatchQueue.main.async {
                    self.deviceZoomFactor = hardwareZoom
                    if desired > self.deviceMaxZoomFactor + 0.01 {
                        self.statusMessage = "Digital framing: hardware zoom unavailable"
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.deviceZoomFactor = 1.0
                    self.statusMessage = "Digital framing: hardware zoom unavailable"
                }
            }
        }
    }

    func focus(at point: CGPoint, in previewSize: CGSize) {
        guard previewSize.width > 0, previewSize.height > 0 else { return }
        let normalized = CGPoint(
            x: min(max(point.x / previewSize.width, 0), 1),
            y: min(max(point.y / previewSize.height, 0), 1)
        )

        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoInput?.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = normalized
                    device.focusMode = .continuousAutoFocus
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = normalized
                    device.exposureMode = .continuousAutoExposure
                }
                device.unlockForConfiguration()
            } catch {
                DispatchQueue.main.async {
                    self.statusMessage = "Focus is temporarily unavailable"
                }
            }
        }
    }

    private func configureIfNeeded() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.isSessionConfigured {
                if !self.session.isRunning {
                    self.session.startRunning()
                    DispatchQueue.main.async { self.isRunning = true }
                }
                return
            }

            self.session.beginConfiguration()

            guard self.session.canSetSessionPreset(.photo) else {
                self.session.commitConfiguration()
                DispatchQueue.main.async { self.statusMessage = "Photo capture is unavailable" }
                return
            }
            self.session.sessionPreset = .photo
            var depthAvailable = false
            var matteAvailable = false

            do {
                let camera = try self.makeRearCamera()
                let input = try AVCaptureDeviceInput(device: camera)
                guard self.session.canAddInput(input) else { throw CameraError.unavailable }
                self.session.addInput(input)
                self.videoInput = input

                guard self.session.canAddOutput(self.photoOutput) else { throw CameraError.unavailable }
                self.session.addOutput(self.photoOutput)
                self.photoOutput.maxPhotoQualityPrioritization = .quality

                if self.photoOutput.isDepthDataDeliverySupported {
                    self.photoOutput.isDepthDataDeliveryEnabled = true
                }
                if self.photoOutput.isPortraitEffectsMatteDeliverySupported {
                    self.photoOutput.isPortraitEffectsMatteDeliveryEnabled = true
                }

                depthAvailable = self.photoOutput.isDepthDataDeliveryEnabled
                matteAvailable = self.photoOutput.isPortraitEffectsMatteDeliveryEnabled
                self.deviceMaxZoomFactor = max(1.0, min(camera.activeFormat.videoMaxZoomFactor, displayMaxZoomFactor))
                self.isSessionConfigured = true
            } catch {
                self.session.commitConfiguration()
                self.videoInput = nil
                DispatchQueue.main.async {
                    self.statusMessage = "Camera setup failed"
                }
                return
            }

            // Commit before starting. AVFoundation requires startRunning()
            // to happen outside beginConfiguration()/commitConfiguration().
            self.session.commitConfiguration()
            self.session.startRunning()

            DispatchQueue.main.async {
                self.depthCaptureAvailable = depthAvailable
                self.portraitMatteAvailable = matteAvailable
                self.isConfigured = true
                self.isRunning = true
                self.deviceZoomFactor = 1.0
                self.zoomFactor = 1.0
            }
        }
    }

    private func makeRearCamera() throws -> AVCaptureDevice {
        if let dualWide = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) {
            return dualWide
        }
        if let wide = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            return wide
        }
        throw CameraError.unavailable
    }

    private func saveToPhotos(data: Data) {
        let save: () -> Void = { [weak self] in
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            }) { success, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isCapturing = false
                    if success {
                        self.statusMessage = "Portrait saved to Photos"
                    } else {
                        self.statusMessage = error?.localizedDescription ?? "Could not save photo"
                    }
                }
            }
        }

        switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
        case .authorized, .limited:
            save()
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                if status == .authorized || status == .limited {
                    save()
                } else {
                    DispatchQueue.main.async {
                        self.isCapturing = false
                        self.statusMessage = "Photos permission is required"
                    }
                }
            }
        default:
            DispatchQueue.main.async {
                self.isCapturing = false
                self.statusMessage = "Photos permission is required"
            }
        }
    }

    private func finishCapture(with message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.isCapturing = false
            self?.statusMessage = message
        }
    }
}

extension CameraModel: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            finishCapture(with: error.localizedDescription)
            return
        }

        guard let data = photo.fileDataRepresentation() else {
            finishCapture(with: "Could not create the photo file")
            return
        }

        saveToPhotos(data: data)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if let error {
            finishCapture(with: error.localizedDescription)
        }
    }
}

enum CameraError: Error {
    case unavailable
}
