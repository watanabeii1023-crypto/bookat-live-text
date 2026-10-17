/// On-device text recognition with Apple's VisionKit ImageAnalyzer (the Live
/// Text engine). Vertical Japanese comes back in reading order (columns from
/// right to left).
///
/// Works on iOS 16+ on devices that support Live Text (A12 Bionic or later).
/// On Android, the web and older iOS, [BookatLiveText.isSupported] returns
/// false and [BookatLiveText.recognize] throws a [BookatLiveTextException]
/// with code `unsupported`.
library bookat_live_text;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Error from [BookatLiveText.recognize].
class BookatLiveTextException implements Exception {
  BookatLiveTextException(this.code, [this.message]);

  /// `unsupported` (not available on this device), `invalid_image` (the
  /// bytes are not an image) or `failed` (the analysis failed).
  final String code;

  /// Details for logs (not meant for users).
  final String? message;

  @override
  String toString() =>
      'BookatLiveTextException($code${message == null ? '' : ': $message'})';
}

/// Entry point of the plugin.
class BookatLiveText {
  BookatLiveText._();

  static const MethodChannel _channel = MethodChannel('bookat_live_text');

  /// True when text recognition is available on this device
  /// (iOS 16+ and `ImageAnalyzer.isSupported`). Never throws.
  static Future<bool> isSupported() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return false;
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

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
    try {
      final text = await _channel.invokeMethod<String>(
        'recognize',
        <String, dynamic>{
          'image': imageBytes,
          'locales': locales,
          'maxDimension': maxDimension,
        },
      );
      return text ?? '';
    } on PlatformException catch (e) {
      throw BookatLiveTextException(e.code, e.message);
    } on MissingPluginException catch (e) {
      throw BookatLiveTextException('unsupported', e.message);
    }
  }
}
