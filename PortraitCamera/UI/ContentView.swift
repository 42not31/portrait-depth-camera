import AVFoundation
import SwiftUI
import UIKit

// MYVISION implementation: clear rectangular viewfinder; fixed lower-left zoom,
// centered shutter, lower-right Menu, and a stable thumbnail/mode/switch row.
// Liquid Glass is limited to controls and the upward-expanding contextual menu.

struct ContentView: View {
    @ObservedObject var camera: CameraModel
    @ObservedObject var settings: CamProSettings

    @State private var focusPoint: CGPoint?
    @State private var focusAnimationID = UUID()
    @State private var showSettings = false
    @State private var isMenuOpen = false

    private let glassBorder = Color.primary.opacity(0.18)
    private let lowerControlReservedHeight: CGFloat = 224
    private let lowerControlFamilyOffset: CGFloat = 8

    private var zoomPresets: [CGFloat] {
        camera.captureMode == .photo ? [1.0, 2.0, 3.0, 4.0, 5.0] : [1.0, 2.0]
    }

    private var previewAspectRatio: CGFloat {
        guard camera.captureMode == .photo else { return 3.0 / 4.0 }
        switch camera.photoAspectRatio {
        case .fourThree: return 3.0 / 4.0
        case .sixteenNine: return 9.0 / 16.0
        }
    }

    private var usesTallPhotoPreview: Bool {
        camera.captureMode == .photo && camera.photoAspectRatio == .sixteenNine
    }

    private var previewLayoutKey: String {
        "\(camera.captureMode.rawValue)-\(camera.photoAspectRatio.rawValue)"
    }

    private var visibleMenuItems: [CameraMenuItem] {
        camera.captureMode == .photo
            ? [.focus, .lens, .aspectRatio, .flash, .exposure, .settings]
            : [.depth, .flash, .exposure, .settings]
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            previewSurface
        }
        .overlay(alignment: .bottom) {
            bottomControlSystem
                .offset(y: lowerControlFamilyOffset)
                .safeAreaPadding(.bottom, 4)
                .zIndex(2)
        }
        .overlay {
            if camera.permissionDenied {
                permissionCard
            }
        }
        .task { camera.start() }
        .onDisappear { camera.stop() }
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: settings)
        }
    }

    private var previewSurface: some View {
        GeometryReader { proxy in
            let cameraCanvasHeight = max(
                proxy.size.height - (lowerControlReservedHeight - lowerControlFamilyOffset),
                1
            )
            let previewHeight = usesTallPhotoPreview
                ? cameraCanvasHeight
                : min(cameraCanvasHeight, proxy.size.width / previewAspectRatio)

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
                .frame(width: proxy.size.width, height: previewHeight)
                .clipShape(Rectangle())
                .overlay {
                    if let focusPoint, !camera.manualControlsEnabled {
                        FocusReticle()
                            .id(focusAnimationID)
                            .position(focusPoint)
                    }
                }
                .frame(
                    width: proxy.size.width,
                    height: cameraCanvasHeight,
                    alignment: usesTallPhotoPreview ? .top : .center
                )
                .animation(.easeInOut(duration: 0.24), value: previewLayoutKey)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
        }
    }

    private var bottomControlSystem: some View {
        VStack(spacing: 0) {
            lowerControlRow
            bottomNavigationRow
                .background(.thickMaterial)
        }
        .frame(maxWidth: .infinity)
    }

    private var lowerControlRow: some View {
        ZStack(alignment: .bottomTrailing) {
            HStack(spacing: 0) {
                zoomButton
                    .frame(maxWidth: .infinity, alignment: .leading)

                shutterButton
                    .frame(maxWidth: .infinity)

                menuButton
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 22)
            .frame(height: 146)

            if isMenuOpen {
                controlMenu
                    .padding(.trailing, 18)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 146)
        .animation(.easeOut(duration: 0.2), value: isMenuOpen)
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
        .padding(.horizontal, 22)
        .frame(height: 76)
    }

    private var zoomButton: some View {
        Button(action: advanceZoom) {
            Text("\(camera.zoomFactor, specifier: "%.0f")×")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .frame(width: 52, height: 52)
                .background(.ultraThinMaterial, in: Circle())
                .overlay { Circle().stroke(glassBorder, lineWidth: 0.8) }
        }
        .buttonStyle(CameraPressStyle())
        .accessibilityLabel("Zoom \(camera.zoomFactor, specifier: "%.0f") times; tap to change")
    }

    private var shutterButton: some View {
        Button { camera.capturePhoto() } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 88, height: 88)
                    .overlay { Circle().stroke(glassBorder, lineWidth: 1) }
                Circle()
                    .fill(camera.isCapturing ? Color.primary.opacity(0.34) : .white)
                    .frame(width: 72, height: 72)
                    .overlay { Circle().stroke(Color.black.opacity(0.16), lineWidth: 1) }
            }
        }
        .buttonStyle(CameraPressStyle())
        .disabled(camera.isCapturing || !camera.isConfigured || !camera.isRunning)
        .opacity(camera.isCapturing || !camera.isConfigured || !camera.isRunning ? 0.58 : 1)
        .accessibilityLabel("Shutter")
    }

    private var menuButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) {
                isMenuOpen.toggle()
            }
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 54, height: 54)
                .background(.ultraThinMaterial, in: Circle())
                .overlay { Circle().stroke(glassBorder, lineWidth: 0.8) }
        }
        .buttonStyle(CameraPressStyle())
        .accessibilityLabel(isMenuOpen ? "Close camera menu" : "Open camera menu")
    }

    private var controlMenu: some View {
        VStack(spacing: 4) {
            ForEach(visibleMenuItems) { item in
                Button {
                    performMenuAction(item)
                } label: {
                    CameraMenuRow(
                        item: item,
                        isActive: isMenuItemActive(item),
                        isUnavailable: item == .depth
                    )
                }
                .buttonStyle(CameraPressStyle())
                .disabled(item == .depth)
                .accessibilityLabel(item.accessibilityLabel)
            }
        }
        .padding(6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .stroke(glassBorder, lineWidth: 0.8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Camera menu")
    }

    private func isMenuItemActive(_ item: CameraMenuItem) -> Bool {
        switch item {
        case .focus, .exposure:
            return camera.manualControlsEnabled
        case .lens:
            return camera.photoLens == .ultraWide
        case .aspectRatio:
            return camera.photoAspectRatio != .fourThree
        case .flash:
            return camera.photoFlashMode != .off
        case .depth, .settings:
            return false
        }
    }

    private func performMenuAction(_ item: CameraMenuItem) {
        switch item {
        case .focus:
            camera.setManualControlsEnabled(!camera.manualControlsEnabled)
        case .lens:
            let nextLens: PhotoLens = camera.photoLens == .wide ? .ultraWide : .wide
            camera.setPhotoLens(nextLens)
        case .aspectRatio:
            cycleAspectRatio()
        case .flash:
            cycleFlashMode()
        case .exposure:
            camera.setManualControlsEnabled(!camera.manualControlsEnabled)
        case .settings:
            isMenuOpen = false
            showSettings = true
            return
        case .depth:
            return
        }

        withAnimation(.easeOut(duration: 0.18)) {
            isMenuOpen = false
        }
    }

    private func advanceZoom() {
        let currentIndex = zoomPresets.firstIndex { abs($0 - camera.zoomFactor) < 0.08 } ?? 0
        let nextIndex = (currentIndex + 1) % zoomPresets.count
        camera.setZoomFactor(zoomPresets[nextIndex])
    }

    private func cycleAspectRatio() {
        let allRatios = PhotoAspectRatio.allCases
        let currentIndex = allRatios.firstIndex(of: camera.photoAspectRatio) ?? 0
        let nextIndex = (currentIndex + 1) % allRatios.count
        camera.setPhotoAspectRatio(allRatios[nextIndex])
    }

    private func cycleFlashMode() {
        let allModes = PhotoFlashMode.allCases
        let currentIndex = allModes.firstIndex(of: camera.photoFlashMode) ?? 0
        let nextIndex = (currentIndex + 1) % allModes.count
        camera.setPhotoFlashMode(allModes[nextIndex])
    }

    private var latestPhotoButton: some View {
        Button { camera.openLatestPhotoInPhotos() } label: {
            Group {
                if let image = camera.latestPhotoImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.clear
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(Circle())
            .background(.ultraThinMaterial, in: Circle())
            .overlay { Circle().stroke(glassBorder, lineWidth: 0.8) }
        }
        .buttonStyle(CameraPressStyle())
        .disabled(camera.latestPhotoImage == nil)
        .opacity(camera.latestPhotoImage == nil ? 0.78 : 1)
        .accessibilityLabel(camera.latestPhotoImage == nil ? "No photo captured yet" : "Open latest photo in Photos")
    }

    private var modePicker: some View {
        HStack(spacing: 0) {
            modeButton(.photo)
            modeButton(.portrait)
        }
        .padding(3)
        .frame(width: 194, height: 48)
        .background(.thinMaterial, in: Capsule())
        .overlay { Capsule().stroke(glassBorder, lineWidth: 0.8) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Capture mode")
    }

    private func modeButton(_ mode: CaptureMode) -> some View {
        Button {
            camera.setCaptureMode(mode)
            focusPoint = nil
            isMenuOpen = false
        } label: {
            Text(mode.title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(camera.captureMode == mode ? .primary : Color.primary.opacity(0.55))
                .frame(maxWidth: .infinity, minHeight: 42)
                .background {
                    if camera.captureMode == mode {
                        Capsule().fill(Color.white.opacity(0.54))
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(camera.captureMode == mode ? .isSelected : [])
    }

    private var rotateCameraButton: some View {
        Button {
            // The reference icon is retained, but the protected pipeline remains rear-only.
        } label: {
            Image(systemName: "camera.rotate")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(.primary)
                .frame(width: 56, height: 56)
                .background(.ultraThinMaterial, in: Circle())
                .overlay { Circle().stroke(glassBorder, lineWidth: 0.8) }
        }
        .buttonStyle(CameraPressStyle())
        .accessibilityLabel("Selfie camera unavailable in this build")
    }

    private var permissionCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.fill")
                .font(.system(size: 28))
            Text("Camera access is required")
                .font(.system(size: 19, weight: .bold, design: .rounded))
            Text("Enable camera access in Settings to capture photos.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.primary)
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(28)
    }
}

private enum CameraMenuItem: String, CaseIterable, Identifiable {
    case focus
    case lens
    case aspectRatio
    case flash
    case exposure
    case settings
    case depth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focus: return "Focus"
        case .lens: return "Lens"
        case .aspectRatio: return "Aspect Ratio"
        case .flash: return "Flash"
        case .exposure: return "Exposure"
        case .settings: return "Settings"
        case .depth: return "Depth"
        }
    }

    var systemImage: String {
        switch self {
        case .focus: return "scope"
        case .lens: return "circle.circle"
        case .aspectRatio: return "viewfinder"
        case .flash: return "bolt.fill"
        case .exposure: return "sun.max"
        case .settings: return "gearshape"
        case .depth: return "f.cursive"
        }
    }

    var accessibilityLabel: String {
        self == .depth ? "Depth adjustment is unavailable in this build" : title
    }
}

private struct CameraMenuRow: View {
    let item: CameraMenuItem
    let isActive: Bool
    let isUnavailable: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: item.systemImage)
                .font(.system(size: 22, weight: .regular))
                .frame(width: 30)
            Text(item.title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Spacer(minLength: 0)
        }
        .foregroundStyle(isUnavailable ? Color.primary.opacity(0.42) : .primary)
        .padding(.horizontal, 15)
        .frame(width: 166, height: 52)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isActive ? Color.primary.opacity(0.10) : Color.clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.18), lineWidth: 0.7)
        }
    }
}

private struct CameraPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
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
                withAnimation(.easeOut(duration: 0.14)) { visible = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    withAnimation(.easeOut(duration: 0.2)) { visible = false }
                }
            }
    }
}
