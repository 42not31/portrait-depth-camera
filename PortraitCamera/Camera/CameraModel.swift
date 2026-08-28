// ... existing code ...
    @Published private(set) var isConfigured = false
    @Published private(set) var isRunning = false
    @Published private(set) var isCapturing = false
    @Published private(set) var zoomFactor: CGFloat = 1.0 {
        didSet { applyTelephotoStability(zoom: zoomFactor) }
    }
    @Published private(set) var deviceZoomFactor: CGFloat = 1.0
    @Published private(set) var captureMode: CaptureMode = .portrait
// ... existing code ...
    @Published var statusMessage: String?

    private let sessionQueue = DispatchQueue(label: "com.privateportrait.camera.session")
    private let photoOutput = AVCapturePhotoOutput()
    let videoDataOutput = AVCaptureVideoDataOutput()
    private let ciContext = CIContext()
    private var videoInput: AVCaptureDeviceInput?
// ... existing code ...
    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.session.isRunning else { return }
            self.session.stopRunning()
            DispatchQueue.main.async { self.isRunning = false }
        }
    }

    private func applyTelephotoStability(zoom: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self = self, let videoInput = self.videoInput else { return }
            
            let device = videoInput.device
            do {
                try device.lockForConfiguration()
                // Enable smooth auto-focus when zoomed in to mimic a heavy telephoto lens
                if device.isSmoothAutoFocusSupported {
                    device.isSmoothAutoFocusEnabled = zoom >= 2.0
                }
                device.unlockForConfiguration()
            } catch {
                print("Could not lock device for stability: \(error)")
            }
            
            // Apply Cinematic Stabilization to the background video stream
            if let connection = self.videoDataOutput.connection(with: .video) {
                if connection.isVideoStabilizationSupported {
                    // Use cinematicExtended for aggressive stabilization at high zooms
                    connection.preferredVideoStabilizationMode = zoom >= 2.0 ? .cinematicExtended : .auto
                }
            }
        }
    }

    func capturePhoto() {
        guard isConfigured, isRunning, !isCapturing else { return }
// ... existing code ...
            do {
                // Use the dual-wide rear camera for the best native Portrait framing.
                let camera = try self.makeCamera(for: .portrait)
                let input = try AVCaptureDeviceInput(device: camera)
                guard self.session.canAddInput(input) else { throw CameraError.unavailable }
                self.session.addInput(input)
                self.videoInput = input

                guard self.session.canAddOutput(self.photoOutput) else { throw CameraError.unavailable }
                self.session.addOutput(self.photoOutput)
                
                // Add streaming outputs for stabilization monitoring
                if self.session.canAddOutput(self.videoDataOutput) {
                    self.session.addOutput(self.videoDataOutput)
                }

                self.applyVideoOrientation()
                self.applyPhotoOutputMirroring()
// ... existing code ...
