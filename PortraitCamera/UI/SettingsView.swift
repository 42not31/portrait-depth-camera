
import SwiftUI

struct SettingsView: View {
    @ObservedObject var camera: CameraModel
    @ObservedObject var settings: CamProSettings
    @Environment(\.dismiss) private var dismiss

    private var toneBinding: Binding<Double> {
        Binding(
            get: { camera.styleAdjustment.tone },
            set: { camera.setStyleAdjustment(tone: $0) }
        )
    }

    private var colorBinding: Binding<Double> {
        Binding(
            get: { camera.styleAdjustment.color },
            set: { camera.setStyleAdjustment(color: $0) }
        )
    }

    private var paletteBinding: Binding<Double> {
        Binding(
            get: { camera.styleAdjustment.palette },
            set: { camera.setStyleAdjustment(palette: $0) }
        )
    }

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
                }

                Section {
                    Toggle("Apple photo metadata", isOn: $settings.includeApplePhotoMetadata)
                    Toggle("Depth data", isOn: $settings.includeDepthData)
                    Toggle("Portrait effects matte", isOn: $settings.includePortraitMatte)
                    Toggle("Semantic mattes", isOn: $settings.includeSemanticMattes)
                } header: {
                    Text("APPLE PHOTO DATA")
                } footer: {
                    Text("These options add supported depth, portrait, and semantic layers to HEIF photos when the camera provides them.")
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Tone", value: String(format: "%.0f", camera.styleAdjustment.tone))
                        Slider(value: toneBinding, in: -100...100)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Color", value: String(format: "%.0f", camera.styleAdjustment.color))
                        Slider(value: colorBinding, in: -100...100)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Palette", value: String(format: "%.0f", camera.styleAdjustment.palette))
                        Slider(value: paletteBinding, in: 0...100)
                    }
                    Button("Reset style controls") {
                        camera.resetStyleAdjustment()
                    }
                } header: {
                    Text("PHOTOGRAPHIC STYLE PACKAGE")
                } footer: {
                    Text("Adjust these values before taking a photo. The app writes the selected look into the saved HEIF image.")
                }

                Section {
                    Picker("Menu appearance", selection: $settings.menuDisplayStyle) {
                        ForEach(MenuDisplayStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                } header: {
                    Text("MENU")
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
            .onAppear {
                camera.includeApplePhotoMetadata = settings.includeApplePhotoMetadata
                camera.includeSemanticMattes = settings.includeSemanticMattes
                camera.includeDepthData = settings.includeDepthData
                camera.includePortraitMatte = settings.includePortraitMatte
            }
            .onChange(of: settings.includeApplePhotoMetadata) { camera.includeApplePhotoMetadata = $0 }
            .onChange(of: settings.includeSemanticMattes) { camera.includeSemanticMattes = $0 }
            .onChange(of: settings.includeDepthData) { camera.includeDepthData = $0 }
            .onChange(of: settings.includePortraitMatte) { camera.includePortraitMatte = $0 }
        }
        .tint(CamProTheme.accent)
    }
}

// References:
// Apple AVDepthData: https://developer.apple.com/documentation/avfoundation/avdepthdata
// Apple AVSemanticSegmentationMatte: https://developer.apple.com/documentation/avfoundation/avsemanticsegmentationmatte
// Apple portrait effects matte: https://developer.apple.com/documentation/avfoundation/avportraiteffectsmatte
