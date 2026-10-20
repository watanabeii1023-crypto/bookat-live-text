/// On-device text recognition with Apple's VisionKit (the Live Text engine).
///
/// - [BookatLiveText.recognize]: all text of an image, in reading order
///   (vertical Japanese columns from right to left). iOS 16+.
/// - [BookatLiveText.selectText]: the photo full screen with Live Text
///   selection (long-press and drag the handles, pinch to zoom), like the
///   Photos app; returns the selected text. iOS 17+.
/// - [BookatLiveText.capturePhoto]: an in-app camera (no "Retake / Use
///   Photo" screen). iOS 16+.
/// - [BookatLiveText.captureAndSelectText]: the camera, then the selection
///   screen, in one flow (with 「撮り直す」). iOS 17+.
///
/// Live Text needs a device that supports it (A12 Bionic or later). On
/// Android, the web and older iOS, [BookatLiveText.isSupported] and
/// [BookatLiveText.isSelectionSupported] return false and the other methods
/// throw a [BookatLiveTextException] with code `unsupported`.
library bookat_live_text;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Error from the methods of [BookatLiveText].
class BookatLiveTextException implements Exception {
  BookatLiveTextException(this.code, [this.message]);

  /// `unsupported` (not available on this device), `invalid_image` (the
  /// bytes are not an image), `failed` (the analysis failed), `busy` (a
  /// screen is already open), `camera_access_denied`, `camera_unavailable`
  /// or `no_view_controller`.
  final String code;

  /// Details for logs (not meant for users).
  final String? message;

  @override
  String toString() =>
      'BookatLiveTextException($code${message == null ? '' : ': $message'})';
}

/// Texts of the native screens. Empty values use the Japanese defaults.
class BookatLiveTextLabels {
  const BookatLiveTextLabels({
    this.cancel = 'キャンセル',
    this.use = 'この文章を使う',
    this.retake = '撮り直す',
    this.hint = '文章を長押しして、つまみを動かして範囲を選んでください',
    this.notSelected = '使いたい文章を長押しして選んでください',
    this.noText = '文字が見つかりませんでした。撮り直すか、別の写真をお試しください',
    this.analyzing = '文字を探しています…',
    this.failed = '読み取りに失敗しました。もう一度お試しください',
    this.cameraHint = '引用したいページを撮影してください',
    this.shutter = '撮影',
    this.light = 'ライト',
  });

  final String cancel;
  final String use;
  final String retake;
  final String hint;
  final String notSelected;
  final String noText;
  final String analyzing;
  final String failed;
  final String cameraHint;
  final String shutter;
  final String light;

  Map<String, String> toMap() => <String, String>{
        'cancel': cancel,
        'use': use,
        'retake': retake,
        'hint': hint,
        'notSelected': notSelected,
        'noText': noText,
        'analyzing': analyzing,
        'failed': failed,
        'cameraHint': cameraHint,
        'shutter': shutter,
        'light': light,
      };
}

/// Result of [BookatLiveText.captureAndSelectText].
class BookatLiveTextSelection {
  const BookatLiveTextSelection({required this.text, required this.image});

  /// The text the user selected.
  final String text;

  /// The photo (JPEG), e.g. to open the selection screen again with
  /// [BookatLiveText.selectText].
  final Uint8List image;
}

/// Entry point of the plugin.
class BookatLiveText {
  BookatLiveText._();

  static const MethodChannel _channel = MethodChannel('bookat_live_text');

  static bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static Future<bool> _flag(String method) async {
    if (!_isIOS) return false;
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<T?> _call<T>(String method, Map<String, dynamic> args) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw BookatLiveTextException(e.code, e.message);
    } on MissingPluginException catch (e) {
      throw BookatLiveTextException('unsupported', e.message);
    }
  }

  static int _argb(Color? c) => c == null
      ? 0xFF007AFF
      : (((c.a * 255).round() & 0xFF) << 24) |
          (((c.r * 255).round() & 0xFF) << 16) |
          (((c.g * 255).round() & 0xFF) << 8) |
          ((c.b * 255).round() & 0xFF);

  /// True when text recognition is available on this device
  /// (iOS 16+ and `ImageAnalyzer.isSupported`). Never throws.
  static Future<bool> isSupported() => _flag('isSupported');

  /// True when [selectText] / [captureAndSelectText] are available
  /// (iOS 17+ and `ImageAnalyzer.isSupported`). Never throws.
  static Future<bool> isSelectionSupported() => _flag('isSelectionSupported');

  /// Recognizes the text in [imageBytes] (JPEG / PNG / HEIC bytes) and
  /// returns it in reading order. Returns '' when no text is found.
  ///
  /// [locales]: recognition languages such as `['ja-JP']`. Empty (default)
  /// uses the device's languages, the same as Live Text in the Photos app.
  /// [maxDimension]: the longer side is scaled down to this many pixels
  /// before analysis (keeps memory low for large camera photos).
  static Future<String> recognize(
    Uint8List imageBytes, {
    List<String> locales = const <String>[],
    int maxDimension = 3000,
  }) async {
    if (!await isSupported()) {
      throw BookatLiveTextException(
          'unsupported', 'Text recognition is not available on this device.');
    }
    if (imageBytes.isEmpty) {
      throw BookatLiveTextException('invalid_image', 'The image is empty.');
    }
    final text = await _call<String>('recognize', <String, dynamic>{
      'image': imageBytes,
      'locales': locales,
      'maxDimension': maxDimension,
    });
    return text ?? '';
  }

  /// Opens the in-app camera (preview, tap to focus, light, shutter). The
  /// photo comes back right away as JPEG bytes (upright, longer side at most
  /// [maxDimension] pixels); null when cancelled.
  static Future<Uint8List?> capturePhoto({
    int maxDimension = 4000,
    BookatLiveTextLabels labels = const BookatLiveTextLabels(),
    Color? accentColor,
  }) async {
    if (!await isSupported()) {
      throw BookatLiveTextException('unsupported', 'Not available on this device.');
    }
    return _call<Uint8List>('capturePhoto', <String, dynamic>{
      'maxDimension': maxDimension,
      'labels': labels.toMap(),
      'accent': _argb(accentColor),
    });
  }

  /// Shows [imageBytes] full screen with Live Text selection (long-press
  /// text and drag the handles; pinch to zoom). Returns the selected text
  /// when the user taps [BookatLiveTextLabels.use], or null when cancelled.
  static Future<String?> selectText(
    Uint8List imageBytes, {
    List<String> locales = const <String>[],
    int maxDimension = 4000,
    BookatLiveTextLabels labels = const BookatLiveTextLabels(),
    Color? accentColor,
  }) async {
    if (!await isSelectionSupported()) {
      throw BookatLiveTextException('unsupported', 'Text selection needs iOS 17.');
    }
    if (imageBytes.isEmpty) {
      throw BookatLiveTextException('invalid_image', 'The image is empty.');
    }
    return _call<String>('selectText', <String, dynamic>{
      'image': imageBytes,
      'locales': locales,
      'maxDimension': maxDimension,
      'labels': labels.toMap(),
      'accent': _argb(accentColor),
    });
  }

  /// The in-app camera, then the selection screen (with 「撮り直す」 back to
  /// the camera). Returns the selected text and the photo, or null when
  /// cancelled.
  static Future<BookatLiveTextSelection?> captureAndSelectText({
    List<String> locales = const <String>[],
    int maxDimension = 4000,
    BookatLiveTextLabels labels = const BookatLiveTextLabels(),
    Color? accentColor,
  }) async {
    if (!await isSelectionSupported()) {
      throw BookatLiveTextException('unsupported', 'Text selection needs iOS 17.');
    }
    final raw = await _call<Map<Object?, Object?>>('captureAndSelect', <String, dynamic>{
      'locales': locales,
      'maxDimension': maxDimension,
      'labels': labels.toMap(),
      'accent': _argb(accentColor),
    });
    if (raw == null) return null;
    final text = raw['text'];
    final image = raw['image'];
    if (text is! String || image is! Uint8List) return null;
    return BookatLiveTextSelection(text: text, image: image);
  }
}
