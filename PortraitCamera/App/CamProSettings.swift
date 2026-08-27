import AVFoundation
import SwiftUI

enum CaptureMode: String, CaseIterable, Identifiable {
    case photo
    case portrait

    var id: String { rawValue }

    var title: String {
        switch self {
        case .photo: return "PHOTO"
        case .portrait: return "PORTRAIT"
        }
    }
}

enum PhotoLens: String, CaseIterable, Identifiable {
    case ultraWide
    case wide

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ultraWide: return "0.5×"
        case .wide: return "1×"
        }
    }

    var deviceType: AVCaptureDevice.DeviceType {
        switch self {
        case .ultraWide: return .builtInUltraWideCamera
        case .wide: return .builtInWideAngleCamera
        }
    }
}

enum PhotoFlashMode: String, CaseIterable, Identifiable {
    case off
    case auto
    case on

    var id: String { rawValue }

    var title: String { rawValue.uppercased() }

    var captureMode: AVCaptureDevice.FlashMode {
        switch self {
        case .off: return .off
        case .auto: return .auto
        case .on: return .on
        }
    }
}

enum PhotoAspectRatio: String, CaseIterable, Identifiable {
    case fourThree
    case sixteenNine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fourThree: return "4:3"
        case .sixteenNine: return "9:16"
        }
    }

    var value: CGFloat {
        switch self {
        case .fourThree: return 4.0 / 3.0
        // The sensor image is landscape before its EXIF orientation is applied.
        // A 16:9 raw crop displays upright as 9:16 for portrait-oriented captures.
        case .sixteenNine: return 16.0 / 9.0
        }
    }
}

enum MenuDisplayStyle: String, CaseIterable, Identifiable {
    case iconsAndText
    case iconsOnly

    var id: String { rawValue }
    var title: String {
        switch self {
        case .iconsAndText: return "Icons + Name"
        case .iconsOnly: return "Icons Only"
        }
    }
}

enum CamProTheme {
    static let accent = Color.yellow
    static let accentMuted = Color.yellow.opacity(0.18)
}

final class CamProSettings: ObservableObject {
    @Published var mirrorFrontCamera: Bool {
        didSet { defaults.set(mirrorFrontCamera, forKey: Keys.mirrorFrontCamera) }
    }
    @Published var showGrid: Bool {
        didSet { defaults.set(showGrid, forKey: Keys.showGrid) }
    }
    @Published var showFocusReticle: Bool {
        didSet { defaults.set(showFocusReticle, forKey: Keys.showFocusReticle) }
    }
    @Published var keepScreenAwake: Bool {
        didSet { defaults.set(keepScreenAwake, forKey: Keys.keepScreenAwake) }
    }
    @Published var frontPhotoWideByDefault: Bool {
        didSet { defaults.set(frontPhotoWideByDefault, forKey: Keys.frontPhotoWideByDefault) }
    }
    @Published var menuDisplayStyle: MenuDisplayStyle {
        didSet { defaults.set(menuDisplayStyle.rawValue, forKey: Keys.menuDisplayStyle) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.mirrorFrontCamera = defaults.object(forKey: Keys.mirrorFrontCamera) as? Bool ?? true
        self.showGrid = defaults.object(forKey: Keys.showGrid) as? Bool ?? false
        self.showFocusReticle = defaults.object(forKey: Keys.showFocusReticle) as? Bool ?? true
        self.keepScreenAwake = defaults.object(forKey: Keys.keepScreenAwake) as? Bool ?? true
        self.frontPhotoWideByDefault = defaults.object(forKey: Keys.frontPhotoWideByDefault) as? Bool ?? true
        self.menuDisplayStyle = MenuDisplayStyle(
            rawValue: defaults.string(forKey: Keys.menuDisplayStyle) ?? MenuDisplayStyle.iconsAndText.rawValue
        ) ?? .iconsAndText
    }

    private enum Keys {
        static let mirrorFrontCamera = "campro.mirrorFrontCamera"
        static let showGrid = "campro.showGrid"
        static let showFocusReticle = "campro.showFocusReticle"
        static let keepScreenAwake = "campro.keepScreenAwake"
        static let frontPhotoWideByDefault = "campro.frontPhotoWideByDefault"
        static let menuDisplayStyle = "campro.menuDisplayStyle"
    }
}
