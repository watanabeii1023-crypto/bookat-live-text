# bookat_live_text

On-device text recognition for Flutter using Apple's **VisionKit** — the
engine behind Live Text in the Photos app.

- `recognize()`: all text of an image. `ImageAnalysis.transcript` returns text
  "in the reading order of the language and region", so vertical Japanese
  (縦書き) comes back column by column from right to left.
- `selectText()`: the photo full screen with **Live Text selection**
  (`ImageAnalysisInteraction`): long-press text and drag the handles, pinch to
  zoom, then 「この文章を使う」. Returns the selected text.
- `capturePhoto()`: an **in-app camera** (tap to focus, light, shutter) that
  returns the photo right away — no "Retake / Use Photo" screen.
- `captureAndSelectText()`: the camera, then the selection screen, in one flow
  (「撮り直す」 goes back to the camera).

| Platform | Behavior |
|---|---|
| iOS 17+ on devices that support Live Text (A12 Bionic or later) | Everything |
| iOS 16 on supported devices | `recognize()`, `capturePhoto()`; `isSelectionSupported()` is `false` |
| Older iOS, Android, web | `isSupported()` and `isSelectionSupported()` return `false` |

Images are processed on the device and are not sent anywhere.

The app's `Info.plist` needs `NSCameraUsageDescription` for the camera.

## Install (Git dependency, pinned to a commit)

```yaml
dependencies:
  bookat_live_text:
    git:
      url: https://github.com/watanabeii1023-crypto/bookat-live-text
      ref: <commit SHA>
```

## Usage

```dart
import 'package:bookat_live_text/bookat_live_text.dart';

// iOS 17+: camera -> Live Text selection
if (await BookatLiveText.isSelectionSupported()) {
  final selection = await BookatLiveText.captureAndSelectText(
    accentColor: Colors.brown,
  ); // null when cancelled
  if (selection != null) {
    print(selection.text);
    // Open the same photo again:
    final again = await BookatLiveText.selectText(selection.image);
  }
}

// iOS 16+: in-app camera, then recognize everything
if (await BookatLiveText.isSupported()) {
  try {
    final photo = await BookatLiveText.capturePhoto(); // JPEG bytes or null
    if (photo != null) {
      final text = await BookatLiveText.recognize(photo); // '' when nothing found
    }
  } on BookatLiveTextException catch (e) {
    // e.code: 'unsupported' | 'invalid_image' | 'failed' | 'busy' |
    //         'camera_access_denied' | 'camera_unavailable' | 'no_view_controller'
  }
}
```

- `locales`: e.g. `['ja-JP']`. Empty (default) uses the device's languages, the
  same as Live Text in the Photos app.
- `maxDimension`: the longer side is scaled down to this many pixels
  (`recognize` 3000, the others 4000).
- `labels`: the texts of the native screens (`BookatLiveTextLabels`; Japanese
  by default). `accentColor`: the color of 「この文章を使う」.
