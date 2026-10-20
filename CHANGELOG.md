## 0.2.0

- `selectText()`: the photo full screen with Live Text selection
  (`ImageAnalysisInteraction`, long-press and drag the handles, pinch to
  zoom), like the Photos app; returns the selected text (`selectedText`,
  iOS 17+).
- `capturePhoto()`: in-app camera (tap to focus, light, shutter) without a
  "Retake / Use Photo" screen (iOS 16+).
- `captureAndSelectText()`: camera, then the selection screen, with
  「撮り直す」 back to the camera (iOS 17+).
- `isSelectionSupported()`.
- Screen texts and the button color can be set from Dart
  (`BookatLiveTextLabels`, `accentColor`).

## 0.1.0

- First version: `isSupported()` and `recognize()` with VisionKit
  `ImageAnalyzer` on iOS 16+; web implementation that reports not supported.
