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

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    header

                    ZStack(alignment: .bottom) {
                        preview

                        if camera.captureMode == .photo && camera.manualControlsEnabled {
                            compactManualPanel
                                .padding(.horizontal, 18)
                                .padding(.bottom, 18)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    cameraDock
                        .padding(.bottom, max(12, proxy.safeAreaInsets.bottom))
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
            SettingsView(settings: settings)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text("CAMPRO")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .tracking(2.2)
                    .foregroundStyle(.white)

                if settings.showDepthIndicator {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(camera.captureMode == .portrait && camera.depthCaptureAvailable ? CamProTheme.accent : .gray)
                            .frame(width: 6, height: 6)
                        Text(camera.captureMode == .portrait
                             ? (camera.depthCaptureAvailable ? "DEPTH READY" : "STANDARD DEPTH")
                             : "SINGLE FRAME PHOTO")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .tracking(1.1)
                            .foregroundStyle(.white.opacity(0.64))
                    }
                }
            }

            Spacer(minLength: 8)

            if camera.captureMode == .photo {
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
                    topControlLabel(
                        systemImage: "bolt.fill",
                        title: camera.photoFlashMode.title
                    )
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
                    topControlLabel(
                        systemImage: "aspectratio",
                        title: camera.photoAspectRatio.title
                    )
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
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    private func topControlLabel(systemImage: String, title: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold))
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
        }
        .foregroundStyle(.white)
        .frame(minWidth: 48, minHeight: 40)
        .padding(.horizontal, 4)
        .background(Color.white.opacity(0.11), in: Capsule())
    }

    private var preview: some View {
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
    }

    private var cameraDock: some View {
        VStack(spacing: 12) {
            modePicker

            HStack(spacing: 10) {
                if camera.captureMode == .photo {
                    lensToggle
                }

                manualButton

                Spacer(minLength: 0)

                zoomButton
            }
            .padding(.horizontal, 20)

            captureRow
        }
        .padding(.top, 12)
    }

    private var modePicker: some View {
        HStack(spacing: 3) {
            ForEach(CaptureMode.allCases) { mode in
                Button {
                    camera.setCaptureMode(mode)
                } label: {
                    Text(mode.title.uppercased())
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .tracking(0.6)
                        .foregroundStyle(camera.captureMode == mode ? .white : .white.opacity(0.68))
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(
                            camera.captureMode == mode ? CamProTheme.accent : Color.clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(camera.captureMode == mode ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.10), in: Capsule())
        .padding(.horizontal, 20)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Capture mode")
    }

    private var lensToggle: some View {
        HStack(spacing: 3) {
            ForEach(PhotoLens.allCases) { lens in
                Button {
                    camera.setPhotoLens(lens)
                } label: {
                    Text(lens.title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(camera.photoLens == lens ? .white : .white.opacity(0.70))
                        .frame(minWidth: 52, minHeight: 40)
                        .background(
                            camera.photoLens == lens ? CamProTheme.accent : Color.clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Photo lens \(lens.title)")
                .accessibilityAddTraits(camera.photoLens == lens ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.10), in: Capsule())
    }

    private var manualButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) {
                camera.setManualControlsEnabled(!camera.manualControlsEnabled)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "slider.vertical.3")
                    .font(.system(size: 13, weight: .bold))
                Text(camera.manualControlsEnabled ? "MANUAL ON" : "MANUAL")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .foregroundStyle(camera.manualControlsEnabled ? .white : .white.opacity(0.78))
            .frame(minHeight: 40)
            .padding(.horizontal, 12)
            .background(
                camera.manualControlsEnabled ? CamProTheme.accent : Color.white.opacity(0.10),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .disabled(camera.captureMode != .photo)
        .opacity(camera.captureMode == .photo ? 1 : 0.48)
        .accessibilityLabel("Manual focus and exposure controls")
    }

    private var zoomButton: some View {
        Button {
            advanceZoom()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 12, weight: .bold))
                Text("\(camera.zoomFactor, specifier: "%.0f")×")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(minWidth: 62, minHeight: 40)
            .padding(.horizontal, 4)
            .background(Color.white.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Zoom \(camera.zoomFactor, specifier: "%.0f") times; tap to change")
    }

    private func advanceZoom() {
        let currentIndex = zoomPresets.firstIndex { abs($0 - camera.zoomFactor) < 0.08 } ?? 0
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
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
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

    private var compactManualPanel: some View {
        VStack(spacing: 8) {
            HStack {
                Label("MANUAL", systemImage: "slider.vertical.3")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(.white)

                Spacer()

                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        camera.setManualControlsEnabled(false)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close manual controls")
            }

            CompactSliderRow(
                title: "FOCUS",
                value: Binding(
                    get: { Double(camera.manualFocusPosition) },
                    set: { camera.setManualFocusPosition(Float($0)) }
                ),
                range: 0...1
            )

            CompactSliderRow(
                title: "EV",
                value: Binding(
                    get: { Double(camera.exposureBias) },
                    set: { camera.setExposureBias(Float($0)) }
                ),
                range: -2...2
            )
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.32), radius: 18, y: 8)
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

private struct CompactSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.72))
                .frame(width: 48, alignment: .leading)

            Slider(value: $value, in: range)
                .tint(CamProTheme.accent)

            Text(displayValue)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.66))
                .frame(width: 34, alignment: .trailing)
        }
        .frame(minHeight: 30)
    }

    private var displayValue: String {
        if range.lowerBound == 0 && range.upperBound == 1 {
            return String(format: "%.0f%%", value * 100)
        }
        return String(format: "%+.1f", value)
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
