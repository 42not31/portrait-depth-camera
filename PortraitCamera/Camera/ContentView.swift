import AVFoundation
import SwiftUI
import UIKit

struct ContentView: View {
    @ObservedObject var camera: CameraModel
    @ObservedObject var settings: CamProSettings
    @State private var focusPoint: CGPoint?
    @State private var focusAnimationID = UUID()
    @State private var showSettings = false

    private var zoomPresets: [CGFloat] {
        camera.captureMode == .photo ? [1.0, 2.0, 3.0, 4.0, 5.0] : [1.0, 2.0]
    }

    private var previewAspectRatio: CGFloat {
        camera.captureMode == .photo ? 1.0 / camera.photoAspectRatio.value : 3.0 / 4.0
    }

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
        .sheet(isPresented: $showSettings) {
            SettingsView(camera: camera, settings: settings)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("CAMPRO")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .tracking(2.2)
                    .foregroundStyle(.white)
            }

            Spacer()

            Button {
                showSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(12)
                    .background(CamProTheme.accentMuted, in: Circle())
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel("Settings")
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
            // The interface and preview stay portrait-locked. The camera model
            // still applies the physical device orientation to the saved output.
            videoOrientation: .portrait,
            onTap: { viewPoint, devicePoint in
                camera.focus(at: devicePoint)
                focusPoint = viewPoint
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
        .aspectRatio(previewAspectRatio, contentMode: .fit)
    }

    private var controls: some View {
        VStack(spacing: 22) {
            Picker("Capture mode", selection: Binding(
                get: { camera.captureMode },
                set: { camera.setCaptureMode($0) }
            )) {
                ForEach(CaptureMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .tint(CamProTheme.accent)
            .padding(.horizontal, 34)
            .accessibilityLabel("Capture mode")

            if camera.captureMode == .photo {
                photoControls
            }

            HStack(spacing: 10) {
                ForEach(zoomPresets, id: \.self) { preset in
                    Button {
                        camera.setZoomFactor(preset)
                    } label: {
                        Text("\(preset, specifier: "%.0f")×")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(abs(camera.zoomFactor - preset) < 0.08 ? .white : .white.opacity(0.82))
                            .frame(minWidth: 46, minHeight: 36)
                            .background(
                                abs(camera.zoomFactor - preset) < 0.08 ? CamProTheme.accent : Color.white.opacity(0.1),
                                in: Capsule()
                            )
                            .animation(.easeOut(duration: 0.18), value: camera.zoomFactor)
                    }
                    .buttonStyle(ScaleButtonStyle(scale: 0.9))
                }
            }

            HStack {
                Button {
                    camera.openLatestPhotoInPhotos()
                } label: {
                    Group {
                        if let image = camera.latestPhotoImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: "photo")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(.white.opacity(0.34))
                        }
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(.white.opacity(0.18), lineWidth: 1)
                    }
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(camera.latestPhotoImage == nil)
                .accessibilityLabel(camera.latestPhotoImage == nil ? "No photo captured yet" : "Open latest photo in Photos")

                Spacer()

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
                .accessibilityLabel("Shutter")

                Spacer()
                Color.clear.frame(width: 56, height: 56)
            }
            .padding(.horizontal, 28)
        }
        .padding(.top, 16)
        .padding(.bottom, 22)
    }

    private var photoControls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(PhotoLens.allCases) { lens in
                    Button {
                        camera.setPhotoLens(lens)
                    } label: {
                        Text(lens.title)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(camera.photoLens == lens ? .white : .white.opacity(0.78))
                            .frame(minWidth: 48, minHeight: 34)
                            .background(
                                camera.photoLens == lens ? CamProTheme.accent : Color.white.opacity(0.1),
                                in: Capsule()
                            )
                            .animation(.easeOut(duration: 0.18), value: camera.photoLens)
                    }
                    .buttonStyle(ScaleButtonStyle(scale: 0.9))
                    .accessibilityLabel("Photo lens \(lens.title)")
                    .accessibilityAddTraits(camera.photoLens == lens ? .isSelected : [])
                }

                Spacer(minLength: 8)

                Menu {
                    ForEach(PhotoFlashMode.allCases) { mode in
                        Button {
                            camera.setPhotoFlashMode(mode)
                        } label: {
                            if camera.photoFlashMode == mode {
                                Label(mode.title, systemImage: "checkmark")
                            } else {
                                Text(mode.title)
                            }
                        }
                    }
                } label: {
                    Label(camera.photoFlashMode.title, systemImage: "bolt.fill")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 34)
                        .background(Color.white.opacity(0.1), in: Capsule())
                }
                .tint(CamProTheme.accent)
                .accessibilityLabel("Flash mode")

                Menu {
                    ForEach(PhotoAspectRatio.allCases) { ratio in
                        Button {
                            camera.setPhotoAspectRatio(ratio)
                        } label: {
                            if camera.photoAspectRatio == ratio {
                                Label(ratio.title, systemImage: "checkmark")
                            } else {
                                Text(ratio.title)
                            }
                        }
                    }
                } label: {
                    Text(camera.photoAspectRatio.title)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 34)
                        .background(Color.white.opacity(0.1), in: Capsule())
                }
                .tint(CamProTheme.accent)
                .accessibilityLabel("Photo aspect ratio")
            }

            Toggle("Manual controls", isOn: Binding(
                get: { camera.manualControlsEnabled },
                set: { camera.setManualControlsEnabled($0) }
            ))
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.86))
            .tint(CamProTheme.accent)

            if camera.manualControlsEnabled {
                VStack(spacing: 8) {
                    HStack {
                        Text("FOCUS")
                        Slider(value: Binding(
                            get: { Double(camera.manualFocusPosition) },
                            set: { camera.setManualFocusPosition(Float($0)) }
                        ), in: 0...1)
                        .tint(CamProTheme.accent)
                    }
                    HStack {
                        Text("EXPOSURE")
                        Slider(value: Binding(
                            get: { Double(camera.exposureBias) },
                            set: { camera.setExposureBias(Float($0)) }
                        ), in: -2...2)
                        .tint(CamProTheme.accent)
                    }
                }
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
            }
        }
        .padding(.horizontal, 28)
    }

    private var permissionCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.fill")
                .font(.system(size: 28))
                .foregroundStyle(.white)
            Text("Camera access is required")
                .font(.system(size: 19, weight: .bold, design: .rounded))
            Text("Enable camera access in Settings to capture photos.")
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

private struct ScaleButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.92

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

private struct FocusReticle: View {
    @State private var visible = false

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(Color.white, lineWidth: 1.5)
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
