import AVFoundation
// Build 47 camera settings: Photo aspect choices are intentionally limited to
// the user-approved 4:3 and portrait-labelled 9:16 capture presentations.
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
        case .sixteenNine: return 9.0 / 16.0
        }
    }
}

enum CamProTheme {
    static let accent = Color.primary
    static let accentMuted = Color.primary.opacity(0.14)
}

final class CamProSettings: ObservableObject {
    @Published var showDepthIndicator: Bool {
        didSet { defaults.set(showDepthIndicator, forKey: Keys.showDepthIndicator) }
    }
    @Published var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Keys.hapticsEnabled) }
    }
    @Published var mirrorFrontCamera: Bool {
        didSet { defaults.set(mirrorFrontCamera, forKey: Keys.mirrorFrontCamera) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.showDepthIndicator = defaults.object(forKey: Keys.showDepthIndicator) as? Bool ?? true
        self.hapticsEnabled = defaults.object(forKey: Keys.hapticsEnabled) as? Bool ?? true
        self.mirrorFrontCamera = defaults.object(forKey: Keys.mirrorFrontCamera) as? Bool ?? true
    }

    private enum Keys {
        static let showDepthIndicator = "campro.showDepthIndicator"
        static let hapticsEnabled = "campro.hapticsEnabled"
        static let mirrorFrontCamera = "campro.mirrorFrontCamera"
    }
}
