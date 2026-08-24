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
