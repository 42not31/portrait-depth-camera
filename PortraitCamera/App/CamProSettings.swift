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

enum CameraPosition: String, Identifiable {
    case back
    case front

    var id: String { rawValue }
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
    case square

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fourThree: return "4:3"
        case .sixteenNine: return "16:9"
        case .square: return "1:1"
        }
    }

    var value: CGFloat {
        switch self {
        case .fourThree: return 4.0 / 3.0
        case .sixteenNine: return 16.0 / 9.0
        case .square: return 1.0
        }
    }
}

enum PhotoStyle: String, CaseIterable, Identifiable {
    case standard
    case richContrast
    case vibrant
    case warm
    case dramatic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "Standard"
        case .richContrast: return "Rich Contrast"
        case .vibrant: return "Vibrant"
        case .warm: return "Warm"
        case .dramatic: return "Dramatic"
        }
    }

    var shortTitle: String {
        switch self {
        case .standard: return "STD"
        case .richContrast: return "RICH"
        case .vibrant: return "VIB"
        case .warm: return "WARM"
        case .dramatic: return "DRAM"
        }
    }
}

enum CamProTheme {
    static let accent = Color(red: 0.18, green: 0.48, blue: 0.98)
    static let accentMuted = Color(red: 0.18, green: 0.48, blue: 0.98).opacity(0.22)
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
    @Published var hardwareCaptureActionsEnabled: Bool {
        didSet { defaults.set(hardwareCaptureActionsEnabled, forKey: Keys.hardwareCaptureActionsEnabled) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.showDepthIndicator = defaults.object(forKey: Keys.showDepthIndicator) as? Bool ?? true
        self.hapticsEnabled = defaults.object(forKey: Keys.hapticsEnabled) as? Bool ?? true
        self.mirrorFrontCamera = defaults.object(forKey: Keys.mirrorFrontCamera) as? Bool ?? true
        self.hardwareCaptureActionsEnabled = defaults.object(forKey: Keys.hardwareCaptureActionsEnabled) as? Bool ?? true
    }

    private enum Keys {
        static let showDepthIndicator = "campro.showDepthIndicator"
        static let hapticsEnabled = "campro.hapticsEnabled"
        static let mirrorFrontCamera = "campro.mirrorFrontCamera"
        static let hardwareCaptureActionsEnabled = "campro.hardwareCaptureActionsEnabled"
    }
}
