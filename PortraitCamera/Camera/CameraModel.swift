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
    private let displayMaxZoomFactor: CGFloat = 2.0
    private var isSessionConfigured = false
    private var captureInFlight = false

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
        guard isConfigured, isRunning, !isCapturing else { return }

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
            guard !self.captureInFlight else { return }
            self.captureInFlight = true

            // A new settings object is required for every capture. Keep the
            // base settings intentionally conservative; AVFoundation chooses
            // the compatible processed photo format for this device/format.
            let settings = AVCapturePhotoSettings()

            if self.photoOutput.supportedFlashModes.contains(.off) {
                settings.flashMode = .off
            }

            // Depth and Portrait Effects matte delivery are requested only
            // after the output has confirmed that they are enabled. Matte is
            // additionally dependent on depth, as required by AVFoundation.
            let useDepth = self.photoOutput.isDepthDataDeliverySupported
                && self.photoOutput.isDepthDataDeliveryEnabled
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

            DispatchQueue.main.async { self.isCapturing = true }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func setZoomFactor(_ requestedFactor: CGFloat) {
        let desired = min(max(requestedFactor, 1.0), displayMaxZoomFactor)

        DispatchQueue.main.async { [weak self] in
            self?.zoomFactor = desired
        }

        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoInput?.device else { return }
            let minimumZoom = max(1.0, device.minAvailableVideoZoomFactor)
            let hardwareZoom = min(
                max(desired, minimumZoom),
                max(minimumZoom, self.deviceMaxZoomFactor)
            )
            do {
                try device.lockForConfiguration()
                if device.isRampingVideoZoom {
                    device.cancelVideoZoomRamp()
                }
                device.videoZoomFactor = hardwareZoom
                device.unlockForConfiguration()
                DispatchQueue.main.async {
                    self.deviceZoomFactor = hardwareZoom
                    if desired > hardwareZoom + 0.01 {
                        self.statusMessage = "2× software framing"
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.deviceZoomFactor = 1.0
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
            guard self.session.canSetSessionPreset(.photo) else {
                self.session.commitConfiguration()
                DispatchQueue.main.async { self.statusMessage = "Photo capture is unavailable" }
                return
            }
            self.session.sessionPreset = .photo

            var depthAvailable = false
            var matteAvailable = false

            do {
                // Use the rear dual-wide virtual camera so AVFoundation can
                // measure disparity and embed genuine depth for Photos Portrait
                // editing. The iPhone 13 has no telephoto; 2× remains crop or
                // virtual-device framing rather than a true telephoto lens.
                let camera = try self.makeRearCamera()
                let input = try AVCaptureDeviceInput(device: camera)
                guard self.session.canAddInput(input) else { throw CameraError.unavailable }
                self.session.addInput(input)
                self.videoInput = input

                guard self.session.canAddOutput(self.photoOutput) else { throw CameraError.unavailable }
                self.session.addOutput(self.photoOutput)

                if self.photoOutput.isDepthDataDeliverySupported {
                    self.photoOutput.isDepthDataDeliveryEnabled = true
                }
                if self.photoOutput.isDepthDataDeliveryEnabled,
                   self.photoOutput.isPortraitEffectsMatteDeliverySupported {
                    self.photoOutput.isPortraitEffectsMatteDeliveryEnabled = true
                }

                depthAvailable = self.photoOutput.isDepthDataDeliveryEnabled
                matteAvailable = self.photoOutput.isPortraitEffectsMatteDeliveryEnabled
                // Depth delivery can change the usable zoom range on a
                // virtual camera. Read the live bounds only after enabling
                // depth, rather than using activeFormat.videoMaxZoomFactor.
                self.deviceMaxZoomFactor = max(
                    1.0,
                    min(camera.maxAvailableVideoZoomFactor, displayMaxZoomFactor)
                )
                self.isSessionConfigured = true
            } catch {
                self.session.commitConfiguration()
                self.videoInput = nil
                DispatchQueue.main.async {
                    self.statusMessage = "Camera setup failed"
                }
                return
            }

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
        // Apple documents builtInDualWideCamera as the rear virtual device
        // that measures disparity between wide and ultrawide cameras.
        if let dualWide = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) {
            return dualWide
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
                    self.captureInFlight = false
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
                        self.captureInFlight = false
                        self.statusMessage = "Photos permission is required"
                    }
                }
            }
        default:
            DispatchQueue.main.async {
                self.isCapturing = false
                self.captureInFlight = false
                self.statusMessage = "Photos permission is required"
            }
        }
    }

    private func finishCapture(with message: String) {
        sessionQueue.async { [weak self] in
            self?.captureInFlight = false
        }
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
