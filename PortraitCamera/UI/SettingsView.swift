import SwiftUI

// MYVISION implementation: retain the stored preferences while using the same
// neutral, material-led appearance as the camera’s anchored control menu.
struct SettingsView: View {
    @ObservedObject var settings: CamProSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Depth readiness indicator", isOn: $settings.showDepthIndicator)
                    Toggle("Capture haptics", isOn: $settings.hapticsEnabled)
                    Toggle("Mirror front camera", isOn: $settings.mirrorFrontCamera)
                } header: {
                    Text("CAPTURE")
                } footer: {
                    Text("Portrait capture remains native and Photos-editable. These preferences are stored on this device.")
                }

                Section {
                    HStack {
                        Text("App")
                        Spacer()
                        Text("CamPro")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Camera")
                        Spacer()
                        Text("iPhone 13 optimized")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("ABOUT")
                }
            }
            .scrollContentBackground(.hidden)
            .background(.thinMaterial)
            .foregroundStyle(.primary)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(CamProTheme.accent)
                }
            }
        }
        .tint(CamProTheme.accent)
        .preferredColorScheme(.light)
    }
}
