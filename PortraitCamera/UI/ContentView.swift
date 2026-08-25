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

    private var zoomPresets: [CGFloat] {
        camera.captureMode == .photo ? [1.0, 2.0, 3.0, 4.0, 5.0] : [1.0, 2.0]
    }

    private var isFullBleedPhoto: Bool {
        camera.captureMode == .photo && camera.photoAspectRatio == .sixteenNine
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

    private var showsPortraitDepth: Bool {
        camera.captureMode == .portrait
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            previewSurface
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Spacer(minLength: 0)
            }

            if showManualPanel {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    manualPanel
                        .padding(.horizontal, 18)
                        .padding(.bottom, 176)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                cameraDock
            }

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

    private var header: some View {
        HStack(spacing: 8) {
            Text("CAMPRO")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .tracking(2.2)
                .foregroundStyle(.white)

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
                HeaderIconButton(
                    systemImage: camera.photoFlashMode == .off ? "bolt.slash.fill" : "bolt.fill",
                    isSelected: camera.photoFlashMode != .off
                )
            }
            .tint(CamProTheme.accent)
            .accessibilityLabel("Flash")

            if camera.captureMode == .photo {
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
                    HeaderTextButton(title: camera.photoAspectRatio.title)
                }
                .tint(CamProTheme.accent)
                .accessibilityLabel("Photo aspect ratio")
            }

            Button {
                showSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white.opacity(0.94))
                    .frame(width: 44, height: 44)
                    .background(CamProTheme.accentMuted, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private var previewSurface: some View {
        GeometryReader { proxy in
            let previewWidth = proxy.size.width
            let previewHeight = isFullBleedPhoto
                ? proxy.size.height
                : min(proxy.size.height, previewWidth / previewAspectRatio)

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
                .overlay {
                    if let focusPoint, !camera.manualControlsEnabled {
                        FocusReticle()
                            .id(focusAnimationID)
                            .position(focusPoint)
                    }
                }
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: isFullBleedPhoto ? 0 : 24,
                        style: .continuous
                    )
                )
                .frame(width: previewWidth, height: previewHeight)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private var cameraDock: some View {
        VStack(spacing: 12) {
            modePicker
            lowerControlRow
            captureRow
        }
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(
            isFullBleedPhoto
                ? Color.black.opacity(0.20)
                : Color.black.opacity(0.86),
            in: RoundedRectangle(
                cornerRadius: isFullBleedPhoto ? 0 : 28,
                style: .continuous
            )
        )
        .padding(.horizontal, isFullBleedPhoto ? 0 : 10)
    }

    private var modePicker: some View {
        HStack(spacing: 3) {
            ForEach(CaptureMode.allCases) { mode in
                Button {
                    camera.setCaptureMode(mode)
                    focusPoint = nil
                    showManualPanel = false
                } label: {
                    Text(mode.title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .tracking(0.6)
                        .foregroundStyle(
                            camera.captureMode == mode
                                ? .white
                                : .white.opacity(0.66)
                        )
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(
                            camera.captureMode == mode
                                ? CamProTheme.accent
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
        .background(Color.white.opacity(0.10), in: Capsule())
        .padding(.horizontal, 18)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Capture mode")
    }

    private var lowerControlRow: some View {
        ZStack {
            zoomButton

            HStack {
                if camera.captureMode == .photo {
                    lensToggle
                } else {
                    Color.clear.frame(width: 112, height: 44)
                }

                Spacer(minLength: 0)
                manualButton
            }
        }
        .padding(.horizontal, 18)
    }

    private var lensToggle: some View {
        HStack(spacing: 3) {
            ForEach(PhotoLens.allCases) { lens in
                Button {
                    camera.setPhotoLens(lens)
                } label: {
                    Text(lens.title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            camera.photoLens == lens
                                ? .white
                                : .white.opacity(0.70)
                        )
                        .frame(minWidth: 52, minHeight: 40)
                        .background(
                            camera.photoLens == lens
                                ? CamProTheme.accent
                                : Color.clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Photo lens \(lens.title)")
                .accessibilityAddTraits(
                    camera.photoLens == lens ? .isSelected : []
                )
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.10), in: Capsule())
    }

    private var zoomButton: some View {
        Button {
            advanceZoom()
        } label: {
            Text("\(camera.zoomFactor, specifier: "%.0f")×")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(minWidth: 64, minHeight: 42)
                .background(CamProTheme.accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "Zoom \(camera.zoomFactor, specifier: "%.0f") times; tap to change"
        )
    }

    private var manualButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) {
                showManualPanel.toggle()
            }
        } label: {
            Image(
                systemName: camera.manualControlsEnabled
                    ? "lock.fill"
                    : "lock.open"
            )
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(
                showManualPanel || camera.manualControlsEnabled
                    ? CamProTheme.accent
                    : Color.white.opacity(0.12),
                in: Circle()
            )
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

    private var captureRow: some View {
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
                .clipShape(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .background(
                    Color.white.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .disabled(camera.latestPhotoImage == nil)
            .accessibilityLabel(
                camera.latestPhotoImage == nil
                    ? "No photo captured yet"
                    : "Open latest photo in Photos"
            )

            Spacer()

            Button {
                camera.capturePhoto()
            } label: {
                ZStack {
                    Circle()
                        .stroke(.white, lineWidth: 4)
                        .frame(width: 76, height: 76)
                    Circle()
                        .fill(
                            camera.isCapturing
                                ? .white.opacity(0.45)
                                : .white
                        )
                        .frame(width: 62, height: 62)
                }
            }
            .buttonStyle(.plain)
            .disabled(
                camera.isCapturing || !camera.isConfigured || !camera.isRunning
            )
            .scaleEffect(camera.isCapturing ? 0.94 : 1.0)
            .animation(
                .easeOut(duration: 0.16),
                value: camera.isCapturing
            )
            .accessibilityLabel("Shutter")

            Spacer()
            Color.clear.frame(width: 56, height: 56)
        }
        .padding(.horizontal, 28)
    }

    private var manualPanel: some View {
        VStack(spacing: 8) {
            HStack {
                Image(
                    systemName: camera.manualControlsEnabled
                        ? "lock.fill"
                        : "lock.open"
                )
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))

                Spacer(minLength: 0)

                Toggle(
                    "",
                    isOn: Binding(
                        get: { camera.manualControlsEnabled },
                        set: { camera.setManualControlsEnabled($0) }
                    )
                )
                .labelsHidden()
                .tint(CamProTheme.accent)
                .accessibilityLabel("Lock manual settings")
            }
            .frame(minHeight: 34)

            if showsPhotoFocus {
                CameraSliderRow(
                    systemImage: "scope",
                    value: Binding(
                        get: { Double(camera.manualFocusPosition) },
                        set: { camera.setManualFocusPosition(Float($0)) }
                    ),
                    range: 0...1,
                    display: { value in
                        String(format: "%.0f%%", value * 100)
                    },
                    enabled: camera.manualControlsEnabled
                )
            }

            if showsPortraitDepth {
                CameraSliderRow(
                    systemImage: "camera.aperture",
                    value: Binding(
                        get: { Double(camera.portraitDepth) },
                        set: { camera.setPortraitDepth(Float($0)) }
                    ),
                    range: 0...1,
                    display: { value in
                        String(format: "%.0f%%", value * 100)
                    },
                    enabled: camera.manualControlsEnabled
                )
            }

            CameraSliderRow(
                systemImage: "sun.max",
                value: Binding(
                    get: { Double(camera.exposureBias) },
                    set: { camera.setExposureBias(Float($0)) }
                ),
                range: -2...2,
                display: { value in
                    String(format: "%+.1f", value)
                },
                enabled: camera.manualControlsEnabled
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
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
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .padding(28)
    }
}

private struct HeaderIconButton: View {
    let systemImage: String
    let isSelected: Bool

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(
                isSelected
                    ? CamProTheme.accentMuted
                    : Color.white.opacity(0.11),
                in: Circle()
            )
    }
}

private struct HeaderTextButton: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(minWidth: 44, minHeight: 44)
            .padding(.horizontal, 5)
            .background(Color.white.opacity(0.11), in: Capsule())
    }
}

private struct CameraSliderRow: View {
    let systemImage: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let display: (Double) -> String
    let enabled: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(enabled ? 0.88 : 0.42))
                .frame(width: 24)

            Slider(value: $value, in: range)
                .tint(CamProTheme.accent)
                .disabled(!enabled)

            Text(display(value))
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(enabled ? 0.72 : 0.38))
                .frame(width: 34, alignment: .trailing)
        }
        .opacity(enabled ? 1.0 : 0.56)
        .frame(minHeight: 30)
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
