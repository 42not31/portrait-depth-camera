import AVFoundation
import SwiftUI
import UIKit

// Build 52 camera surface: the complete Build 47 MYVISION screen and Build 51 geometry
// remain authoritative. The live preview retains the marked 4:3 / 9:16 placement, compact
// capture row, and separate final navigation row while this screen exposes front-camera state.

struct ContentView: View {
    @ObservedObject var camera: CameraModel
    @ObservedObject var settings: CamProSettings

    @State private var focusPoint: CGPoint?
    @State private var focusAnimationID = UUID()
    @State private var showSettings = false
    @State private var isMenuOpen = false
    @State private var activeMenuItem: CameraMenuItem?

    private let previewVerticalOffset: CGFloat = 8
    private let captureControlRowOffset: CGFloat = -8
    private let navigationRowOffset: CGFloat = 8
    private let previewLowerBoundaryOffset: CGFloat = 16
    @State private var displayedCaptureMode: CaptureMode = .portrait
    @Namespace private var modeSelectionNamespace

    private var zoomPresets: [CGFloat] {
        if camera.isUsingFrontCamera {
            return camera.captureMode == .photo ? [1.0, 2.0] : [1.0, 1.5]
        }
        return camera.captureMode == .photo ? [1.0, 2.0, 3.0, 4.0, 5.0] : [1.0, 2.0]
    }

    private func formattedZoom(_ rawFactor: CGFloat) -> String {
        let displayedZoom = (!camera.isUsingFrontCamera && camera.captureMode == .photo && camera.photoLens == .ultraWide)
            ? rawFactor * 0.5
            : rawFactor
        let isWholeNumber = abs(displayedZoom.rounded() - displayedZoom) < 0.01
        return isWholeNumber
            ? String(format: "%.0f×", displayedZoom)
            : String(format: "%.1f×", displayedZoom)
    }

    private var zoomTitle: String {
        formattedZoom(camera.zoomFactor)
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
        if camera.isUsingFrontCamera {
            return camera.captureMode == .photo
                ? [.aspectRatio, .flash, .exposure, .settings]
                : [.flash, .exposure, .settings]
        }
        guard camera.captureMode == .photo else {
            return [.flash, .exposure, .settings]
        }
        var items: [CameraMenuItem] = []
        if isFocusSupported {
            items.append(.focus)
        }
        items += [.lens, .aspectRatio, .flash, .exposure, .settings]
        return items
    }

    private var isFocusSupported: Bool {
        !camera.isUsingFrontCamera && camera.captureMode == .photo && camera.photoLens == .wide
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            previewSurface
                .zIndex(0)

            if isMenuOpen {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { dismissMenu() }
                    .zIndex(1)
            }
        }
        .overlay(alignment: .bottom) {
            bottomControlSystem
                .safeAreaPadding(.bottom, 2)
                .zIndex(2)
        }
        .overlay {
            if camera.permissionDenied {
                permissionCard
            }
        }
        .task {
            camera.setFrontCameraMirroring(settings.mirrorFrontCamera)
            camera.start()
        }
        .onChange(of: settings.mirrorFrontCamera) { enabled in
            camera.setFrontCameraMirroring(enabled)
        }
        .onChange(of: camera.captureMode) { mode in
            withAnimation(.snappy(duration: 0.28, extraBounce: 0)) {
                displayedCaptureMode = mode
            }
        }
        .onAppear {
            displayedCaptureMode = camera.captureMode
            UIApplication.shared.isIdleTimerDisabled = settings.keepScreenAwake
        }
        .onChange(of: settings.keepScreenAwake) { enabled in
            UIApplication.shared.isIdleTimerDisabled = enabled
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            camera.stop()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: settings)
        }
    }

    private var previewSurface: some View {
        GeometryReader { proxy in
            // The final marked Apple comparison keeps each ratio-specific canvas intact,
            // then lowers the complete live preview slightly as one visual frame.
            let bottomSafeArea = max(proxy.safeAreaInsets.bottom, 20)
            let immediateCaptureRowHeight: CGFloat = 112
            let finalNavigationHeight: CGFloat = 58 + bottomSafeArea
            let fourThreeCanvasHeight = max(
                proxy.size.height - immediateCaptureRowHeight - finalNavigationHeight
                    + previewLowerBoundaryOffset,
                1
            )
            let tallCanvasHeight = max(
                proxy.size.height - finalNavigationHeight + previewLowerBoundaryOffset,
                1
            )
            let availableHeight = usesTallPhotoPreview ? tallCanvasHeight : fourThreeCanvasHeight
            let previewHeight = min(availableHeight, proxy.size.width / previewAspectRatio)

            ZStack(alignment: .top) {
                Color.black

                CameraPreview(
                    session: camera.session,
                    zoomFactor: camera.zoomFactor,
                    deviceZoomFactor: camera.deviceZoomFactor,
                    videoOrientation: .portrait,
                    isMirrored: camera.isUsingFrontCamera && settings.mirrorFrontCamera,
                    onTap: { viewPoint, devicePoint in
                        guard !camera.manualControlsEnabled else { return }
                        camera.focus(at: devicePoint)
                        focusPoint = viewPoint
                        focusAnimationID = UUID()
                    }
                )
                .frame(width: proxy.size.width, height: previewHeight)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay {
                    if settings.showGrid {
                        GridOverlay().allowsHitTesting(false)
                    }
                    if let focusPoint, !camera.manualControlsEnabled && settings.showFocusReticle {
                        FocusReticle()
                            .id(focusAnimationID)
                            .position(focusPoint)
                    }
                        }
                .frame(
                    width: proxy.size.width,
                    height: availableHeight,
                    alignment: .bottom
                )
                .offset(y: previewVerticalOffset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .animation(.easeInOut(duration: 0.25), value: previewLayoutKey)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
        }
    }

    private var bottomControlSystem: some View {
        VStack(spacing: 0) {
            lowerControlRow
                .offset(y: captureControlRowOffset)
                .zIndex(1)
            bottomNavigationRow
                .offset(y: navigationRowOffset)
                .zIndex(0)
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
            .padding(.horizontal, 20)
            .frame(height: 112)

        }
        .frame(maxWidth: .infinity, minHeight: 112)
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
        .padding(.horizontal, 20)
        .frame(height: 58)
    }

    private var zoomButton: some View {
        Button(action: openZoomControl) {
            Text(zoomTitle)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white)
                .frame(width: 48, height: 48)
                .camProGlass(Circle())
        }
        .buttonStyle(CameraPressStyle())
        .overlay(alignment: .bottomLeading) {
            if activeMenuItem == .zoom {
                zoomControlDetail
                    .offset(y: -62)
                    .transition(.scale(scale: 0.95, anchor: .bottomLeading).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.24, extraBounce: 0), value: activeMenuItem)
        .accessibilityLabel("Zoom \(zoomTitle); tap to change")
    }

    private var shutterButton: some View {
        Button { camera.capturePhoto() } label: {
            ZStack {
                Circle()
                    .fill(.clear)
                    .frame(width: 72, height: 72)
                    .camProGlass(Circle())
                Circle()
                    .fill(camera.isCapturing ? Color.white.opacity(0.35) : .white)
                    .frame(width: 56, height: 56)
                    .overlay { Circle().stroke(Color.black.opacity(0.18), lineWidth: 1) }
            }
        }
        .buttonStyle(CameraPressStyle())
        .disabled(camera.isCapturing || !camera.isConfigured || !camera.isRunning)
        .opacity(camera.isCapturing || !camera.isConfigured || !camera.isRunning ? 0.58 : 1)
        .accessibilityLabel("Shutter")
    }

    private var menuButton: some View {
        Button {
            withAnimation(.snappy(duration: 0.24, extraBounce: 0)) {
                if isMenuOpen {
                    activeMenuItem = nil
                    isMenuOpen = false
                } else {
                    activeMenuItem = nil
                    isMenuOpen = true
                }
            }
        } label: {
            Image(systemName: isMenuOpen ? "xmark" : "line.3.horizontal")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 50, height: 50)
                .contentShape(Circle())
                .camProGlass(Circle())
        }
        .buttonStyle(CameraPressStyle())
        .overlay(alignment: .bottomTrailing) {
            if isMenuOpen {
                controlMenu
                    .offset(y: -62)
                    .transition(.scale(scale: 0.94, anchor: .bottomTrailing).combined(with: .opacity))
            } else if activeMenuItem != nil && activeMenuItem != .zoom {
                activeControlDetail
                    .offset(y: -62)
                    .transition(.scale(scale: 0.95, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.24, extraBounce: 0), value: isMenuOpen)
        .animation(.snappy(duration: 0.24, extraBounce: 0), value: activeMenuItem)
        .accessibilityLabel(isMenuOpen ? "Close camera menu" : "Open camera menu")
    }

    private var controlMenu: some View {
        VStack(spacing: 8) {
            if settings.menuDisplayStyle == .iconsAndText {
                HStack(spacing: 8) {
                    Image(systemName: camera.captureMode == .photo ? "camera" : "camera.aperture")
                        .font(.system(size: 13, weight: .semibold))
                    Text(camera.captureMode == .photo ? "PHOTO" : "PORTRAIT")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.2)
                    Spacer(minLength: 0)
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 10)
                .padding(.bottom, 2)
            }

            ForEach(visibleMenuItems) { item in
                Button { performMenuAction(item) } label: {
                    CameraMenuRow(
                        item: item,
                        valueText: menuValueText(item),
                        isSelected: activeMenuItem == item,
                        displayStyle: settings.menuDisplayStyle
                    )
                }
                .buttonStyle(CameraPressStyle())
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(Rectangle())
                .accessibilityLabel(item.accessibilityLabel)
            }
        }
        .padding(settings.menuDisplayStyle == .iconsOnly ? 10 : 12)
        .frame(width: settings.menuDisplayStyle == .iconsOnly ? 78 : 286)
        .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .camProGlass(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.34), radius: 24, y: 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Camera menu")
    }

    @ViewBuilder
    private var activeControlDetail: some View {
        if let item = activeMenuItem {
            switch item {
            case .focus:
                focusControlDetail
            case .zoom:
                zoomControlDetail
            case .lens:
                lensControlDetail
            case .aspectRatio:
                aspectControlDetail
            case .flash:
                flashControlDetail
            case .exposure:
                exposureControlDetail
            case .settings:
                EmptyView()
            }
        }
    }

    private var focusControlDetail: some View {
        CameraControlDetail(title: "Focus", onClose: { closeActiveControl() }) {
            if isFocusSupported {
                HStack(spacing: 10) {
                    stateButton(title: camera.manualControlsEnabled ? "LOCK" : "AUTO") {
                        camera.setManualControlsEnabled(!camera.manualControlsEnabled)
                    }
                    Spacer(minLength: 0)
                    Text("\(Int(camera.manualFocusPosition * 100))")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                Slider(
                    value: Binding(
                        get: { Double(camera.manualFocusPosition) },
                        set: { camera.setManualFocusPosition(Float($0)) }
                    ),
                    in: 0...1
                )
                .tint(Color.primary)
                .disabled(!camera.manualControlsEnabled)
                .opacity(camera.manualControlsEnabled ? 1 : 0.45)
            } else {
                Text("Focus lock is available with the 1× rear lens.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.62))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var zoomControlDetail: some View {
        let bounds = zoomPresets
        let minZoom = bounds.min() ?? 1.0
        let maxZoom = bounds.max() ?? 1.0
        let isUltraWide = !camera.isUsingFrontCamera && camera.captureMode == .photo && camera.photoLens == .ultraWide

        return CameraControlDetail(title: isUltraWide ? "Ultra Wide Zoom" : "Zoom", onClose: { closeActiveControl() }) {
            HStack(spacing: 9) {
                Text(formattedZoom(minZoom))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Slider(
                    value: Binding(
                        get: { Double(min(max(camera.zoomFactor, minZoom), maxZoom)) },
                        set: { camera.setZoomFactor(CGFloat($0)) }
                    ),
                    in: minZoom...maxZoom
                )
                .tint(Color.primary)
                Text(zoomTitle)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .frame(width: 34, alignment: .trailing)
            }
            if isUltraWide {
                Text("Manual crop for the rear Ultra Wide lens")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.62))
            }
        }
    }

    private var lensControlDetail: some View {
        CameraControlDetail(title: "Lens", onClose: { closeActiveControl() }) {
            HStack(spacing: 7) {
                ForEach(PhotoLens.allCases) { lens in
                    choiceButton(lens.title, isSelected: camera.photoLens == lens) {
                        camera.setPhotoLens(lens)
                        activeMenuItem = nil
                    }
                }
            }
        }
    }

    private var aspectControlDetail: some View {
        CameraControlDetail(title: "Aspect Ratio", onClose: { closeActiveControl() }) {
            HStack(spacing: 7) {
                ForEach(PhotoAspectRatio.allCases) { ratio in
                    choiceButton(ratio.title, isSelected: camera.photoAspectRatio == ratio) {
                        withAnimation(.snappy(duration: 0.24, extraBounce: 0)) {
                            camera.setPhotoAspectRatio(ratio)
                        }
                    }
                }
            }
        }
    }

    private var flashControlDetail: some View {
        CameraControlDetail(title: "Flash", onClose: { closeActiveControl() }) {
            HStack(spacing: 7) {
                ForEach(PhotoFlashMode.allCases) { flashMode in
                    choiceButton(flashMode.title, isSelected: camera.photoFlashMode == flashMode) {
                        camera.setPhotoFlashMode(flashMode)
                        activeMenuItem = nil
                    }
                }
            }
        }
    }

    private var exposureControlDetail: some View {
        CameraControlDetail(title: "Exposure", onClose: { closeActiveControl() }) {
            HStack(spacing: 10) {
                stateButton(title: camera.manualControlsEnabled ? "LOCK" : "AUTO") {
                    camera.setManualControlsEnabled(!camera.manualControlsEnabled)
                }
                Spacer(minLength: 0)
                Text(String(format: "%+.1f", camera.exposureBias))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            Slider(
                value: Binding(
                    get: { Double(camera.exposureBias) },
                    set: { camera.setExposureBias(Float($0)) }
                ),
                in: -2...2
            )
            .tint(Color.primary)
            .disabled(!camera.manualControlsEnabled)
            .opacity(camera.manualControlsEnabled ? 1 : 0.45)
        }
    }

    private func stateButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(0.7)
                .frame(minWidth: 58, minHeight: 30)
                .camProGlass(Capsule())
        }
        .buttonStyle(CameraPressStyle())
    }

    private func choiceButton(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(title)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                }
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .frame(maxWidth: .infinity, minHeight: 39)
            .foregroundStyle(Color.primary)
            .background {
                if isSelected {
                    CamProTheme.accent.opacity(0.28)
                } else {
                    Color.clear
                }
            }
            .camProGlass(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(CameraPressStyle())
    }

    private func menuValueText(_ item: CameraMenuItem) -> String? {
        switch item {
        case .focus:
            return isFocusSupported ? (camera.manualControlsEnabled ? "LOCK" : "AUTO") : "1× only"
        case .zoom:
            return String(format: "%.1f×", camera.zoomFactor * 0.5)
        case .lens:
            return camera.photoLens.title
        case .aspectRatio:
            return camera.photoAspectRatio.title
        case .flash:
            return camera.photoFlashMode.title
        case .exposure:
            return camera.manualControlsEnabled ? String(format: "%+.1f", camera.exposureBias) : "AUTO"
        case .settings:
            return nil
        }
    }

    private func performMenuAction(_ item: CameraMenuItem) {
        switch item {
        case .settings:
            dismissMenu()
            showSettings = true
        case .zoom:
            openZoomControl()
        case .focus:
            if isFocusSupported && !camera.manualControlsEnabled { camera.setManualControlsEnabled(true) }
            withAnimation(.easeOut(duration: 0.18)) {
                isMenuOpen = false
                activeMenuItem = item
            }
        case .exposure:
            if !camera.manualControlsEnabled { camera.setManualControlsEnabled(true) }
            withAnimation(.easeOut(duration: 0.18)) {
                isMenuOpen = false
                activeMenuItem = item
            }
        case .flash:
            let modes = PhotoFlashMode.allCases
            if let index = modes.firstIndex(of: camera.photoFlashMode) {
                camera.setPhotoFlashMode(modes[(index + 1) % modes.count])
            }
            dismissMenu()
        case .aspectRatio:
            let ratios = PhotoAspectRatio.allCases
            if let index = ratios.firstIndex(of: camera.photoAspectRatio) {
                withAnimation(.snappy(duration: 0.24, extraBounce: 0)) {
                    camera.setPhotoAspectRatio(ratios[(index + 1) % ratios.count])
                }
            }
        case .lens:
            let lenses = PhotoLens.allCases
            if let index = lenses.firstIndex(of: camera.photoLens) {
                camera.setPhotoLens(lenses[(index + 1) % lenses.count])
            }
            dismissMenu()
        }
    }

    private func closeActiveControl() {
        withAnimation(.snappy(duration: 0.24, extraBounce: 0)) {
            activeMenuItem = nil
        }
    }

    private func dismissMenu() {
        withAnimation(.snappy(duration: 0.24, extraBounce: 0)) {
            activeMenuItem = nil
            isMenuOpen = false
        }
    }

    private func openZoomControl() {
        withAnimation(.snappy(duration: 0.24, extraBounce: 0)) {
            isMenuOpen = false
            activeMenuItem = .zoom
        }
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
            .frame(width: 46, height: 46)
            .clipShape(Circle())
            .camProGlass(Circle())
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
        .frame(width: 176, height: 42)
        .background(Color.black.opacity(0.14), in: Capsule())
        .camProGlass(Capsule())
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.18), lineWidth: 0.7)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Capture mode")
    }

    private func modeButton(_ mode: CaptureMode) -> some View {
        let isSelected = displayedCaptureMode == mode
        return Button {
            withAnimation(.easeInOut(duration: 0.32)) {
                displayedCaptureMode = mode
            }
            camera.setCaptureMode(mode)
            focusPoint = nil
            dismissMenu()
        } label: {
            ZStack {
                if isSelected {
                    Capsule()
                        .fill(Color.white.opacity(0.16))
                        .overlay {
                            Capsule()
                                .stroke(Color.white.opacity(0.46), lineWidth: 0.8)
                        }
                        .camProGlass(Capsule())
                        .shadow(color: .black.opacity(0.34), radius: 8, y: 3)
                        .matchedGeometryEffect(id: "selectedCaptureMode", in: modeSelectionNamespace)
                }
                Text(mode.title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.75)
                    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.68))
                    .contentTransition(.interpolate)
            }
            .frame(maxWidth: .infinity, minHeight: 34)
            .contentShape(Capsule())
        }
        .buttonStyle(CameraPressStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var rotateCameraButton: some View {
        Button {
            camera.toggleCamera()
            focusPoint = nil
            dismissMenu()
        } label: {
            Image(systemName: "camera.rotate")
                .font(.system(size: 21, weight: .regular))
                .foregroundStyle(Color.white)
                .frame(width: 46, height: 46)
                .camProGlass(Circle())
        }
        .buttonStyle(CameraPressStyle())
        .disabled(camera.isCapturing || !camera.isConfigured || !camera.isRunning)
        .opacity(camera.isCapturing || !camera.isConfigured || !camera.isRunning ? 0.58 : 1)
        .accessibilityLabel(camera.isUsingFrontCamera ? "Switch to rear camera" : "Switch to selfie camera")
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
        .camProGlass(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(28)
    }
}

private struct GridOverlay: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let column = proxy.size.width / 3
                let row = proxy.size.height / 3
                for index in 1...2 {
                    path.move(to: CGPoint(x: column * CGFloat(index), y: 0))
                    path.addLine(to: CGPoint(x: column * CGFloat(index), y: proxy.size.height))
                    path.move(to: CGPoint(x: 0, y: row * CGFloat(index)))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: row * CGFloat(index)))
                }
            }
            .stroke(Color.white.opacity(0.3), lineWidth: 0.7)
        }
    }
}

private enum CameraMenuItem: String, CaseIterable, Identifiable, Hashable {
    case focus
    case zoom
    case lens
    case aspectRatio
    case flash
    case exposure
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focus: return "Focus"
        case .zoom: return "Zoom"
        case .lens: return "Lens"
        case .aspectRatio: return "Aspect Ratio"
        case .flash: return "Flash"
        case .exposure: return "Exposure"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .focus: return "scope"
        case .zoom: return "plus.magnifyingglass"
        case .lens: return "circle.circle"
        case .aspectRatio: return "viewfinder"
        case .flash: return "bolt.fill"
        case .exposure: return "sun.max"
        case .settings: return "gearshape"
        }
    }

    var accessibilityLabel: String { title }
}

private struct CameraMenuRow: View {
    let item: CameraMenuItem
    let valueText: String?
    let isSelected: Bool
    let displayStyle: MenuDisplayStyle

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: item.systemImage)
                .font(.system(size: 17, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 30, height: 30)
                .foregroundStyle(.primary)

            if displayStyle == .iconsAndText {
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Spacer(minLength: 0)
            }

            if displayStyle == .iconsAndText, let valueText {
                Text(valueText)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.45)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .frame(width: displayStyle == .iconsOnly ? 58 : 262, height: 52)
        .background {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(isSelected ? CamProTheme.accent.opacity(0.22) : Color.white.opacity(0.07))
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(CamProTheme.accent.opacity(0.44), lineWidth: 0.8)
            }
        }
        .camProGlass(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
    }
}

private struct CameraControlDetail<Content: View>: View {
    let title: String
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(0.72))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 27, height: 27)
                        .camProGlass(Circle())
                }
                .buttonStyle(CameraPressStyle())
                .accessibilityLabel("Return to camera menu")
            }
            content()
        }
        .padding(14)
        .frame(width: 286)
        .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .camProGlass(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.24), radius: 18, y: 8)
    }
}

private extension View {
    @ViewBuilder
    func camProGlass<S: Shape>(_ shape: S) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
                .overlay {
                    shape.stroke(Color.white.opacity(0.24), lineWidth: 0.7)
                }
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
