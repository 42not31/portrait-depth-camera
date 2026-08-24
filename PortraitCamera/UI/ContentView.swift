import AVFoundation
import SwiftUI

struct ContentView: View {
    @ObservedObject var camera: CameraModel
    @State private var focusPoint: CGPoint?
    @State private var focusAnimationID = UUID()

    private let zoomPresets: [CGFloat] = [1.0, 2.0]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    header
                    preview(in: proxy.size)
                    controls
                }

                if camera.permissionDenied {
                    permissionCard
                }

                if let message = camera.statusMessage {
                    VStack {
                        Spacer()
                        Text(message)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.bottom, 28)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    .allowsHitTesting(false)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                            if camera.statusMessage == message {
                                withAnimation { camera.statusMessage = nil }
                            }
                        }
                    }
                }
            }
        }
        .task {
            camera.start()
        }
        .onDisappear {
            camera.stop()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("PORTRAIT")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .tracking(2.2)
                    .foregroundStyle(.white)
                HStack(spacing: 6) {
                    Circle()
                        .fill(camera.depthCaptureAvailable ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(camera.depthCaptureAvailable ? "DEPTH READY" : "STANDARD DEPTH")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(.white.opacity(0.64))
                }
            }

            Spacer()

            Image(systemName: camera.portraitMatteAvailable ? "person.crop.square" : "camera.metering.center.weighted")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .padding(12)
                .background(.white.opacity(0.1), in: Circle())
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 16)
    }

    private func preview(in size: CGSize) -> some View {
        CameraPreview(
            session: camera.session,
            zoomFactor: camera.zoomFactor,
            deviceZoomFactor: camera.deviceZoomFactor,
            onTap: { point, previewSize in
                camera.focus(at: point, in: previewSize)
                focusPoint = point
                focusAnimationID = UUID()
            }
        )
        .overlay {
            if let focusPoint {
                FocusReticle()
                    .id(focusAnimationID)
                    .position(focusPoint)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
    }

    private var controls: some View {
        VStack(spacing: 22) {
            HStack(spacing: 10) {
                ForEach(zoomPresets, id: \.self) { preset in
                    Button {
                        camera.setZoomFactor(preset)
                    } label: {
                        Text(preset == 1.0 ? "1×" : "2×")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(abs(camera.zoomFactor - preset) < 0.08 ? .black : .white.opacity(0.82))
                            .frame(width: 52, height: 36)
                            .background(
                                abs(camera.zoomFactor - preset) < 0.08 ? Color.white : Color.white.opacity(0.1),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                camera.capturePhoto()
            } label: {
                ZStack {
                    Circle()
                        .stroke(.white, lineWidth: 4)
                        .frame(width: 76, height: 76)
                    Circle()
                        .fill(camera.isCapturing ? .white.opacity(0.45) : .white)
                        .frame(width: 62, height: 62)
                }
            }
            .buttonStyle(.plain)
            .disabled(camera.isCapturing || !camera.isConfigured || !camera.isRunning)
            .scaleEffect(camera.isCapturing ? 0.94 : 1.0)
            .animation(.easeOut(duration: 0.16), value: camera.isCapturing)
        }
        .padding(.top, 16)
        .padding(.bottom, 22)
    }

    private var permissionCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.fill")
                .font(.system(size: 28))
                .foregroundStyle(.white)
            Text("Camera access is required")
                .font(.system(size: 19, weight: .bold, design: .rounded))
            Text("Enable camera access in Settings to capture Portrait photos.")
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .padding(28)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(28)
    }
}

private struct FocusReticle: View {
    @State private var visible = false

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(Color.yellow, lineWidth: 1.5)
            .frame(width: 64, height: 64)
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeOut(duration: 0.14)) { visible = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    withAnimation(.easeIn(duration: 0.2)) { visible = false }
                }
            }
    }
}
