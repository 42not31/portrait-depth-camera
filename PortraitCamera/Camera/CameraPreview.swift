import AVFoundation
import SwiftUI
import UIKit

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let zoomFactor: CGFloat
    let deviceZoomFactor: CGFloat
    let onTap: (CGPoint, CGSize) -> Void

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        view.onTap = onTap
        view.setDigitalZoom(max(1.0, zoomFactor / max(deviceZoomFactor, 1.0)))
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        view.videoPreviewLayer.session = session
        view.onTap = onTap
        view.setDigitalZoom(max(1.0, zoomFactor / max(deviceZoomFactor, 1.0)))
    }
}

final class PreviewView: UIView, UIGestureRecognizerDelegate {
    var onTap: ((CGPoint, CGSize) -> Void)?

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.delegate = self
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        videoPreviewLayer.frame = bounds
    }

    func setDigitalZoom(_ factor: CGFloat) {
        let clamped = min(max(factor, 1.0), 2.0)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoPreviewLayer.setAffineTransform(CGAffineTransform(scaleX: clamped, y: clamped))
        CATransaction.commit()
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        onTap?(point, bounds.size)
    }
}
