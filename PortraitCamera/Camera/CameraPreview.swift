import AVFoundation
import SwiftUI
import UIKit

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let zoomFactor: CGFloat
    let deviceZoomFactor: CGFloat
    let videoOrientation: AVCaptureVideoOrientation
    let onTap: (CGPoint, CGPoint) -> Void

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.onTap = onTap
        view.setVideoOrientation(videoOrientation)
        view.setDigitalZoom(max(1.0, zoomFactor / max(deviceZoomFactor, 1.0)))
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        view.videoPreviewLayer.session = session
        view.onTap = onTap
        view.setVideoOrientation(videoOrientation)
        view.setDigitalZoom(max(1.0, zoomFactor / max(deviceZoomFactor, 1.0)))
    }
}

final class PreviewView: UIView {
    private let previewLayer = AVCaptureVideoPreviewLayer()
    var onTap: ((CGPoint, CGPoint) -> Void)?

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        previewLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        clipsToBounds = true
        previewLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(previewLayer)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        previewLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(previewLayer)
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
        guard let connection = previewLayer.connection,
              connection.isVideoOrientationSupported else { return }
        connection.videoOrientation = orientation
    }

    func setDigitalZoom(_ factor: CGFloat) {
        let clamped = min(max(factor, 1.0), 5.0)
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
}