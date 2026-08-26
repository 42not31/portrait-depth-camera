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

    private let cameraYellow = Color(red: 1.0, green: 0.84, blue: 0.0)
    private let glassFill = Color.white.opacity(0.10)
    private let glassBorder = Color.white.opacity(0.22)

    private var zoomPresets: [CGFloat] {
        camera.captureMode == .photo ? [1.0, 2.0, 3.0, 4.0, 5.0] : [1.0, 2.0]
    }

    private var previewAspectRatio: CGFloat {
        guard camera.captureMode == .photo else { return 3.0 / 4.0 }
        switch camera.photoAspectRatio {
        case .fourThree:
            return 3.0 / 4.0
        case .sixteenNine:
            return 9.0 / 16.0
        case .square:
            return 1.0
        }
    }

    private var aspectRatioDisplayTitle: String {
        guard camera.captureMode == .photo else { return "4:3" }
        switch camera.photoAspectRatio {
        case .fourThree:
            return "4:3"
        case .sixteenNine:
            return "9:16"
        case .square:
            return "1:1"
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
            topControlBar
                .safeAreaPadding(.top, 6)
        }
        .overlay(alignment: .bottom) {
            bottomControlSystem
                .safeAreaPadding(.bottom, 4)
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

    private var topControlBar: some View {
        HStack(spacing: 0) {
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
                TopControlIcon(
                    systemImage: camera.photoFlashMode == .off ? "bolt.slash" : "bolt.fill",
                    accessibilityLabel: "Flash"
                )
            }
            .tint(.white)
            .frame(maxWidth: .infinity)

            topSeparator

            if camera.captureMode == .photo {
                Menu {
                    ForEach(PhotoAspectRatio.allCases) { ratio in
                        Button {
                            withAnimation(.easeInOut(duration: 0.24)) {
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
                    AspectRatioControl(title: aspectRatioDisplayTitle)
                }
                .tint(.white)
                .frame(maxWidth: .infinity)
            } else {
                AspectRatioControl(title: "4:3")
                    .frame(maxWidth: .infinity)
                    .opacity(0.45)
            }

            topSeparator

            Button {
                showSettings = true
            } label: {
                TopControlIcon(
                    systemImage: "gearshape",
                    accessibilityLabel: "Settings"
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
        .frame(width: 320, height: 58)
        .background(.thinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(glassBorder, lineWidth: 0.8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Camera controls")
    }

    private var topSeparator: some View {
        Rectangle()
            .fill(Color.white.opacity(0.22))
            .frame(width: 1, height: 26)
            .accessibilityHidden(true)
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
                    videoOrientation: .portrait,
                    onTap: { viewPoint, devicePoint in
                        guard !camera.manualControlsEnabled else { return }
                        camera.focus(at: devicePoint)
                        focusPoint = viewPoint
                        focusAnimationID = UUID()
                    }
                )
                .frame(width: fittedWidth, height: fittedHeight)
                .clipShape(Rectangle())
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
                .animation(.easeInOut(duration: 0.24), value: camera.photoAspectRatio)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
        }
    }

    private var bottomControlSystem: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                lowerControlRow

                if showManualPanel {
                    manualPanel
                        .padding(.bottom, 168)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity)

            bottomNavigationRow
                .background(Color.black)
        }
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.18), value: showManualPanel)
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
        .frame(height: 168)
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
        .frame(height: 76)
    }

    private var lensSwitchButton: some View {
        Button {
            guard camera.captureMode == .photo else { return }
            let nextLens: PhotoLens = camera.photoLens == .wide ? .ultraWide : .wide
            camera.setPhotoLens(nextLens)
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 25, weight: .regular))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(.thinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .stroke(glassBorder, lineWidth: 0.8)
                }
        }
        .buttonStyle(.plain)
        .disabled(camera.captureMode != .photo)
        .opacity(camera.captureMode == .photo ? 1.0 : 0.42)
        .accessibilityLabel("Lens switch")
    }

    private var zoomButton: some View {
        Button {
            advanceZoom()
        } label: {
            Text("\(camera.zoomFactor, specifier: "%.0f")×")
                .font(.system(size: 18, weight: .semibold, design: .default))
                .foregroundStyle(cameraYellow)
                .frame(width: 58, height: 50)
                .background(.thinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.20), lineWidth: 1.0)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "Zoom \(camera.zoomFactor, specifier: "%.0f") times; tap to change"
        )
    }

    private var shutterButton: some View {
        Button {
            camera.capturePhoto()
        } label: {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 82, height: 82)
                Circle()
                    .fill(camera.isCapturing ? Color.white.opacity(0.45) : .white)
                    .frame(width: 68, height: 68)
            }
        }
        .buttonStyle(.plain)
        .disabled(camera.isCapturing || !camera.isConfigured || !camera.isRunning)
        .scaleEffect(camera.isCapturing ? 0.96 : 1.0)
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
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(.thinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .stroke(glassBorder, lineWidth: 0.8)
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
                    Color.clear
                }
            }
            .frame(width: 58, height: 58)
            .clipShape(Circle())
            .background(Color.white.opacity(0.08), in: Circle())
            .overlay {
                Circle()
                    .stroke(glassBorder, lineWidth: 0.8)
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
        HStack(spacing: 0) {
            modeButton(.photo)
            Rectangle()
                .fill(Color.white.opacity(0.25))
                .frame(width: 1, height: 25)
                .accessibilityHidden(true)
            modeButton(.portrait)
        }
        .padding(.horizontal, 3)
        .frame(width: 236, height: 54)
        .background(.thinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(glassBorder, lineWidth: 0.8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Capture mode")
    }

    private func modeButton(_ mode: CaptureMode) -> some View {
        Button {
            camera.setCaptureMode(mode)
            focusPoint = nil
            showManualPanel = false
        } label: {
            Text(mode.title.uppercased())
                .font(.system(size: 15, weight: .medium, design: .default))
                .foregroundStyle(
                    camera.captureMode == mode ? cameraYellow : .white.opacity(0.90)
                )
                .frame(maxWidth: .infinity, minHeight: 46)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(
            camera.captureMode == mode ? .isSelected : []
        )
    }

    private var rotateCameraButton: some View {
        Button {
            // Build 27 intentionally exposes rear-camera capture only.
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 25, weight: .regular))
                .foregroundStyle(.white.opacity(0.46))
                .frame(width: 58, height: 58)
                .background(.thinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Selfie camera unavailable in this build")
    }

    private var manualPanel: some View {
        VStack(spacing: 8) {
            HStack {
                Text("MANUAL")
                    .font(.system(size: 12, weight: .semibold, design: .default))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.82))
                Spacer(minLength: 12)
                Toggle(
                    "",
                    isOn: Binding(
                        get: { camera.manualControlsEnabled },
                        set: { camera.setManualControlsEnabled($0) }
                    )
                )
                .labelsHidden()
                .tint(cameraYellow)
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
                    accent: cameraYellow
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
                accent: cameraYellow
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: 312)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
        }
    }

    private var permissionCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.fill")
                .font(.system(size: 28))
                .foregroundStyle(.white)
            Text("Camera access is required")
                .font(.system(size: 19, weight: .bold, design: .default))
            Text("Enable camera access in Settings to capture photos.")
                .font(.system(size: 14, weight: .regular, design: .default))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .padding(28)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(28)
    }
}

private struct TopControlIcon: View {
    let systemImage: String
    let accessibilityLabel: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 22, weight: .regular))
            .foregroundStyle(.white)
            .frame(width: 72, height: 52)
            .contentShape(Rectangle())
            .accessibilityLabel(accessibilityLabel)
    }
}

private struct AspectRatioControl: View {
    let title: String

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "viewfinder")
                .font(.system(size: 16, weight: .regular))
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .default))
        }
        .foregroundStyle(.white)
        .frame(width: 72, height: 52)
        .contentShape(Rectangle())
        .accessibilityLabel("Aspect ratio \(title)")
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
                .font(.system(size: 10, weight: .semibold, design: .default))
                .tracking(0.4)
                .foregroundStyle(.white.opacity(enabled ? 0.86 : 0.46))
                .frame(width: 42, alignment: .leading)

            Slider(value: $value, in: range)
                .tint(accent)
                .disabled(!enabled)

            Text(display(value))
                .font(.system(size: 10, weight: .semibold, design: .default))
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
        Rectangle()
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
