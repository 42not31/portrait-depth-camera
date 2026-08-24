import SwiftUI

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
            .background(Color.black)
            .foregroundStyle(.white)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
        .tint(.white)
        .preferredColorScheme(.dark)
    }
}
