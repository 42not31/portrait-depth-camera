import AVFoundation
import CoreImage
import ImageIO
import Photos
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct PhotoStyleAdjustment: Equatable {
    var tone: Double = 0       // -100...100, shadow/highlight balance
    var color: Double = 0      // -100...100, warm/cool tint
    var palette: Double = 50   // 0...100, hue rotation (50 = neutral)

    static let neutral = PhotoStyleAdjustment()

    var isNeutral: Bool {
        abs(tone) < 0.5 && abs(color) < 0.5 && abs(palette - 50) < 0.5
    }
}

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
    @Published private(set) var depthCaptureAvailable = false
    @Published private(set) var portraitMatteAvailable = false
    @Published private(set) var isUsingFrontCamera = false
    @Published var permissionDenied = false
    @Published var statusMessage: String?
    @Published private(set) var portraitAperture: CGFloat = 2.8
    @Published private(set) var styleAdjustment = PhotoStyleAdjustment()

    private let sessionQueue = DispatchQueue(label: "com.privateportrait.camera.session")
    private let photoOutput = AVCapturePhotoOutput()
    private let ciContext = CIContext()
    private var videoInput: AVCaptureDeviceInput?
    private let maxPhotoSoftwareZoomFactor: CGFloat = 5.0
    private var isSessionConfigured = false
    private var captureInFlight = false
    private var softwareZoomFactor: CGFloat = 1.0
    private var activeCaptureZoomFactor: CGFloat = 1.0
    private var activeCaptureMode: CaptureMode = .portrait
    private var activeCaptureAspectRatio: PhotoAspectRatio = .fourThree
    private var activeCaptureFlashMode: PhotoFlashMode = .off
    private var activeCaptureAperture: CGFloat = 2.8
    private var activeCaptureStyle = PhotoStyleAdjustment()
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
        let requestedDepthAperture: CGFloat = portraitAperture
        let requestedStyle: PhotoStyleAdjustment = styleAdjustment

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
            self.activeCaptureAperture = requestedDepthAperture
            self.activeCaptureStyle = requestedStyle
            DispatchQueue.main.async { self.isCapturing = true }
            self.captureSinglePhoto(
                includePortraitData: requestedMode == .portrait,
                flashMode: requestedFlashMode
            )
        }
    }

    private func makePhotoSettings(
        includePortraitData: Bool,
        flashMode: PhotoFlashMode
    ) -> AVCapturePhotoSettings {
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

        let useDepth = includePortraitData
            && photoOutput.isDepthDataDeliverySupported
            && photoOutput.isDepthDataDeliveryEnabled
        if useDepth {
            settings.isDepthDataDeliveryEnabled = true
            settings.embedsDepthDataInPhoto = true
        }

        let usePortraitMatte = useDepth
            && photoOutput.isPortraitEffectsMatteDeliverySupported
            && photoOutput.isPortraitEffectsMatteDeliveryEnabled
        if usePortraitMatte {
            settings.isPortraitEffectsMatteDeliveryEnabled = true
            settings.embedsPortraitEffectsMatteInPhoto = true
        }
        return settings
    }

    private func captureSinglePhoto(
        includePortraitData: Bool,
        flashMode: PhotoFlashMode
    ) {
        photoOutput.capturePhoto(
            with: makePhotoSettings(
                includePortraitData: includePortraitData,
                flashMode: flashMode
            ),
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
                self.softwareZoomFactor = 1.0
                DispatchQueue.main.async {
                    self.photoLens = lens
                    self.zoomFactor = self.softwareZoomFactor
                }
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

    func setStyleAdjustment(tone: Double? = nil, color: Double? = nil, palette: Double? = nil) {
        var updated = styleAdjustment
        if let tone { updated.tone = min(max(tone, -100), 100) }
        if let color { updated.color = min(max(color, -100), 100) }
        if let palette { updated.palette = min(max(palette, 0), 100) }
        DispatchQueue.main.async { [weak self] in self?.styleAdjustment = updated }
    }

    func resetStyleAdjustment() {
        DispatchQueue.main.async { [weak self] in self?.styleAdjustment = .neutral }
    }

    func setPortraitAperture(_ aperture: CGFloat) {
        let clamped = min(max(aperture, 1.4), 16.0)
        DispatchQueue.main.async { [weak self] in self?.portraitAperture = clamped }
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
        configureDepthDelivery(for: mode)
        applyVideoOrientation()
        applyPhotoOutputMirroring()
        if !withinExistingSessionConfiguration {
            session.commitConfiguration()
        }
    }

    private func configureDepthDelivery(for mode: CaptureMode) {
        // Configure depth once for the session and keep it enabled while the
        // input changes between Photo and Portrait. Toggling delivery after a
        // running session has changed inputs can make AVCapturePhotoSettings
        // invalid and crash at capture time on physical devices.
        guard mode == .portrait else { return }
        if photoOutput.isDepthDataDeliverySupported {
            photoOutput.isDepthDataDeliveryEnabled = true
        }
        if photoOutput.isDepthDataDeliveryEnabled,
           photoOutput.isPortraitEffectsMatteDeliverySupported {
            photoOutput.isPortraitEffectsMatteDeliveryEnabled = true
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
           mode == .portrait,
           let trueDepth = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front) {
            return trueDepth
        }

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

    private func applyStyleAdjustment(_ adjustment: PhotoStyleAdjustment, to image: CGImage) -> CGImage {
        guard !adjustment.isNeutral else { return image }
        var output = CIImage(cgImage: image)

        if abs(adjustment.tone) > 0.5, let curve = CIFilter(name: "CIToneCurve") {
            let t = CGFloat(adjustment.tone / 100.0)
            curve.setValue(output, forKey: kCIInputImageKey)
            curve.setValue(CIVector(x: 0, y: max(0, 0 - t * 0.04)), forKey: "inputPoint0")
            curve.setValue(CIVector(x: 0.25, y: 0.25 + t * 0.05), forKey: "inputPoint1")
            curve.setValue(CIVector(x: 0.5, y: 0.5 + t * 0.08), forKey: "inputPoint2")
            curve.setValue(CIVector(x: 0.75, y: 0.75 + t * 0.05), forKey: "inputPoint3")
            curve.setValue(CIVector(x: 1, y: min(1, 1 + t * 0.04)), forKey: "inputPoint4")
            if let toneOutput = curve.outputImage { output = toneOutput }
        }

        if abs(adjustment.color) > 0.5 {
            let tempFilter = CIFilter(name: "CITemperatureAndTint")
            tempFilter?.setValue(output, forKey: kCIInputImageKey)
            let neutralTemp: CGFloat = 6500
            let shift = CGFloat(adjustment.color / 100.0) * 900
            tempFilter?.setValue(CIVector(x: neutralTemp - shift, y: 0), forKey: "inputNeutral")
            tempFilter?.setValue(CIVector(x: neutralTemp, y: 0), forKey: "inputTargetNeutral")
            if let tempOutput = tempFilter?.outputImage { output = tempOutput }
        }

        let paletteOffset = adjustment.palette - 50
        if abs(paletteOffset) > 0.5, let matrix = CIFilter(name: "CIColorMatrix") {
            let strength = CGFloat(paletteOffset / 50.0) * 0.05
            matrix.setValue(output, forKey: kCIInputImageKey)
            matrix.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
            matrix.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
            matrix.setValue(CIVector(x: 0, y: 0, z: 1, w: 0), forKey: "inputBVector")
            matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
            matrix.setValue(
                CIVector(x: strength * 0.6, y: strength * 0.25, z: -strength * 0.6, w: 0),
                forKey: "inputBiasVector"
            )
            if let matrixOutput = matrix.outputImage { output = matrixOutput }
        }

        guard let rendered = ciContext.createCGImage(output, from: output.extent) else { return image }
        return rendered
    }

    private func softwareZoomedFileData(
        for photo: AVCapturePhoto,
        factor: CGFloat,
        includePortraitData: Bool,
        aspectRatio: PhotoAspectRatio,
        aperture: CGFloat,
        styleAdjustment: PhotoStyleAdjustment
    ) -> Data? {
        guard factor > 1.01 || aspectRatio != .fourThree || includePortraitData || !styleAdjustment.isNeutral else {
            return photo.fileDataRepresentation()
        }
        guard let primaryImage = photo.cgImageRepresentation() else {
            return includePortraitData
                ? (portraitEnabledFileData(for: photo, aperture: aperture) ?? photo.fileDataRepresentation())
                : photo.fileDataRepresentation()
        }

        let sourceAspectRatio = CGFloat(primaryImage.width) / CGFloat(primaryImage.height)
        // The primary image is landscape before its EXIF orientation is applied.
        // Crop Portrait to the established 4:3 sensor frame and Photo to the
        // selected sensor ratio, so an upright 9:16 Photo remains upright once
        // Photos applies the capture orientation metadata.
        let targetAspectRatio = includePortraitData
            ? PhotoAspectRatio.fourThree.value
            : aspectRatio.value
        var cropWidth = 1.0
        var cropHeight = 1.0
        if sourceAspectRatio > targetAspectRatio {
            cropWidth = targetAspectRatio / sourceAspectRatio
        } else if sourceAspectRatio < targetAspectRatio {
            cropHeight = sourceAspectRatio / targetAspectRatio
        }

        let processedImage = includePortraitData
            ? (depthEffectImage(from: primaryImage, photo: photo, aperture: aperture) ?? primaryImage)
            : primaryImage

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

        guard let croppedImage = processedImage.cropping(to: cropRect) else {
            return includePortraitData
                ? (portraitEnabledFileData(for: photo, aperture: aperture) ?? photo.fileDataRepresentation())
                : photo.fileDataRepresentation()
        }
        let styledImage = applyStyleAdjustment(styleAdjustment, to: croppedImage)

        var depthAuxiliaryInfo: (CFString, CFDictionary)?
        if includePortraitData, let depth = photo.depthData {
            var depthType: NSString?
            if let originalInfo = depth.dictionaryRepresentation(forAuxiliaryDataType: &depthType),
               let depthType {
                depthAuxiliaryInfo = croppedAuxiliaryInfo(
                    from: originalInfo,
                    auxiliaryType: depthType,
                    map: depth.depthDataMap,
                    normalizedRect: normalizedCrop
                )
            }
        }

        var matteAuxiliaryInfo: (CFString, CFDictionary)?
        if includePortraitData, let matte = photo.portraitEffectsMatte {
            var matteType: NSString?
            if let originalInfo = matte.dictionaryRepresentation(forAuxiliaryDataType: &matteType),
               let matteType {
                matteAuxiliaryInfo = croppedAuxiliaryInfo(
                    from: originalInfo,
                    auxiliaryType: matteType,
                    map: matte.mattingImage,
                    normalizedRect: normalizedCrop
                )
            }
        }

        let croppedMetadata = croppedMetadata(
            from: photo.metadata,
            width: styledImage.width,
            height: styledImage.height
        )
        let outputMetadata = includePortraitData
            ? portraitEnabledMetadata(from: croppedMetadata)
            : croppedMetadata

        guard let croppedData = packageImage(
            styledImage,
            metadata: outputMetadata,
            depthAuxiliaryInfo: depthAuxiliaryInfo,
            matteAuxiliaryInfo: matteAuxiliaryInfo
        ) else {
            // Never discard a genuine Portrait capture merely because a
            // derivative software crop could not be packaged on this OS.
            return includePortraitData
                ? (portraitEnabledFileData(for: photo, aperture: aperture) ?? photo.fileDataRepresentation())
                : photo.fileDataRepresentation()
        }
        return croppedData
    }

    private func croppedPortraitFileData(for photo: AVCapturePhoto, factor: CGFloat, aperture: CGFloat, styleAdjustment: PhotoStyleAdjustment) -> Data? {
        guard factor > 1.01 || !styleAdjustment.isNeutral || aperture < 15.95 else {
            return photo.fileDataRepresentation()
        }

        guard let primaryImage = photo.cgImageRepresentation() else {
            return photo.fileDataRepresentation()
        }

        let blurredImage = depthEffectImage(from: primaryImage, photo: photo, aperture: aperture) ?? primaryImage

        let sourceAspectRatio = CGFloat(primaryImage.width) / CGFloat(primaryImage.height)
        let targetAspectRatio = PhotoAspectRatio.fourThree.value
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
        let normalizedCrop = CGRect(
            x: (1.0 - cropWidth) / 2.0,
            y: (1.0 - cropHeight) / 2.0,
            width: cropWidth,
            height: cropHeight
        )
        let cropRect = CGRect(
            x: CGFloat(primaryImage.width) * normalizedCrop.minX,
            y: CGFloat(primaryImage.height) * normalizedCrop.minY,
            width: CGFloat(primaryImage.width) * normalizedCrop.width,
            height: CGFloat(primaryImage.height) * normalizedCrop.height
        ).integral

        guard let croppedImage = blurredImage.cropping(to: cropRect) else {
            return photo.fileDataRepresentation()
        }
        let styledPortraitImage = applyStyleAdjustment(styleAdjustment, to: croppedImage)

        var depthAuxiliaryInfo: (CFString, CFDictionary)?
        if let depth = photo.depthData {
            var depthType: NSString?
            if let originalInfo = depth.dictionaryRepresentation(forAuxiliaryDataType: &depthType),
               let depthType {
                depthAuxiliaryInfo = croppedAuxiliaryInfo(
                    from: originalInfo,
                    auxiliaryType: depthType,
                    map: depth.depthDataMap,
                    normalizedRect: normalizedCrop
                )
            }
        }

        var matteAuxiliaryInfo: (CFString, CFDictionary)?
        if let matte = photo.portraitEffectsMatte {
            var matteType: NSString?
            if let originalInfo = matte.dictionaryRepresentation(forAuxiliaryDataType: &matteType),
               let matteType {
                matteAuxiliaryInfo = croppedAuxiliaryInfo(
                    from: originalInfo,
                    auxiliaryType: matteType,
                    map: matte.mattingImage,
                    normalizedRect: normalizedCrop
                )
            }
        }

        let outputMetadata = portraitEnabledMetadata(
            from: croppedMetadata(from: photo.metadata, width: styledPortraitImage.width, height: styledPortraitImage.height)
        )

        guard let croppedData = packageImage(
            styledPortraitImage,
            metadata: outputMetadata,
            depthAuxiliaryInfo: depthAuxiliaryInfo,
            matteAuxiliaryInfo: matteAuxiliaryInfo
        ) else {
            // Never lose a genuine Portrait capture over a packaging
            // failure — fall back to the native, uncropped file.
            return photo.fileDataRepresentation()
        }
        return croppedData
    }

    private func depthEffectImage(from image: CGImage, photo: AVCapturePhoto, aperture: CGFloat) -> CGImage? {
        guard aperture < 15.95, let depth = photo.depthData else { return nil }
        guard let filter = CIFilter(name: "CIDepthOfField") else { return nil }
        let inputImage = CIImage(cgImage: image)
        let disparityImage = CIImage(cvPixelBuffer: depth.depthDataMap)
        let normalizedStrength = max(0, min(1, (16.0 - aperture) / 14.6))
        filter.setValue(inputImage, forKey: kCIInputImageKey)
        filter.setValue(disparityImage, forKey: "inputDisparityImage")
        filter.setValue(CIVector(x: inputImage.extent.midX, y: inputImage.extent.midY), forKey: "inputPoint0")
        filter.setValue(NSNumber(value: Float(normalizedStrength * 18.0)), forKey: "inputRadius")
        guard let output = filter.outputImage else { return nil }
        return ciContext.createCGImage(output, from: inputImage.extent)
    }

    private func portraitEnabledFileData(for photo: AVCapturePhoto, aperture: CGFloat) -> Data? {
        guard let image = photo.cgImageRepresentation() else { return nil }
        let outputImage = depthEffectImage(from: image, photo: photo, aperture: aperture) ?? image
        let originalMetadata = photo.metadata
        let originalMakerApple = originalMetadata[kCGImagePropertyMakerAppleDictionary as String] as? [String: Any]
        if originalMakerApple?["25"] != nil, aperture >= 15.95 {
            return photo.fileDataRepresentation()
        }
        let metadata = portraitEnabledMetadata(from: originalMetadata)

        var depthAuxiliaryInfo: (CFString, CFDictionary)?
        if let depth = photo.depthData {
            var depthType: NSString?
            if let originalInfo = depth.dictionaryRepresentation(forAuxiliaryDataType: &depthType),
               let depthType {
                depthAuxiliaryInfo = auxiliaryInfo(
                    from: originalInfo,
                    auxiliaryType: depthType,
                    map: depth.depthDataMap
                )
            }
        }

        var matteAuxiliaryInfo: (CFString, CFDictionary)?
        if let matte = photo.portraitEffectsMatte {
            var matteType: NSString?
            if let originalInfo = matte.dictionaryRepresentation(forAuxiliaryDataType: &matteType),
               let matteType {
                matteAuxiliaryInfo = auxiliaryInfo(
                    from: originalInfo,
                    auxiliaryType: matteType,
                    map: matte.mattingImage
                )
            }
        }

        guard depthAuxiliaryInfo != nil || matteAuxiliaryInfo != nil else { return nil }
        return packageImage(
            outputImage,
            metadata: metadata,
            depthAuxiliaryInfo: depthAuxiliaryInfo,
            matteAuxiliaryInfo: matteAuxiliaryInfo
        )
    }

    private func auxiliaryInfo(
        from originalInfo: [AnyHashable: Any],
        auxiliaryType: NSString,
        map: CVPixelBuffer
    ) -> (CFString, CFDictionary)? {
        guard let mapData = pixelBufferData(map) else { return nil }
        let result = NSMutableDictionary(dictionary: originalInfo)
        result.setObject(mapData as NSData, forKey: kCGImageAuxiliaryDataInfoData as NSString)
        return (auxiliaryType as CFString, result as CFDictionary)
    }

    private func portraitEnabledMetadata(from original: [String: Any]) -> [String: Any] {
        var result = original
        var makerApple = (original[kCGImagePropertyMakerAppleDictionary as String] as? [String: Any]) ?? [:]
        // Apple’s native Portrait captures carry a nonzero SceneFlags value.
        // Preserve an existing value; otherwise use the conservative Portrait marker.
        if makerApple["25"] == nil {
            makerApple["25"] = 1
        }
        result[kCGImagePropertyMakerAppleDictionary as String] = makerApple
        return result
    }

    private func croppedAuxiliaryInfo(
        from originalInfo: [AnyHashable: Any],
        auxiliaryType: NSString,
        map source: CVPixelBuffer,
        normalizedRect: CGRect
    ) -> (CFString, CFDictionary)? {
        guard let croppedMap = cropPixelBuffer(source, normalizedRect: normalizedRect),
              let mapData = pixelBufferData(croppedMap) else { return nil }

        let result = NSMutableDictionary(dictionary: originalInfo)
        result.setObject(mapData as NSData, forKey: kCGImageAuxiliaryDataInfoData as NSString)

        if let originalDescription = originalInfo[kCGImageAuxiliaryDataInfoDataDescription] as? [AnyHashable: Any] {
            let description = NSMutableDictionary(dictionary: originalDescription)
            description.setObject(CVPixelBufferGetWidth(croppedMap), forKey: kCGImagePropertyWidth as NSString)
            description.setObject(CVPixelBufferGetHeight(croppedMap), forKey: kCGImagePropertyHeight as NSString)
            description.setObject(CVPixelBufferGetBytesPerRow(croppedMap), forKey: kCGImagePropertyBytesPerRow as NSString)
            description.setObject(CVPixelBufferGetPixelFormatType(croppedMap), forKey: kCGImagePropertyPixelFormat as NSString)
            result.setObject(description, forKey: kCGImageAuxiliaryDataInfoDataDescription as NSString)
        }

        return (auxiliaryType as CFString, result as CFDictionary)
    }

    private func pixelBufferData(_ pixelBuffer: CVPixelBuffer) -> Data? {
        guard CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let byteCount = CVPixelBufferGetBytesPerRow(pixelBuffer) * CVPixelBufferGetHeight(pixelBuffer)
        return Data(bytes: baseAddress, count: byteCount)
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
        let bytesPerPixel: Int
        switch pixelFormat {
        case kCVPixelFormatType_DepthFloat16,
             kCVPixelFormatType_DisparityFloat16,
             kCVPixelFormatType_OneComponent16Half:
            bytesPerPixel = 2
        case kCVPixelFormatType_DepthFloat32,
             kCVPixelFormatType_DisparityFloat32,
             kCVPixelFormatType_OneComponent32Float:
            bytesPerPixel = 4
        case kCVPixelFormatType_OneComponent8:
            bytesPerPixel = 1
        default:
            return nil
        }

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

        guard CVPixelBufferLockBaseAddress(source, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(source, .readOnly) }
        guard CVPixelBufferLockBaseAddress(destination, []) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(destination, []) }

        let sourceBytesPerRow = CVPixelBufferGetBytesPerRow(source)
        let destinationBytesPerRow = CVPixelBufferGetBytesPerRow(destination)
        let copyBytesPerRow = Int(cropRect.width) * bytesPerPixel
        let sourceBaseAddress = CVPixelBufferGetBaseAddress(source)
        let destinationBaseAddress = CVPixelBufferGetBaseAddress(destination)
        guard let sourceBaseAddress, let destinationBaseAddress,
              copyBytesPerRow <= sourceBytesPerRow,
              copyBytesPerRow <= destinationBytesPerRow else { return nil }

        let sourceStartX = Int(cropRect.minX) * bytesPerPixel
        let sourceStartY = Int(cropRect.minY)
        for row in 0..<Int(cropRect.height) {
            let sourceRow = sourceBaseAddress
                .advanced(by: (sourceStartY + row) * sourceBytesPerRow + sourceStartX)
            let destinationRow = destinationBaseAddress
                .advanced(by: row * destinationBytesPerRow)
            destinationRow.copyMemory(from: sourceRow, byteCount: copyBytesPerRow)
        }
        return destination
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
        metadata: [String: Any],
        depthAuxiliaryInfo: (CFString, CFDictionary)?,
        matteAuxiliaryInfo: (CFString, CFDictionary)?
    ) -> Data? {
        let data = NSMutableData()
        let imageType: CFString = UTType.heic.identifier as CFString
        guard let destination = CGImageDestinationCreateWithData(data, imageType, 1, nil) else {
            return nil
        }

        CGImageDestinationAddImage(destination, image, metadata as CFDictionary)

        if let depthAuxiliaryInfo {
            CGImageDestinationAddAuxiliaryDataInfo(
                destination,
                depthAuxiliaryInfo.0,
                depthAuxiliaryInfo.1
            )
        }

        if let matteAuxiliaryInfo {
            CGImageDestinationAddAuxiliaryDataInfo(
                destination,
                matteAuxiliaryInfo.0,
                matteAuxiliaryInfo.1
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
        let includePortraitData = activeCaptureMode == .portrait

        if includePortraitData {
            // Crop to the selected zoom factor while preserving embedded
            // depth/matte data for Photos. At 1x this returns the native
            // AVFoundation representation unchanged (no crop needed).
            guard let data = croppedPortraitFileData(for: photo, factor: zoom, aperture: activeCaptureAperture, styleAdjustment: activeCaptureStyle) else {
                finishCapture(with: "Could not create the Portrait photo file")
                return
            }
            saveToPhotos(data: data)
            return
        }

        guard let data = softwareZoomedFileData(
            for: photo,
            factor: zoom,
            includePortraitData: false,
            aspectRatio: activeCaptureAspectRatio,
            aperture: activeCaptureAperture,
            styleAdjustment: activeCaptureStyle
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
