import SwiftUI

@main
struct PortraitCameraApp: App {
    @StateObject private var camera = CameraModel()
    @StateObject private var settings = CamProSettings()

    var body: some Scene {
        WindowGroup {
            ContentView(camera: camera, settings: settings)
                .preferredColorScheme(.dark)
        }
    }
}
