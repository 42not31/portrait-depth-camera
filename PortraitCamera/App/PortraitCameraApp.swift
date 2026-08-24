import SwiftUI

@main
struct PortraitCameraApp: App {
    @StateObject private var camera = CameraModel()

    var body: some Scene {
        WindowGroup {
            ContentView(camera: camera)
                .preferredColorScheme(.dark)
        }
    }
}
