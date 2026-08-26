import AVFoundation
import SwiftUI
import UIKit

struct ContentView: View {
    @ObservedObject var camera: CameraModel
    @ObservedObject var settings: CamProSettings

    @State private var focusPoint: CGPoint?
    @State private var focusAnimationID = UUID()
    @State private var showSettings = false
    @State private var showManualPanel = false

    private let glassAccent = Color(red: 1.0, green: 0.86, blue: 0.08)

    private var zoomPresets: [CGFloat] {
        camera.captureMode == .photo ? [1.0, 2.0, 3.0, 4.0, 5.0] : [1.0, 2.0]
    }

    private var previewAspectRatio: CGFloat {
        guard camera.captureMode == .photo else { return 3.0 / 4.0 }
        switch camera.photoAspectRatio {
        case .fourThree: return 3.0 / 4.0
        case .sixteenNine: return 9.0 / 16.0
        case .square: return 1.0
        }
    }

    private var showsPhotoFocus: Bool {
        camera.captureMode == .photo && camera.photoLens == .wide
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            previewSurface
                .ignoresSafeArea()
        }
        .overlay(alignment: .top) {
            topControlStrip
                .ignoresSafeArea(edges: .horizontal)
        }
        .overlay(alignment: .bottom) {
            bottomControlSystem
                .ignoresSafeArea(edges: .horizontal)
                .zIndex(2)
        }
        .overlay {
            if camera.permissionDenied {
                permissionCard
            }
        }
        .task {
            camera.start()
        }
        .onDisappear {
            camera.stop()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: settings)
        }
    }

    private var topControlStrip: some View {
        GeometryReader { proxy in
            HStack(spacing: 4) {
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
                    GlassIconButton(
                        systemImage: camera.photoFlashMode == .off
                            ? "bolt.slash.fill"
                            : "bolt.fill",
                        diameter: 46,
                        isActive: camera.photoFlashMode != .off
                    )
                }
                .tint(.white)
                .accessibilityLabel("Flash")

                if camera.captureMode == .photo {
                    Menu {
                        ForEach(PhotoAspectRatio.allCases) { ratio in
                            Button {
                                withAnimation(.easeInOut(duration: 0.20)) {
                                    camera.setPhotoAspectRatio(ratio)
                                }
                            } label: {
                                if camera.photoAspectRatio == ratio {
                                    Label(ratio.title, systemImage: "checkmark")
                                } else {
                                    Text(ratio.title)
                                }
                            }
                        }
                    } label: {
                        GlassRatioButton(title: camera.photoAspectRatio.title)
                    }
                    .tint(.white)
                    .accessibilityLabel("Photo aspect ratio")
                }

                Button {
                    showSettings = true
                } label: {
                    GlassIconButton(systemImage: "gearshape", diameter: 46)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
            }
            .padding(.horizontal, 10)
            .frame(height: 58)
            .background(.thinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.18), lineWidth: 0.8)
            }
            .padding(.top, proxy.safeAreaInsets.top + 12)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(height: 80)
    }

    private var previewSurface: some View {
        GeometryReader { proxy in
            let fittedWidth = min(proxy.size.width, proxy.size.height * previewAspectRatio)
            let fittedHeight = min(proxy.size.height, proxy.size.width / previewAspectRatio)

            ZStack {
                Color.black

                CameraPreview(
                    session: camera.session,
                    zoomFactor: camera.zoomFactor,
                    deviceZoomFactor: camera.deviceZoomFactor,
                    // The interface stays portrait-locked. Saved output follows physical orientation.
                    videoOrientation: .portrait,
                    onTap: { viewPoint, devicePoint in
                        guard !camera.manualControlsEnabled else { return }
                        camera.focus(at: devicePoint)
                        focusPoint = viewPoint
                        focusAnimationID = UUID()
                    }
                )
                .frame(width: fittedWidth, height: fittedHeight)
                .overlay {
                    if let focusPoint, !camera.manualControlsEnabled {
                        FocusReticle()
                            .id(focusAnimationID)
                            .position(focusPoint)
                    }
                }
                .position(
                    x: proxy.size.width / 2,
                    y: proxy.size.height / 2
                )
                .animation(.easeInOut(duration: 0.20), value: camera.photoAspectRatio)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
        }
    }

    private var bottomControlSystem: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 2)
                    lowerControlRow
                    bottomNavigationRow
                        .padding(.top, 10)
                }
                .padding(.bottom, proxy.safeAreaInsets.bottom + 8)
                .frame(maxWidth: .infinity)
                .background {
                    ZStack {
                        Color.black.opacity(0.46)
                        Rectangle().fill(.ultraThinMaterial)
                    }
                }

                if showManualPanel {
                    manualPanel
                        .padding(.bottom, proxy.safeAreaInsets.bottom + 150)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .animation(.easeOut(duration: 0.18), value: showManualPanel)
        }
    }

    private var lowerControlRow: some View {
        HStack(spacing: 0) {
            lensSwitchButton
                .frame(maxWidth: .infinity)

            VStack(spacing: 5) {
                zoomButton
                shutterButton
            }
            .frame(maxWidth: .infinity)

            manualButton
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 18)
        .frame(height: 158)
    }

    private var bottomNavigationRow: some View {
        HStack(spacing: 0) {
            latestPhotoButton
                .frame(maxWidth: .infinity, alignment: .leading)

            modePicker
                .frame(maxWidth: .infinity)

            rotateCameraButton
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .frame(height: 64)
    }

    private var lensSwitchButton: some View {
        Button {
            guard camera.captureMode == .photo else { return }
            let nextLens: PhotoLens = camera.photoLens == .wide ? .ultraWide : .wide
            camera.setPhotoLens(nextLens)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: "camera.aperture")
                    .font(.system(size: 21, weight: .medium))
                Text(camera.captureMode == .photo ? camera.photoLens.title : "1×")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(camera.captureMode == .photo ? glassAccent : .white.opacity(0.45))
            }
            .foregroundStyle(.white)
            .frame(width: 70, height: 70)
            .background(.thinMaterial, in: Circle())
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.18), lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
        .disabled(camera.captureMode != .photo)
        .accessibilityLabel("Lens switch")
    }

    private var zoomButton: some View {
        Button {
            advanceZoom()
        } label: {
            Text("\(camera.zoomFactor, specifier: \"%.0f\")×")
                .font(.system(size: 19, weight: .medium, design: .rounded))
                .foregroundStyle(glassAccent)
                .frame(width: 64, height: 52)
                .background(.thinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.13), lineWidth: 0.8)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "Zoom \(camera.zoomFactor, specifier: \"%.0f\") times; tap to change"
        )
    }

    private var shutterButton: some View {
        Button {
            camera.capturePhoto()
        } label: {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.16))
                    .frame(width: 84, height: 84)
                Circle()
                    .fill(camera.isCapturing ? .white.opacity(0.45) : .white)
                    .frame(width: 68, height: 68)
            }
        }
        .buttonStyle(.plain)
        .disabled(camera.isCapturing || !camera.isConfigured || !camera.isRunning)
        .scaleEffect(camera.isCapturing ? 0.94 : 1.0)
        .animation(.easeOut(duration: 0.16), value: camera.isCapturing)
        .accessibilityLabel("Shutter")
    }

    private var manualButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) {
                showManualPanel.toggle()
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 23, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 70, height: 70)
                .background(.thinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.18), lineWidth: 0.8)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Manual controls")
    }

    private func advanceZoom() {
        let currentIndex = zoomPresets.firstIndex {
            abs($0 - camera.zoomFactor) < 0.08
        } ?? 0
        let nextIndex = (currentIndex + 1) % zoomPresets.count
        camera.setZoomFactor(zoomPresets[nextIndex])
    }

    private var latestPhotoButton: some View {
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
            .frame(width: 58, height: 58)
            .clipShape(Circle())
            .background(.thinMaterial, in: Circle())
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.20), lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
        .disabled(camera.latestPhotoImage == nil)
        .accessibilityLabel(
            camera.latestPhotoImage == nil
                ? "No photo captured yet"
                : "Open latest photo in Photos"
        )
    }

    private var modePicker: some View {
        HStack(spacing: 2) {
            ForEach(CaptureMode.allCases) { mode in
                Button {
                    camera.setCaptureMode(mode)
                    focusPoint = nil
                    showManualPanel = false
                } label: {
                    Text(mode.title)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(
                            camera.captureMode == mode ? glassAccent : .white.opacity(0.86)
                        )
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(
                            camera.captureMode == mode
                                ? Color.white.opacity(0.12)
                                : Color.clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(
                    camera.captureMode == mode ? .isSelected : []
                )
            }
        }
        .padding(3)
        .frame(width: 236, height: 54)
        .background(.thinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.16), lineWidth: 0.8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Capture mode")
    }

    private var rotateCameraButton: some View {
        Button {
            // Build 27 intentionally exposes rear-camera capture only. Keep the
            // supplied control visible while selfie capture remains out of scope.
        } label: {
            Image(systemName: "camera.rotate")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 58, height: 58)
                .background(.thinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.12), lineWidth: 0.8)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Selfie camera unavailable in this build")
    }

    private var manualPanel: some View {
        VStack(spacing: 8) {
            HStack {
                Text("MANUAL")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.78))
                Spacer(minLength: 12)
                Toggle(
                    "",
                    isOn: Binding(
                        get: { camera.manualControlsEnabled },
                        set: { camera.setManualControlsEnabled($0) }
                    )
                )
                .labelsHidden()
                .tint(glassAccent)
                .accessibilityLabel("Lock manual settings")
            }
            .frame(height: 28)

            if showsPhotoFocus {
                CameraSliderRow(
                    label: "FOCUS",
                    value: Binding(
                        get: { Double(camera.manualFocusPosition) },
                        set: { camera.setManualFocusPosition(Float($0)) }
                    ),
                    range: 0...1,
                    display: { value in String(format: "%.0f%%", value * 100) },
                    enabled: camera.manualControlsEnabled,
                    accent: glassAccent
                )
            }

            CameraSliderRow(
                label: "EV",
                value: Binding(
                    get: { Double(camera.exposureBias) },
                    set: { camera.setExposureBias(Float($0)) }
                ),
                range: -2...2,
                display: { value in String(format: "%+.1f", value) },
                enabled: camera.manualControlsEnabled,
                accent: glassAccent
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 0.8)
        }
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

private struct GlassIconButton: View {
    let systemImage: String
    let diameter: CGFloat
    var isActive = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: diameter, height: diameter)
            .background(
                isActive ? Color.white.opacity(0.16) : Color.clear,
                in: Circle()
            )
    }
}

private struct GlassRatioButton: View {
    let title: String

    var body: some View {
        VStack(spacing: 1) {
            Image(systemName: "viewfinder")
                .font(.system(size: 15, weight: .medium))
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(.white)
        .frame(width: 54, height: 46)
    }
}

private struct CameraSliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let display: (Double) -> String
    let enabled: Bool
    let accent: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(0.4)
                .foregroundStyle(.white.opacity(enabled ? 0.86 : 0.46))
                .frame(width: 42, alignment: .leading)

            Slider(value: $value, in: range)
                .tint(accent)
                .disabled(!enabled)

            Text(display(value))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(enabled ? 0.74 : 0.40))
                .frame(width: 34, alignment: .trailing)
        }
        .opacity(enabled ? 1.0 : 0.60)
        .frame(minHeight: 32)
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
                withAnimation(.easeOut(duration: 0.14)) {
                    visible = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    withAnimation(.easeIn(duration: 0.2)) {
                        visible = false
                    }
                }
            }
    }
}
