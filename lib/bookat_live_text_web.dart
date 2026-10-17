import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// Web implementation: text recognition is not available in the browser.
/// `isSupported` returns false so apps (and FlutterFlow Test / Run Mode) keep
/// working and can simply hide the feature.
class BookatLiveTextWeb {
  BookatLiveTextWeb._();

  static void registerWith(Registrar registrar) {
    final channel = MethodChannel(
      'bookat_live_text',
      const StandardMethodCodec(),
      registrar,
    );
    channel.setMethodCallHandler((MethodCall call) async {
      switch (call.method) {
        case 'isSupported':
          return false;
        case 'recognize':
          throw PlatformException(
            code: 'unsupported',
            message: 'Text recognition is not available on the web.',
          );
        default:
          throw PlatformException(
            code: 'unimplemented',
            message: 'bookat_live_text for web does not implement ${call.method}.',
          );
      }
    });
  }
}
