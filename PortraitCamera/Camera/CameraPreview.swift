import AVFoundation
import SwiftUI
import UIKit

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let zoomFactor: CGFloat
    let deviceZoomFactor: CGFloat
    let videoOrientation: AVCaptureVideoOrientation
    let isMirrored: Bool
    let onTap: (CGPoint, CGPoint) -> Void
    var onViewReady: ((PreviewView) -> Void)? = nil

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.apply(
            session: session,
            onTap: onTap,
            orientation: videoOrientation,
            isMirrored: isMirrored,
            digitalZoom: max(1.0, zoomFactor / max(deviceZoomFactor, 1.0))
        )
        onViewReady?(view)
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        // Keep the live layer stable. Reassigning the session and transform on
        // every SwiftUI state update can interrupt preview rendering while a
        // menu, mode, or aspect-ratio control is being used.
        view.apply(
            session: session,
            onTap: onTap,
            orientation: videoOrientation,
            isMirrored: isMirrored,
            digitalZoom: max(1.0, zoomFactor / max(deviceZoomFactor, 1.0))
        )
    }
}

final class PreviewView: UIView {
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private var lastDigitalZoom: CGFloat = 1.0
    private var lastOrientation: AVCaptureVideoOrientation?
    private var lastMirroring: Bool?

    var onTap: ((CGPoint, CGPoint) -> Void)?

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        previewLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    private func configureView() {
        backgroundColor = .black
        clipsToBounds = true
        previewLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(previewLayer)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)
    }

    func apply(
        session: AVCaptureSession,
        onTap: @escaping (CGPoint, CGPoint) -> Void,
        orientation: AVCaptureVideoOrientation,
        isMirrored: Bool,
        digitalZoom: CGFloat
    ) {
        if previewLayer.session !== session {
            previewLayer.session = session
        }
        self.onTap = onTap
        setVideoOrientation(orientation)
        setVideoMirroring(isMirrored)
        setDigitalZoom(digitalZoom)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.bounds = bounds
        previewLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }

    func setVideoOrientation(_ orientation: AVCaptureVideoOrientation) {
        guard lastOrientation != orientation,
              let connection = previewLayer.connection,
              connection.isVideoOrientationSupported else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        connection.videoOrientation = orientation
        CATransaction.commit()
        lastOrientation = orientation
    }

    func setVideoMirroring(_ isMirrored: Bool) {
        guard lastMirroring != isMirrored,
              let connection = previewLayer.connection,
              connection.isVideoMirroringSupported else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = isMirrored
        CATransaction.commit()
        lastMirroring = isMirrored
    }

    func setDigitalZoom(_ factor: CGFloat) {
        let clamped = min(max(factor, 1.0), 5.0)
        guard abs(lastDigitalZoom - clamped) > 0.001 else { return }
        lastDigitalZoom = clamped
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.setAffineTransform(CGAffineTransform(scaleX: clamped, y: clamped))
        previewLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let viewPoint = gesture.location(in: self)
        let layerPoint = previewLayer.convert(viewPoint, from: layer)
        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: layerPoint)
        onTap?(viewPoint, devicePoint)
    }

    func snapshotImage() -> UIImage? {
        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        return renderer.image { context in
            layer.render(in: context.cgContext)
        }
    }
}
