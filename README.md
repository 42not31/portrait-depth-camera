# Portrait Depth

Portrait Depth is a private SwiftUI camera app for iPhone 13 and later. Version 1 focuses on rear-camera Portrait capture with native AVFoundation depth delivery, Portrait Effects matte delivery when supported, and software-simulated 1×/2×/3× framing.

The app intentionally saves the original HEIC representation returned by `AVCapturePhoto.fileDataRepresentation()` to the user’s Photos library. This preserves the depth and portrait auxiliary data path instead of saving only a flattened blur. Apple Photos may then expose its native Depth Control and focus-point editing when the captured camera format produces the required metadata.

## Version 1 controls

The camera screen provides a rear-camera viewfinder, 1×/2×/3× zoom presets, pinch zoom, tap-to-focus and exposure, a subject/depth readiness indicator, and a single shutter button. There is no selfie mode, portrait video, filter system, or custom editor in this first version.

## Build and installation model

The repository is intended to be connected to Codemagic. The `codemagic.yaml` workflow uses a macOS runner to build the app for `iphoneos` with code signing disabled, packages the resulting device `.app` inside `Payload/`, and uploads `PortraitCamera-unsigned.ipa` plus `SHA256SUMS.txt` as artifacts.

The IPA is deliberately unsigned. Sideloadly must sign it with the user’s Apple ID or developer provisioning setup before installing it on an iPhone. The app’s bundle identifier is `com.abhi.portraitdepth`; if the signing tool changes the identifier, the installed app will use that new identifier.

## Important hardware limitation

The iPhone 13 has no rear telephoto lens. The 2× and 3× choices therefore use sensor crop/enlargement rather than true telephoto optics. The app preserves the depth metadata from the active capture configuration, but the exact Portrait Effects matte availability depends on the device format and the scene, so the app reports readiness instead of pretending that every scene will produce a matte.

## Required permissions

The app requests camera access and add-only Photos access. It does not request read access to the photo library in version 1.

## New style presets

The camera now includes named, adjustable style presets inspired by newer-generation iPhone looks: Natural Bright, Warm Skin, Rich Color, Golden, Dramatic, Cool Contrast, and Monochrome. Each preset can be fine-tuned with the existing tone, colour, and palette controls before capture.

These are app-created styles, not Apple’s private native Photographic Styles metadata. They are applied to the saved image by the app while the original camera/depth representation remains the fallback when the adjustment is neutral. The app does not claim the photo was captured by an iPhone 16 or iPhone 17.
