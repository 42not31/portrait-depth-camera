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
    private var focusStackStage: FocusStackStage = .idle
    private var focusStackSubjectPhoto: AVCapturePhoto?
    private var focusStackBackgroundPhoto: AVCapturePhoto?
    private var focusStackOriginalLensPosition: Float?

    private enum FocusStackStage {
        case idle
        case capturingSubject
        case capturingBackground
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
            self.focusStackStage = .idle
            self.focusStackSubjectPhoto = nil
            self.focusStackBackgroundPhoto = nil
            self.focusStackOriginalLensPosition = nil
            DispatchQueue.main.async { self.isCapturing = true }

            if self.activeCaptureZoomFactor > 1.01 && self.canUseFocusStack {
                self.beginFocusStackCapture()
            } else {
                self.captureSinglePhoto(includePortraitData: true)
            }
        }
    }

    private var canUseFocusStack: Bool {
        guard activeCaptureZoomFactor > 1.01,
              let device = videoInput?.device,
              device.isFocusModeSupported(.locked),
              device.isLockingFocusWithCustomLensPositionSupported else {
            return false
        }
        return photoOutput.isDepthDataDeliverySupported
            && photoOutput.isDepthDataDeliveryEnabled
            && photoOutput.isPortraitEffectsMatteDeliverySupported
            && photoOutput.isPortraitEffectsMatteDeliveryEnabled
    }

    private func makePhotoSettings(includePortraitData: Bool) -> AVCapturePhotoSettings {
        let settings = AVCapturePhotoSettings()
        if photoOutput.maxPhotoQualityPrioritization == .quality {
            settings.photoQualityPrioritization = .quality
        }
        if photoOutput.supportedFlashModes.contains(.off) {
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

    private func captureSinglePhoto(includePortraitData: Bool) {
        photoOutput.capturePhoto(
            with: makePhotoSettings(includePortraitData: includePortraitData),
            delegate: self
        )
    }

    private func beginFocusStackCapture() {
        guard let device = videoInput?.device else {
            captureSinglePhoto(includePortraitData: true)
            return
        }

        focusStackStage = .capturingSubject
        focusStackOriginalLensPosition = device.lensPosition
        captureSinglePhoto(includePortraitData: true)
    }

    private func beginBackgroundFocusCapture() {
        guard let device = videoInput?.device,
              device.isLockingFocusWithCustomLensPositionSupported else {
            finishFocusStackUsingSubjectOnly()
            return
        }

        focusStackStage = .capturingBackground
        device.setFocusModeLocked(lensPosition: 1.0) { [weak self] _ in
            self?.sessionQueue.asyncAfter(deadline: .now() + 0.10) { [weak self] in
                guard let self else { return }
                self.captureSinglePhoto(includePortraitData: false)
            }
        }
    }

    private func finishFocusStackUsingSubjectOnly() {
        guard let subjectPhoto = focusStackSubjectPhoto else {
            finishCapture(with: "Could not create the photo file")
            return
        }
        let zoom = activeCaptureZoomFactor
        let data = softwareZoomedFileData(for: subjectPhoto, factor: zoom)
        restoreFocusAfterStack()
        clearFocusStackState()
        guard let data else {
            finishCapture(with: "Could not create the photo file")
            return
        }
        saveToPhotos(data: data, zoomFactor: zoom)
    }

    private func finishFocusStackCapture() {
        guard let subjectPhoto = focusStackSubjectPhoto,
              let backgroundPhoto = focusStackBackgroundPhoto else {
            finishFocusStackUsingSubjectOnly()
            return
        }

        let zoom = activeCaptureZoomFactor
        let stackedImage = makeFocusStackImage(
            subjectPhoto: subjectPhoto,
            backgroundPhoto: backgroundPhoto
        )
        let data = softwareZoomedFileData(
            for: subjectPhoto,
            factor: zoom,
            replacementImage: stackedImage
        )
        restoreFocusAfterStack()
        clearFocusStackState()
        guard let data else {
            finishCapture(with: "Could not create the photo file")
            return
        }
        saveToPhotos(data: data, zoomFactor: zoom)
    }

    private func restoreFocusAfterStack() {
        guard let device = videoInput?.device else { return }
        let originalLensPosition = focusStackOriginalLensPosition

        if let originalLensPosition,
           device.isLockingFocusWithCustomLensPositionSupported {
            device.setFocusModeLocked(lensPosition: originalLensPosition) { [weak self] _ in
                self?.sessionQueue.async {
                    self?.restoreContinuousFocusIfSupported(on: device)
                }
            }
        } else {
            restoreContinuousFocusIfSupported(on: device)
        }
    }

    private func restoreContinuousFocusIfSupported(on device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            device.unlockForConfiguration()
        } catch {
            // Focus restoration is best effort; the next tap-to-focus can still
            // reconfigure the device through the existing focus path.
        }
    }

    private func clearFocusStackState() {
        focusStackStage = .idle
        focusStackSubjectPhoto = nil
        focusStackBackgroundPhoto = nil
        focusStackOriginalLensPosition = nil
    }

    private func makeFocusStackImage(
        subjectPhoto: AVCapturePhoto,
        backgroundPhoto: AVCapturePhoto
    ) -> CGImage? {
        guard let subjectImage = subjectPhoto.cgImageRepresentation(),
              let backgroundImage = backgroundPhoto.cgImageRepresentation(),
              let matte = subjectPhoto.portraitEffectsMatte else {
            return nil
        }

        let foreground = CIImage(cgImage: subjectImage)
        let background = CIImage(cgImage: backgroundImage)
        let matteImage = CIImage(cvPixelBuffer: matte.mattingImage)
        guard foreground.extent.width > 0,
              foreground.extent.height > 0,
              matteImage.extent.width > 0,
              matteImage.extent.height > 0 else { return nil }

        let scaleX = foreground.extent.width / matteImage.extent.width
        let scaleY = foreground.extent.height / matteImage.extent.height
        let scaledMatte = matteImage
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .cropped(to: foreground.extent)

        guard let filter = CIFilter(name: "CIBlendWithMask") else { return nil }
        filter.setValue(foreground, forKey: kCIInputImageKey)
        filter.setValue(background, forKey: kCIInputBackgroundImageKey)
        filter.setValue(scaledMatte, forKey: kCIInputMaskImageKey)
        guard let result = filter.outputImage else { return nil }
        return ciContext.createCGImage(result, from: foreground.extent)
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
                self.photoOutput.maxPhotoQualityPrioritization = .quality

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

    private func softwareZoomedFileData(
        for photo: AVCapturePhoto,
        factor: CGFloat,
        replacementImage: CGImage? = nil
    ) -> Data? {
        guard factor > 1.01 else { return photo.fileDataRepresentation() }
        guard let primaryImage = replacementImage ?? photo.cgImageRepresentation() else {
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

        guard let croppedData = packageImage(
            croppedImage,
            metadata: croppedMetadata(from: photo.metadata, width: croppedImage.width, height: croppedImage.height),
            depthAuxiliaryInfo: depthAuxiliaryInfo,
            matteAuxiliaryInfo: matteAuxiliaryInfo
        ) else {
            // Never discard a genuine Portrait capture merely because a
            // derivative software crop could not be packaged on this OS.
            return photo.fileDataRepresentation()
        }
        return croppedData
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
            if focusStackStage == .capturingBackground {
                finishFocusStackUsingSubjectOnly()
            } else {
                clearFocusStackState()
                finishCapture(with: error.localizedDescription)
            }
            return
        }

        switch focusStackStage {
        case .capturingSubject:
            guard photo.portraitEffectsMatte != nil else {
                finishFocusStackUsingSubjectOnly()
                return
            }
            focusStackSubjectPhoto = photo
            beginBackgroundFocusCapture()

        case .capturingBackground:
            focusStackBackgroundPhoto = photo
            finishFocusStackCapture()

        case .idle:
            let zoom = activeCaptureZoomFactor
            guard let data = softwareZoomedFileData(for: photo, factor: zoom) else {
                finishCapture(with: "Could not create the photo file")
                return
            }
            saveToPhotos(data: data, zoomFactor: zoom)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if let error, focusStackStage == .idle {
            finishCapture(with: error.localizedDescription)
        }
    }
}

enum CameraError: Error {
    case unavailable
}
