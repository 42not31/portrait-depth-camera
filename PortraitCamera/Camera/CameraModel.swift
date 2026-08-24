import AVFoundation
import CoreImage
import ImageIO
import Photos
import SwiftUI
import UniformTypeIdentifiers

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
    private let ciContext = CIContext()
    private var videoInput: AVCaptureDeviceInput?
    private let displayMaxZoomFactor: CGFloat = 2.0
    private var isSessionConfigured = false
    private var captureInFlight = false
    private var softwareZoomFactor: CGFloat = 1.0
    private var activeCaptureZoomFactor: CGFloat = 1.0

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
            self.activeCaptureZoomFactor = self.softwareZoomFactor

            // A fresh, conservative settings object avoids unsupported
            // combinations while still allowing AVFoundation to attach its
            // native depth and Portrait Effects matte data.
            let settings = AVCapturePhotoSettings()
            if self.photoOutput.supportedFlashModes.contains(.off) {
                settings.flashMode = .off
            }

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

        // This is intentionally software-only. Do not set
        // AVCaptureDevice.videoZoomFactor: enabling depth on a virtual camera
        // can clamp or alter its available hardware zoom range. The preview
        // and the saved primary image are both cropped at the requested state.
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.softwareZoomFactor = desired
            DispatchQueue.main.async {
                self.zoomFactor = desired
                self.deviceZoomFactor = 1.0
                self.statusMessage = desired > 1.01 ? "2× software framing" : nil
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
                // The iPhone 13 rear dual-wide virtual camera is required for
                // genuine dual-camera disparity/depth capture. Zoom itself is
                // deliberately not configured on this device input.
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
        if let dualWide = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) {
            return dualWide
        }
        throw CameraError.unavailable
    }

    private func saveToPhotos(data: Data, zoomFactor: CGFloat) {
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
                        self.statusMessage = zoomFactor > 1.01
                            ? "Portrait saved at 2× software crop"
                            : "Portrait saved to Photos"
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

    private func softwareZoomedFileData(for photo: AVCapturePhoto, factor: CGFloat) -> Data? {
        guard factor > 1.01 else { return photo.fileDataRepresentation() }
        guard let primaryImage = photo.cgImageRepresentation() else {
            return photo.fileDataRepresentation()
        }

        let normalizedCrop = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let cropRect = CGRect(
            x: CGFloat(primaryImage.width) * normalizedCrop.minX,
            y: CGFloat(primaryImage.height) * normalizedCrop.minY,
            width: CGFloat(primaryImage.width) * normalizedCrop.width,
            height: CGFloat(primaryImage.height) * normalizedCrop.height
        ).integral

        guard let croppedImage = primaryImage.cropping(to: cropRect) else {
            return photo.fileDataRepresentation()
        }

        let croppedDepth: AVDepthData?
        if let depth = photo.depthData,
           let croppedMap = cropPixelBuffer(depth.depthDataMap, normalizedRect: normalizedCrop) {
            croppedDepth = try? depth.replacingDepthDataMap(with: croppedMap)
        } else {
            croppedDepth = nil
        }

        let croppedMatte: AVPortraitEffectsMatte?
        if let matte = photo.portraitEffectsMatte,
           let croppedMap = cropPixelBuffer(matte.mattingImage, normalizedRect: normalizedCrop) {
            croppedMatte = try? matte.replacingPortraitEffectsMatte(with: croppedMap)
        } else {
            croppedMatte = nil
        }

        guard let croppedData = packageImage(
            croppedImage,
            metadata: photo.metadata,
            depth: croppedDepth,
            matte: croppedMatte
        ) else {
            // Never discard a genuine Portrait capture merely because a
            // derivative software crop could not be packaged on this OS.
            return photo.fileDataRepresentation()
        }
        return croppedData
    }

    private func cropPixelBuffer(_ source: CVPixelBuffer, normalizedRect: CGRect) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        guard width > 1, height > 1 else { return nil }

        let cropRect = CGRect(
            x: CGFloat(width) * normalizedRect.minX,
            y: CGFloat(height) * normalizedRect.minY,
            width: CGFloat(width) * normalizedRect.width,
            height: CGFloat(height) * normalizedRect.height
        ).integral
        guard cropRect.width > 1, cropRect.height > 1 else { return nil }

        let pixelFormat = CVPixelBufferGetPixelFormatType(source)
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        var destination: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(cropRect.width),
            Int(cropRect.height),
            pixelFormat,
            attributes as CFDictionary,
            &destination
        )
        guard status == kCVReturnSuccess, let destination else { return nil }

        let image = CIImage(cvPixelBuffer: source).cropped(to: cropRect)
        ciContext.render(image, to: destination)
        return destination
    }

    private func packageImage(
        _ image: CGImage,
        metadata: [String: Any],
        depth: AVDepthData?,
        matte: AVPortraitEffectsMatte?
    ) -> Data? {
        let data = NSMutableData()
        let imageType: CFString = UTType.heic.identifier as CFString
        guard let destination = CGImageDestinationCreateWithData(data, imageType, 1, nil) else {
            return nil
        }

        CGImageDestinationAddImage(destination, image, metadata as CFDictionary)

        if let depth,
           var auxiliaryType: NSString? = nil,
           let auxiliaryInfo = depth.dictionaryRepresentation(forAuxiliaryDataType: &auxiliaryType),
           let auxiliaryType {
            CGImageDestinationAddAuxiliaryDataInfo(
                destination,
                auxiliaryType as CFString,
                auxiliaryInfo as CFDictionary
            )
        }

        if let matte,
           var auxiliaryType: NSString? = nil,
           let auxiliaryInfo = matte.dictionaryRepresentation(forAuxiliaryDataType: &auxiliaryType),
           let auxiliaryType {
            CGImageDestinationAddAuxiliaryDataInfo(
                destination,
                auxiliaryType as CFString,
                auxiliaryInfo as CFDictionary
            )
        }

        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}

extension CameraModel: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            finishCapture(with: error.localizedDescription)
            return
        }

        let zoom = activeCaptureZoomFactor
        guard let data = softwareZoomedFileData(for: photo, factor: zoom) else {
            finishCapture(with: "Could not create the photo file")
            return
        }

        saveToPhotos(data: data, zoomFactor: zoom)
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
