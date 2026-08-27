import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: CamProSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Depth readiness indicator", isOn: $settings.showDepthIndicator)
                    Toggle("Mirror front camera", isOn: $settings.mirrorFrontCamera)
                    Toggle("Front Photo starts wide", isOn: $settings.frontPhotoWideByDefault)
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

                    ForEach(settings.menuOrder, id: \.self) { item in
                        HStack(spacing: 10) {
                            Image(systemName: iconName(for: item))
                                .frame(width: 22)
                            Text(title(for: item))
                            Spacer()
                            Button {
                                settings.moveMenuItem(item, by: -1)
                            } label: {
                                Image(systemName: "chevron.up")
                            }
                            .disabled(settings.menuOrder.first == item)
                            .accessibilityLabel("Move \(title(for: item)) up")
                            Button {
                                settings.moveMenuItem(item, by: 1)
                            } label: {
                                Image(systemName: "chevron.down")
                            }
                            .disabled(settings.menuOrder.last == item)
                            .accessibilityLabel("Move \(title(for: item)) down")
                        }
                    }
                } header: {
                    Text("MENU CUSTOMIZATION")
                } footer: {
                    Text("Choose icons only or icons with labels, then use the arrows to rearrange the menu.")
                }

                Section {
                    HStack {
                        Text("App")
                        Spacer()
                        Text("CamPro Beta")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Developer")
                        Spacer()
                        Text("Abhijeet Mitra")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Build")
                        Spacer()
                        Text((Bundle.main.object(forInfoDictionaryKey: "CAMPRO_BUILD_NAME") as? String) ?? "Build 54")
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
    }

    private func title(for item: String) -> String {
        switch item {
        case "focus": return "Focus"
        case "lens": return "Lens"
        case "aspectRatio": return "Ratio"
        case "flash": return "Flash"
        case "exposure": return "Exposure"
        case "depth": return "Depth"
        case "settings": return "Settings"
        default: return item.capitalized
        }
    }

    private func iconName(for item: String) -> String {
        switch item {
        case "focus": return "scope"
        case "lens": return "circle.circle"
        case "aspectRatio": return "viewfinder"
        case "flash": return "bolt.fill"
        case "exposure": return "sun.max"
        case "depth": return "camera.aperture"
        case "settings": return "gearshape"
        default: return "circle"
        }
    }
}
