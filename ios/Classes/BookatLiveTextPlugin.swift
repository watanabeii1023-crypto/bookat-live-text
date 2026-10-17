import Flutter
import UIKit
import VisionKit

/// Method channel "bookat_live_text":
/// - isSupported -> Bool (iOS 16+ and ImageAnalyzer.isSupported)
/// - recognize {image: bytes, locales: [String], maxDimension: Int}
///     -> String (ImageAnalysis.transcript, in reading order)
///   errors: unsupported / invalid_image / failed
public class BookatLiveTextPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "bookat_live_text",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(BookatLiveTextPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isSupported":
      result(BookatLiveTextPlugin.isAnalyzerSupported())
    case "recognize":
      recognize(call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func isAnalyzerSupported() -> Bool {
    if #available(iOS 16.0, *) {
      return ImageAnalyzer.isSupported
    }
    return false
  }

  private func recognize(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard #available(iOS 16.0, *) else {
      result(FlutterError(code: "unsupported", message: "iOS 16 or later is required.", details: nil))
      return
    }
    guard ImageAnalyzer.isSupported else {
      result(FlutterError(code: "unsupported", message: "This device does not support Live Text.", details: nil))
      return
    }
    guard
      let args = call.arguments as? [String: Any],
      let typed = args["image"] as? FlutterStandardTypedData,
      let source = UIImage(data: typed.data)
    else {
      result(FlutterError(code: "invalid_image", message: "The image could not be read.", details: nil))
      return
    }
    let locales = (args["locales"] as? [String]) ?? []
    let maxDimension = CGFloat((args["maxDimension"] as? NSNumber)?.doubleValue ?? 3000)

    Task { @MainActor in
      do {
        let image = BookatLiveTextPlugin.upright(source, maxDimension: maxDimension)
        var configuration = ImageAnalyzer.Configuration([.text])
        if !locales.isEmpty {
          configuration.locales = locales
        }
        let analyzer = ImageAnalyzer()
        let analysis = try await analyzer.analyze(image, configuration: configuration)
        result(analysis.transcript)
      } catch {
        result(FlutterError(code: "failed", message: error.localizedDescription, details: nil))
      }
    }
  }

  /// Draws the image upright (EXIF orientation applied), scaling the longer
  /// side down to maxDimension pixels when it is larger.
  private static func upright(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
    let size = image.size
    let longest = max(size.width, size.height)
    let ratio = (maxDimension > 0 && longest > maxDimension) ? maxDimension / longest : 1
    if ratio == 1 && image.imageOrientation == .up {
      return image
    }
    let target = CGSize(
      width: max(1, (size.width * ratio).rounded()),
      height: max(1, (size.height * ratio).rounded())
    )
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    return UIGraphicsImageRenderer(size: target, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: target))
    }
  }
}
