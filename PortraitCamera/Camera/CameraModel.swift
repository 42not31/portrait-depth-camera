import AVFoundation
import Photos
import SwiftUI

final class CameraModel: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published private(set) var isConfigured = false
    @Published private(set) var isRunning = false
    @Published private(set) var isCapturing = false
    @Published private(set) var zoomFactor: CGFloat = 1.0
    @Published private(set) var depthCaptureAvailable = false
    @Published private(set) var portraitMatteAvailable = false
    @Published var permissionDenied = false
    @Published var statusMessage: String?

    private let sessionQueue = DispatchQueue(label: "com.privateportrait.camera.session")
    private let photoOutput = AVCapturePhotoOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var maxZoomFactor: CGFloat = 3.0
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
            permissionDenied = true
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

        DispatchQueue.main.async { self.isCapturing = true }
        sessionQueue.async { [weak self] in
            guard let self else { return }

            let settings: AVCapturePhotoSettings
            if self.photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            } else {
                settings = AVCapturePhotoSettings()
            }

            if self.videoInput?.device.hasFlash == true {
                settings.flashMode = .off
            }

            settings.photoQualityPrioritization = .quality
            settings.isHighResolutionPhotoEnabled = true

            if self.photoOutput.isDepthDataDeliverySupported {
                settings.isDepthDataDeliveryEnabled = self.photoOutput.isDepthDataDeliveryEnabled
                settings.embedsDepthDataInPhoto = settings.isDepthDataDeliveryEnabled
            }
            if self.photoOutput.isPortraitEffectsMatteDeliverySupported {
                settings.isPortraitEffectsMatteDeliveryEnabled = self.photoOutput.isPortraitEffectsMatteDeliveryEnabled
                settings.embedsPortraitEffectsMatteInPhoto = settings.isPortraitEffectsMatteDeliveryEnabled
            }

            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func setZoomFactor(_ requestedFactor: CGFloat) {
        let clamped = min(max(requestedFactor, 1.0), maxZoomFactor)
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoInput?.device else { return }
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
                DispatchQueue.main.async { self.zoomFactor = clamped }
            } catch {
                DispatchQueue.main.async {
                    self.statusMessage = "Zoom is temporarily unavailable"
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
            self.session.sessionPreset = .photo

            do {
                let camera = self.makeRearCamera()
                let input = try AVCaptureDeviceInput(device: camera)
                guard self.session.canAddInput(input) else {
                    throw CameraError.unavailable
                }
                self.session.addInput(input)
                self.videoInput = input

                guard self.session.canAddOutput(self.photoOutput) else {
                    throw CameraError.unavailable
                }
                self.session.addOutput(self.photoOutput)
                self.photoOutput.maxPhotoQualityPrioritization = .quality
                if self.photoOutput.isDepthDataDeliverySupported {
                    self.photoOutput.isDepthDataDeliveryEnabled = true
                }
                if self.photoOutput.isPortraitEffectsMatteDeliverySupported {
                    self.photoOutput.isPortraitEffectsMatteDeliveryEnabled = true
                }

                self.depthCaptureAvailable = self.photoOutput.isDepthDataDeliveryEnabled
                self.portraitMatteAvailable = self.photoOutput.isPortraitEffectsMatteDeliveryEnabled
                self.maxZoomFactor = min(camera.activeFormat.videoMaxZoomFactor, 3.0)
                self.isSessionConfigured = true
                self.session.commitConfiguration()
                self.session.startRunning()

                DispatchQueue.main.async {
                    self.isConfigured = true
                    self.isRunning = true
                }
            } catch {
                self.session.commitConfiguration()
                DispatchQueue.main.async {
                    self.statusMessage = "Camera setup failed"
                }
            }
        }
    }

    private func makeRearCamera() -> AVCaptureDevice {
        if let dualWide = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) {
            return dualWide
        }
        if let wide = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            return wide
        }
        fatalError("No rear camera is available")
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
                        self.statusMessage = error == nil ? "Could not save photo" : "Photos permission is required"
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
}

extension CameraModel: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            DispatchQueue.main.async {
                self.isCapturing = false
                self.statusMessage = error.localizedDescription
            }
            return
        }

        guard let data = photo.fileDataRepresentation() else {
            DispatchQueue.main.async {
                self.isCapturing = false
                self.statusMessage = "Could not create the photo file"
            }
            return
        }

        saveToPhotos(data: data)
    }
}

enum CameraError: Error {
    case unavailable
}
