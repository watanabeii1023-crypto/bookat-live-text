# bookat_live_text

On-device text recognition for Flutter using Apple's **VisionKit
`ImageAnalyzer`** — the engine behind Live Text in the Photos app.
`ImageAnalysis.transcript` returns text "in the reading order of the language
and region", so vertical Japanese (縦書き) comes back column by column from right
to left.

| Platform | Behavior |
|---|---|
| iOS 16+ on devices that support Live Text (A12 Bionic or later) | Recognizes text |
| Older iOS, Android, web | `isSupported()` returns `false` |

Images are processed on the device and are not sent anywhere.

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

if (await BookatLiveText.isSupported()) {
  try {
    final text = await BookatLiveText.recognize(imageBytes); // JPEG / PNG / HEIC bytes
    // text == '' when nothing was found
  } on BookatLiveTextException catch (e) {
    // e.code: 'unsupported' | 'invalid_image' | 'failed'
  }
}
```

- `locales`: e.g. `['ja-JP']`. Empty (default) uses the device's languages, the
  same as Live Text in the Photos app.
- `maxDimension`: the longer side is scaled down to this many pixels before
  analysis (default 3000).

Crop the image to the passage you want before recognizing it; page numbers,
running heads and ruby may otherwise be included.
