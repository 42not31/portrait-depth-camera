import AVFoundation
import ImageIO
import Photos
import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class CameraModel: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published private(set) var isConfigured = false
    @Published private(set) var isRunning = false
    @Published private(set) var isCapturing = false
    @Published private(set) var zoomFactor: CGFloat = 1.0
    @Published private(set) var deviceZoomFactor: CGFloat = 1.0
    @Published private(set) var captureMode: CaptureMode = .portrait
    @Published private(set) var photoLens: PhotoLens = .wide
    @Published private(set) var photoFlashMode: PhotoFlashMode = .off
    @Published private(set) var photoAspectRatio: PhotoAspectRatio = .fourThree
    @Published private(set) var manualControlsEnabled = false
    @Published private(set) var manualFocusPosition: Float = 0.5
    @Published private(set) var exposureBias: Float = 0.0
    @Published private(set) var videoOrientation: AVCaptureVideoOrientation = .portrait
    @Published private(set) var latestPhotoImage: UIImage?
    @Published private(set) var latestPhotoAssetIdentifier: String?
    @Published private(set) var isUsingFrontCamera = false
    @Published var permissionDenied = false
    @Published var statusMessage: String?

    private let sessionQueue = DispatchQueue(label: "com.privateportrait.camera.session")
    private let photoOutput = AVCapturePhotoOutput()
    private var videoInput: AVCaptureDeviceInput?
    private let maxPhotoSoftwareZoomFactor: CGFloat = 5.0
    private var isSessionConfigured = false
    private var captureInFlight = false
    private var softwareZoomFactor: CGFloat = 1.0
    private var activeCaptureZoomFactor: CGFloat = 1.0
    private var activeCaptureMode: CaptureMode = .portrait
    private var activeCaptureAspectRatio: PhotoAspectRatio = .fourThree
    private var activeCaptureFlashMode: PhotoFlashMode = .off
    private var activeVideoOrientation: AVCaptureVideoOrientation = .portrait
    private var activeCameraPosition: AVCaptureDevice.Position = .back
    private var mirrorFrontCamera = true
    private var orientationObserver: NSObjectProtocol?
    private var backgroundObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?

    override init() {
        super.init()
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        updateOrientation(for: UIDevice.current.orientation)
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateOrientation(for: UIDevice.current.orientation)
        }
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.stop() }
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.start() }
    }

    deinit {
        if let orientationObserver { NotificationCenter.default.removeObserver(orientationObserver) }
        if let backgroundObserver { NotificationCenter.default.removeObserver(backgroundObserver) }
        if let foregroundObserver { NotificationCenter.default.removeObserver(foregroundObserver) }
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

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
        let requestedMode = captureMode
        let requestedAspectRatio = photoAspectRatio
        let requestedFlashMode = photoFlashMode

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
            self.applyVideoOrientation()
            self.activeCaptureZoomFactor = self.softwareZoomFactor
            self.activeCaptureMode = requestedMode
            self.activeCaptureAspectRatio = requestedAspectRatio
            self.activeCaptureFlashMode = requestedFlashMode
            DispatchQueue.main.async { self.isCapturing = true }
            self.captureSinglePhoto(flashMode: requestedFlashMode)
        }
    }

    private func makePhotoSettings(flashMode: PhotoFlashMode) -> AVCapturePhotoSettings {
        let settings = AVCapturePhotoSettings()
        if photoOutput.maxPhotoQualityPrioritization == .quality {
            settings.photoQualityPrioritization = .quality
        }
        let requestedFlash = flashMode.captureMode
        if photoOutput.supportedFlashModes.contains(requestedFlash) {
            settings.flashMode = requestedFlash
            if requestedFlash == .on {
                settings.isAutoStillImageStabilizationEnabled = false
            }
        } else if photoOutput.supportedFlashModes.contains(.off) {
            settings.flashMode = .off
        }

        return settings
    }

    private func captureSinglePhoto(flashMode: PhotoFlashMode) {
        photoOutput.capturePhoto(
            with: makePhotoSettings(flashMode: flashMode),
            delegate: self
        )
    }

    func setCaptureMode(_ mode: CaptureMode) {
        sessionQueue.async { [weak self] in
            guard let self, self.isSessionConfigured, self.captureMode != mode else { return }
            do {
                try self.replaceCameraInput(for: mode)
                self.configurePhotoOutput(for: mode)

                if mode == .portrait {
                    self.softwareZoomFactor = min(
                        self.softwareZoomFactor,
                        self.maximumSoftwareZoomFactor(for: mode)
                    )
                }

                DispatchQueue.main.async {
                    self.captureMode = mode
                    self.zoomFactor = self.softwareZoomFactor
                }
            } catch {
                DispatchQueue.main.async {
                    self.statusMessage = mode == .photo
                        ? "Photo lens is unavailable"
                        : "Portrait camera is unavailable"
                }
            }
        }
    }

    func setPhotoLens(_ lens: PhotoLens) {
        guard captureMode == .photo, !isUsingFrontCamera else { return }
        sessionQueue.async { [weak self] in
            guard let self, self.isSessionConfigured, self.photoLens != lens else { return }
            do {
                try self.replaceCameraInput(for: .photo, lens: lens)
                DispatchQueue.main.async { self.photoLens = lens }
            } catch {
                DispatchQueue.main.async { self.statusMessage = "This lens is unavailable" }
            }
        }
    }

    func setPhotoFlashMode(_ mode: PhotoFlashMode) {
        DispatchQueue.main.async { [weak self] in self?.photoFlashMode = mode }
    }

    func setPhotoAspectRatio(_ ratio: PhotoAspectRatio) {
        guard captureMode == .photo else { return }
        DispatchQueue.main.async { [weak self] in self?.photoAspectRatio = ratio }
    }

    func toggleCamera() {
        sessionQueue.async { [weak self] in
            guard let self, self.isSessionConfigured, !self.captureInFlight else { return }
            let previousPosition = self.activeCameraPosition
            self.activeCameraPosition = previousPosition == .back ? .front : .back

            do {
                try self.replaceCameraInput(for: self.captureMode)
                self.configurePhotoOutput(for: self.captureMode)
                self.softwareZoomFactor = 1.0

                DispatchQueue.main.async {
                    self.isUsingFrontCamera = self.activeCameraPosition == .front
                    self.zoomFactor = self.softwareZoomFactor
                    self.deviceZoomFactor = 1.0
                    self.statusMessage = nil
                }
            } catch {
                self.activeCameraPosition = previousPosition
                DispatchQueue.main.async {
                    self.statusMessage = self.captureMode == .portrait
                        ? "Front Portrait camera is unavailable"
                        : "Front camera is unavailable"
                }
            }
        }
    }

    func setFrontCameraMirroring(_ enabled: Bool) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.mirrorFrontCamera = enabled
            self.applyPhotoOutputMirroring()
        }
    }

    func setManualControlsEnabled(_ enabled: Bool) {
        sessionQueue.async { [weak self] in
            guard let self, self.isSessionConfigured, let device = self.videoInput?.device else { return }
            do {
                try device.lockForConfiguration()
                if enabled {
                    let canLockPhotoFocus = self.captureMode == .photo
                        && self.photoLens == .wide
                        && device.isLockingFocusWithCustomLensPositionSupported
                    if canLockPhotoFocus {
                        device.setFocusModeLocked(lensPosition: self.manualFocusPosition, completionHandler: nil)
                    }
                    if device.minExposureTargetBias < device.maxExposureTargetBias {
                        device.setExposureTargetBias(self.exposureBias, completionHandler: nil)
                    }
                } else {
                    if device.isFocusModeSupported(.continuousAutoFocus) {
                        device.focusMode = .continuousAutoFocus
                    }
                    if device.isExposureModeSupported(.continuousAutoExposure) {
                        device.exposureMode = .continuousAutoExposure
                    }
                }
                device.unlockForConfiguration()
                DispatchQueue.main.async { self.manualControlsEnabled = enabled }
            } catch {
                DispatchQueue.main.async { self.statusMessage = "Manual controls are unavailable" }
            }
        }
    }

    func setManualFocusPosition(_ position: Float) {
        let clamped = min(max(position, 0), 1)
        DispatchQueue.main.async { [weak self] in self?.manualFocusPosition = clamped }
        guard manualControlsEnabled, captureMode == .photo, photoLens == .wide else { return }
        sessionQueue.async { [weak self] in
            guard let self, self.isSessionConfigured, let device = self.videoInput?.device,
                  device.isLockingFocusWithCustomLensPositionSupported else { return }
            do {
                try device.lockForConfiguration()
                device.setFocusModeLocked(lensPosition: clamped, completionHandler: nil)
                device.unlockForConfiguration()
            } catch {
                DispatchQueue.main.async { self.statusMessage = "Manual focus is unavailable" }
            }
        }
    }

    func setExposureBias(_ bias: Float) {
        let clamped = min(max(bias, -2.0), 2.0)
        DispatchQueue.main.async { [weak self] in self?.exposureBias = clamped }
        guard manualControlsEnabled else { return }
        sessionQueue.async { [weak self] in
            guard let self, self.isSessionConfigured, let device = self.videoInput?.device,
                  device.minExposureTargetBias < device.maxExposureTargetBias else { return }
            do {
                try device.lockForConfiguration()
                device.setExposureTargetBias(clamped, completionHandler: nil)
                device.unlockForConfiguration()
            } catch {
                DispatchQueue.main.async { self.statusMessage = "Manual exposure is unavailable" }
            }
        }
    }

    func setZoomFactor(_ requestedFactor: CGFloat) {
        let maximum = maximumSoftwareZoomFactor(for: captureMode)
        let desired = min(max(requestedFactor, 1.0), maximum)

        // Keep the crop software-based so the preview and saved image stay aligned.
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.softwareZoomFactor = desired
            DispatchQueue.main.async {
                self.zoomFactor = desired
                self.deviceZoomFactor = 1.0
            }
        }
    }

    func focus(at devicePoint: CGPoint) {
        if manualControlsEnabled { return }
        let point = CGPoint(
            x: min(max(devicePoint.x, 0), 1),
            y: min(max(devicePoint.y, 0), 1)
        )

        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoInput?.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = point
                    device.focusMode = .continuousAutoFocus
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = point
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

    private func updateOrientation(for deviceOrientation: UIDeviceOrientation) {
        let mappedOrientation: AVCaptureVideoOrientation
        switch deviceOrientation {
        case .landscapeLeft:
            // UIDevice orientation is viewed from the back of the phone;
            // capture orientation is therefore the opposite landscape side.
            mappedOrientation = .landscapeRight
        case .landscapeRight:
            mappedOrientation = .landscapeLeft
        case .portraitUpsideDown:
            mappedOrientation = .portraitUpsideDown
        case .portrait:
            mappedOrientation = .portrait
        default:
            return
        }

        guard videoOrientation != mappedOrientation else { return }
        videoOrientation = mappedOrientation
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.activeVideoOrientation = mappedOrientation
            self.applyVideoOrientation()
        }
    }

    private func applyVideoOrientation() {
        guard let connection = photoOutput.connection(with: .video),
              connection.isVideoOrientationSupported else { return }
        connection.videoOrientation = activeVideoOrientation
    }

    private func applyPhotoOutputMirroring() {
        guard let connection = photoOutput.connection(with: .video),
              connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = activeCameraPosition == .front && mirrorFrontCamera
    }

    private func configurePhotoOutput(
        for mode: CaptureMode,
        withinExistingSessionConfiguration: Bool = false
    ) {
        if !withinExistingSessionConfiguration {
            session.beginConfiguration()
        }
        applyVideoOrientation()
        applyPhotoOutputMirroring()
        if !withinExistingSessionConfiguration {
            session.commitConfiguration()
        }
    }

    private func maximumSoftwareZoomFactor(for mode: CaptureMode) -> CGFloat {
        if activeCameraPosition == .front {
            return mode == .portrait ? 1.5 : 2.0
        }
        return mode == .photo ? maxPhotoSoftwareZoomFactor : 2.0
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

            do {
                // Use the dual-wide rear camera for the best native Portrait framing.
                let camera = try self.makeCamera(for: .portrait)
                let input = try AVCaptureDeviceInput(device: camera)
                guard self.session.canAddInput(input) else { throw CameraError.unavailable }
                self.session.addInput(input)
                self.videoInput = input

                guard self.session.canAddOutput(self.photoOutput) else { throw CameraError.unavailable }
                self.session.addOutput(self.photoOutput)
                self.applyVideoOrientation()
                self.applyPhotoOutputMirroring()
                self.photoOutput.maxPhotoQualityPrioritization = .quality

                self.configurePhotoOutput(
                    for: .portrait,
                    withinExistingSessionConfiguration: true
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
                self.isConfigured = true
                self.isRunning = true
                self.deviceZoomFactor = 1.0
                self.zoomFactor = 1.0
                self.isUsingFrontCamera = false
            }
        }
    }

    private func makeCamera(for mode: CaptureMode, lens: PhotoLens? = nil) throws -> AVCaptureDevice {
        if activeCameraPosition == .front,
           let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
            return frontCamera
        }

        if mode == .portrait,
           let dualWide = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) {
            return dualWide
        }

        let requestedType = lens?.deviceType ?? photoLens.deviceType
        if let camera = AVCaptureDevice.default(requestedType, for: .video, position: .back) {
            return camera
        }
        throw CameraError.unavailable
    }

    private func replaceCameraInput(for mode: CaptureMode, lens: PhotoLens? = nil) throws {
        let camera = try makeCamera(for: mode, lens: lens)
        let newInput = try AVCaptureDeviceInput(device: camera)
        let oldInput = videoInput

        session.beginConfiguration()
        if let oldInput { session.removeInput(oldInput) }
        guard session.canAddInput(newInput) else {
            if let oldInput { session.addInput(oldInput) }
            session.commitConfiguration()
            throw CameraError.unavailable
        }
        session.addInput(newInput)
        session.commitConfiguration()
        videoInput = newInput
    }

    private func saveToPhotos(data: Data) {
        let latestThumbnail = makeLatestThumbnail(from: data)
        let save: () -> Void = { [weak self] in
            var placeholderIdentifier: String?
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                placeholderIdentifier = request.placeholderForCreatedAsset?.localIdentifier
                request.addResource(with: .photo, data: data, options: nil)
            }) { success, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isCapturing = false
                    self.captureInFlight = false
                    if success {
                        self.latestPhotoImage = latestThumbnail
                        self.latestPhotoAssetIdentifier = placeholderIdentifier
                        self.statusMessage = nil
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

    private func makeLatestThumbnail(from data: Data) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 320
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else {
            return UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 320, height: 320))
        }
        return UIImage(cgImage: image)
    }

    func openLatestPhotoInPhotos() {
        // There is no documented public API to deep-link to one PHAsset in Photos.
        // Avoid the unstable photos-navigation asset URLs: on some iOS builds they
        // can make Photos terminate while transitioning. Open Photos itself only.
        guard let photosURL = URL(string: "photos-redirect://") else { return }

        DispatchQueue.main.async { [weak self] in
            UIApplication.shared.open(photosURL, options: [:]) { opened in
                if !opened {
                    self?.statusMessage = "Photos could not be opened"
                }
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

    private func softwareZoomedFileData(
        for photo: AVCapturePhoto,
        factor: CGFloat,
        aspectRatio: PhotoAspectRatio
    ) -> Data? {
        guard factor > 1.01 || aspectRatio != .fourThree else {
            return photo.fileDataRepresentation()
        }
        guard let primaryImage = photo.cgImageRepresentation() else {
            return photo.fileDataRepresentation()
        }

        let sourceAspectRatio = CGFloat(primaryImage.width) / CGFloat(primaryImage.height)
        // The primary image is landscape before its EXIF orientation is applied.
        // Crop to the selected sensor ratio so an upright 9:16 Photo remains
        // upright once Photos applies the capture orientation metadata.
        let targetAspectRatio = aspectRatio.value
        var cropWidth = 1.0
        var cropHeight = 1.0
        if sourceAspectRatio > targetAspectRatio {
            cropWidth = targetAspectRatio / sourceAspectRatio
        } else if sourceAspectRatio < targetAspectRatio {
            cropHeight = sourceAspectRatio / targetAspectRatio
        }

        let zoomScale = max(1.0 / factor, 0.05)
        cropWidth *= zoomScale
        cropHeight *= zoomScale
        let cropOriginX = (1.0 - cropWidth) / 2.0
        let cropOriginY = (1.0 - cropHeight) / 2.0
        let normalizedCrop = CGRect(
            x: cropOriginX,
            y: cropOriginY,
            width: cropWidth,
            height: cropHeight
        )
        let cropRect = CGRect(
            x: CGFloat(primaryImage.width) * normalizedCrop.minX,
            y: CGFloat(primaryImage.height) * normalizedCrop.minY,
            width: CGFloat(primaryImage.width) * normalizedCrop.width,
            height: CGFloat(primaryImage.height) * normalizedCrop.height
        ).integral

        guard let croppedImage = primaryImage.cropping(to: cropRect) else {
            return photo.fileDataRepresentation()
        }

        let metadata = croppedMetadata(
            from: photo.metadata,
            width: croppedImage.width,
            height: croppedImage.height
        )
        return packageImage(croppedImage, metadata: metadata) ?? photo.fileDataRepresentation()
    }

    private func croppedMetadata(from original: [String: Any], width: Int, height: Int) -> [String: Any] {
        var result = original
        result[kCGImagePropertyPixelWidth as String] = width
        result[kCGImagePropertyPixelHeight as String] = height

        if let originalExif = original[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            var exif = originalExif
            exif[kCGImagePropertyExifPixelXDimension as String] = width
            exif[kCGImagePropertyExifPixelYDimension as String] = height
            result[kCGImagePropertyExifDictionary as String] = exif
        }
        return result
    }

    private func packageImage(
        _ image: CGImage,
        metadata: [String: Any]
    ) -> Data? {
        let data = NSMutableData()
        let imageType: CFString = UTType.heic.identifier as CFString
        guard let destination = CGImageDestinationCreateWithData(data, imageType, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, metadata as CFDictionary)
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
        guard let data = softwareZoomedFileData(
            for: photo,
            factor: zoom,
            aspectRatio: activeCaptureAspectRatio
        ) else {
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
