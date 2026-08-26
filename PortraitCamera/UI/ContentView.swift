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

    private let topBarHeight: CGFloat = 58
    private let dockHeight: CGFloat = 194

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
        GeometryReader { proxy in
            let topInset = max(proxy.safeAreaInsets.top, 0)
            let bottomInset = max(proxy.safeAreaInsets.bottom, 0)
            let previewTop = topInset + topBarHeight
            let previewBottom = bottomInset + dockHeight
            let previewHeight = max(1, proxy.size.height - previewTop - previewBottom)
            let previewRegion = CGRect(
                x: 0,
                y: previewTop,
                width: proxy.size.width,
                height: previewHeight
            )

            ZStack {
                Color.black

                previewSurface(in: previewRegion)
                    .animation(.easeInOut(duration: 0.22), value: camera.photoAspectRatio)

                VStack(spacing: 0) {
                    header
                        .padding(.top, topInset)
                        .frame(
                            width: proxy.size.width,
                            height: previewTop,
                            alignment: .bottom
                        )
                    Spacer(minLength: 0)
                }

                cameraControls(
                    width: proxy.size.width,
                    height: proxy.size.height,
                    bottomInset: bottomInset
                )

                if camera.permissionDenied {
                    permissionCard
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
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
            Spacer(minLength: 0)

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
                    systemImage: camera.photoFlashMode == .off
                        ? "bolt.slash.fill"
                        : "bolt.fill",
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
                    .background(.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.72),
                    Color.black.opacity(0.18),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        }
    }

    private func previewSurface(in region: CGRect) -> some View {
        let previewWidth = max(1, min(region.width, region.height * previewAspectRatio))
        let previewHeight = max(1, min(region.height, region.width / previewAspectRatio))

        return ZStack {
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
            .frame(width: previewWidth, height: previewHeight)
            .overlay {
                if let focusPoint, !camera.manualControlsEnabled {
                    FocusReticle()
                        .id(focusAnimationID)
                        .position(focusPoint)
                }
            }
            .position(x: region.width / 2, y: region.height / 2)
        }
        .frame(width: region.width, height: region.height)
        .position(x: region.midX, y: region.midY)
    }

    private func cameraControls(
        width: CGFloat,
        height: CGFloat,
        bottomInset: CGFloat
    ) -> some View {
        ZStack(alignment: .bottom) {
            cameraDock
                .padding(.bottom, bottomInset)

            if showManualPanel {
                manualPanel
                    .padding(.bottom, bottomInset + dockHeight + 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(width: width, height: height, alignment: .bottom)
        .animation(
            .spring(response: 0.28, dampingFraction: 0.86),
            value: showManualPanel
        )
    }

    private var cameraDock: some View {
        VStack(spacing: 10) {
            modePicker
            lowerControlRow
            captureRow
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.12),
                    Color.black.opacity(0.72),
                    Color.black.opacity(0.98)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(.white.opacity(0.10))
                    .frame(height: 1)
            }
            .ignoresSafeArea(edges: .bottom)
        }
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
                        .font(.system(size: 12, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(
                            camera.captureMode == mode
                                ? .white
                                : .white.opacity(0.62)
                        )
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(
                            camera.captureMode == mode
                                ? CamProTheme.accent
                                : .clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(
                    camera.captureMode == mode ? .isSelected : []
                )
            }
        }
        .padding(2)
        .frame(width: 236, height: 36)
        .background(.white.opacity(0.12), in: Capsule())
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
                    Color.clear.frame(width: 118, height: 44)
                }

                Spacer(minLength: 0)
                manualButton
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 18)
    }

    private var lensToggle: some View {
        HStack(spacing: 2) {
            ForEach(PhotoLens.allCases) { lens in
                Button {
                    camera.setPhotoLens(lens)
                } label: {
                    Text(lens.title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(
                            camera.photoLens == lens
                                ? .white
                                : .white.opacity(0.68)
                        )
                        .frame(minWidth: 48, minHeight: 38)
                        .background(
                            camera.photoLens == lens
                                ? CamProTheme.accent
                                : .clear,
                            in: RoundedRectangle(
                                cornerRadius: 9,
                                style: .continuous
                            )
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
        .background(.thinMaterial, in: RoundedRectangle(
            cornerRadius: 12,
            style: .continuous
        ))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        }
    }

    private var zoomButton: some View {
        Button {
            advanceZoom()
        } label: {
            Text("\(camera.zoomFactor, specifier: "%.0f")×")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 42)
                .background(CamProTheme.accent, in: Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.24), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "Software zoom \(camera.zoomFactor, specifier: "%.0f") times; tap to change"
        )
    }

    private var manualButton: some View {
        Button {
            withAnimation {
                showManualPanel.toggle()
            }
        } label: {
            Text("Manual")
                .font(.system(size: 12, weight: .bold))
                .tracking(0.3)
                .foregroundStyle(.white)
                .frame(width: 78, height: 40)
                .background(
                    showManualPanel || camera.manualControlsEnabled
                        ? CamProTheme.accent
                        : .white.opacity(0.12),
                    in: RoundedRectangle(
                        cornerRadius: 11,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(.white.opacity(0.14), lineWidth: 1)
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
                .frame(width: 54, height: 54)
                .clipShape(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .background(
                    .white.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.22), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .disabled(camera.latestPhotoImage == nil)
            .accessibilityLabel(
                camera.latestPhotoImage == nil
                    ? "No photo captured yet"
                    : "Open latest photo in Photos"
            )

            Spacer(minLength: 0)

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
            .animation(.easeOut(duration: 0.16), value: camera.isCapturing)
            .accessibilityLabel("Shutter")

            Spacer(minLength: 0)
            Color.clear.frame(width: 54, height: 54)
        }
        .padding(.horizontal, 28)
    }

    private var manualPanel: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Text("Manual")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))

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
            .frame(height: 28)

            if showsPhotoFocus {
                CameraSliderRow(
                    label: "FOCUS",
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

            CameraSliderRow(
                label: "EV",
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
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: 320)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .padding(.horizontal, 16)
    }

    private var permissionCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.fill")
                .font(.system(size: 28))
                .foregroundStyle(.white)
            Text("Camera access is required")
                .font(.system(size: 19, weight: .bold))
            Text("Enable camera access in Settings to capture photos.")
                .font(.system(size: 14))
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
                    : .white.opacity(0.12),
                in: Circle()
            )
            .contentShape(Circle())
    }
}

private struct HeaderTextButton: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(minWidth: 44, minHeight: 44)
            .padding(.horizontal, 5)
            .background(.white.opacity(0.12), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            }
    }
}

private struct CameraSliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let display: (Double) -> String
    let enabled: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(.white.opacity(enabled ? 0.86 : 0.42))
                .frame(width: 42, alignment: .leading)

            Slider(value: $value, in: range)
                .tint(CamProTheme.accent)
                .disabled(!enabled)

            Text(display(value))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(enabled ? 0.72 : 0.38))
                .frame(width: 34, alignment: .trailing)
        }
        .opacity(enabled ? 1.0 : 0.56)
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
