import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: CamProSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Mirror front camera", isOn: $settings.mirrorFrontCamera)
                    Toggle("Show focus reticle", isOn: $settings.showFocusReticle)
                    Toggle("Show framing grid", isOn: $settings.showGrid)
                    Toggle("Keep screen awake while open", isOn: $settings.keepScreenAwake)
                } header: {
                    Text("CAMERA")
                } footer: {
                    Text("These options are stored on this device. Camera processing pauses in the background to reduce heat and battery use.")
                }

                Section {
                    Picker("Menu appearance", selection: $settings.menuDisplayStyle) {
                        ForEach(MenuDisplayStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                } header: {
                    Text("MENU")
                } footer: {
                    Text("Choose between a narrow icons-only menu or a labeled menu with current values.")
                }

                Section {
                    LabeledContent("App", value: "CamPro Beta")
                    LabeledContent("Developer", value: "Abhijeet Mitra")
                    LabeledContent(
                        "Build",
                        value: (Bundle.main.object(forInfoDictionaryKey: "CAMPRO_BUILD_NAME") as? String) ?? "Build 54"
                    )
                } header: {
                    Text("ABOUT")
                }
            }
            .scrollContentBackground(.hidden)
            .background(.regularMaterial)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(CamProTheme.accent)
                }
            }
        }
        .tint(CamProTheme.accent)
    }
}
