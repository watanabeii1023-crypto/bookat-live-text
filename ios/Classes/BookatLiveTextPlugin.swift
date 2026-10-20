import AVFoundation
import Flutter
import UIKit
import VisionKit

/// Method channel "bookat_live_text":
/// - isSupported -> Bool (iOS 16+ and ImageAnalyzer.isSupported)
/// - isSelectionSupported -> Bool (iOS 17+ and ImageAnalyzer.isSupported)
/// - recognize {image, locales, maxDimension}
///     -> String (ImageAnalysis.transcript, in reading order)
/// - capturePhoto {maxDimension, labels, accent}
///     -> JPEG bytes (in-app camera, no "Retake / Use Photo" screen) | nil
/// - selectText {image, locales, maxDimension, labels, accent}
///     -> String (the text the user selected) | nil (cancelled)
/// - captureAndSelect {locales, maxDimension, labels, accent}
///     -> {text: String, image: JPEG bytes} | nil (cancelled)
///   errors: unsupported / invalid_image / failed / busy /
///           camera_access_denied / camera_unavailable / no_view_controller
public class BookatLiveTextPlugin: NSObject, FlutterPlugin {
  private var pending: FlutterResult?
  private weak var presented: UIViewController?

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
    case "isSelectionSupported":
      result(BookatLiveTextPlugin.isSelectionSupported())
    case "recognize":
      recognize(call, result: result)
    case "capturePhoto":
      capturePhoto(call, result: result)
    case "selectText":
      selectText(call, result: result)
    case "captureAndSelect":
      captureAndSelect(call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Support

  private static func isAnalyzerSupported() -> Bool {
    if #available(iOS 16.0, *) {
      return ImageAnalyzer.isSupported
    }
    return false
  }

  /// Text selection needs ImageAnalysisInteraction.selectedText (iOS 17).
  private static func isSelectionSupported() -> Bool {
    if #available(iOS 17.0, *) {
      return ImageAnalyzer.isSupported
    }
    return false
  }

  private static func error(_ code: String, _ message: String) -> FlutterError {
    FlutterError(code: code, message: message, details: nil)
  }

  // MARK: - recognize (unchanged)

  private func recognize(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard #available(iOS 16.0, *) else {
      result(Self.error("unsupported", "iOS 16 or later is required."))
      return
    }
    guard ImageAnalyzer.isSupported else {
      result(Self.error("unsupported", "This device does not support Live Text."))
      return
    }
    guard
      let args = call.arguments as? [String: Any],
      let typed = args["image"] as? FlutterStandardTypedData,
      let source = UIImage(data: typed.data)
    else {
      result(Self.error("invalid_image", "The image could not be read."))
      return
    }
    let locales = (args["locales"] as? [String]) ?? []
    let maxDimension = CGFloat((args["maxDimension"] as? NSNumber)?.doubleValue ?? 3000)

    Task { @MainActor in
      do {
        let image = LiveTextImages.upright(source, maxDimension: maxDimension)
        var configuration = ImageAnalyzer.Configuration([.text])
        if !locales.isEmpty {
          configuration.locales = locales
        }
        let analyzer = ImageAnalyzer()
        let analysis = try await analyzer.analyze(image, configuration: configuration)
        result(analysis.transcript)
      } catch {
        result(Self.error("failed", error.localizedDescription))
      }
    }
  }

  // MARK: - Screens

  private struct Options {
    let locales: [String]
    let maxDimension: CGFloat
    let labels: LiveTextLabels
    let accent: UIColor

    init(_ arguments: Any?) {
      let args = (arguments as? [String: Any]) ?? [:]
      locales = (args["locales"] as? [String]) ?? []
      maxDimension = CGFloat((args["maxDimension"] as? NSNumber)?.doubleValue ?? 4000)
      labels = LiveTextLabels(args["labels"])
      if let argb = (args["accent"] as? NSNumber)?.uint32Value {
        accent = UIColor(
          red: CGFloat((argb >> 16) & 0xFF) / 255,
          green: CGFloat((argb >> 8) & 0xFF) / 255,
          blue: CGFloat(argb & 0xFF) / 255,
          alpha: CGFloat((argb >> 24) & 0xFF) / 255
        )
      } else {
        accent = .systemBlue
      }
    }
  }

  /// Starts a screen flow; false (and an error result) when one is running.
  private func begin(_ result: @escaping FlutterResult) -> Bool {
    if pending != nil {
      result(Self.error("busy", "Another screen is already open."))
      return false
    }
    pending = result
    return true
  }

  /// Closes the flow and answers Flutter exactly once.
  private func finish(_ value: Any?) {
    let result = pending
    pending = nil
    let screen = presented
    presented = nil
    if let screen = screen, screen.presentingViewController != nil {
      screen.dismiss(animated: true) { result?(value) }
    } else {
      result?(value)
    }
  }

  private func present(_ root: UIViewController) {
    guard let top = Self.topViewController() else {
      finish(Self.error("no_view_controller", "No view controller to present from."))
      return
    }
    let nav = UINavigationController(rootViewController: root)
    nav.setNavigationBarHidden(true, animated: false)
    nav.modalPresentationStyle = .fullScreen
    nav.overrideUserInterfaceStyle = .dark
    presented = nav
    top.present(nav, animated: true)
  }

  private static func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let windows = scenes.flatMap { $0.windows }
    let window = windows.first { $0.isKeyWindow } ?? windows.first
    var top = window?.rootViewController
    while let next = top?.presentedViewController {
      top = next
    }
    return top
  }

  /// Camera permission, then [onReady] on the main thread.
  private func withCamera(_ onReady: @escaping () -> Void) {
    guard CameraViewController.hasCamera else {
      finish(Self.error("camera_unavailable", "No camera is available."))
      return
    }
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      onReady()
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { granted in
        DispatchQueue.main.async {
          if granted {
            onReady()
          } else {
            self.finish(Self.error("camera_access_denied", "Camera access was denied."))
          }
        }
      }
    default:
      finish(Self.error("camera_access_denied", "Camera access is not allowed."))
    }
  }

  private func capturePhoto(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard begin(result) else { return }
    let options = Options(call.arguments)
    withCamera {
      let camera = CameraViewController(labels: options.labels, accent: options.accent)
      camera.onCancel = { [weak self] in self?.finish(nil) }
      camera.onPhoto = { [weak self] photo in
        let image = LiveTextImages.upright(photo, maxDimension: options.maxDimension)
        guard let data = image.jpegData(compressionQuality: 0.9) else {
          self?.finish(Self.error("failed", "The photo could not be encoded."))
          return
        }
        self?.finish(FlutterStandardTypedData(bytes: data))
      }
      self.present(camera)
    }
  }

  private func selectText(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard #available(iOS 17.0, *), ImageAnalyzer.isSupported else {
      result(Self.error("unsupported", "Text selection needs iOS 17 and Live Text."))
      return
    }
    guard
      let args = call.arguments as? [String: Any],
      let typed = args["image"] as? FlutterStandardTypedData,
      let source = UIImage(data: typed.data)
    else {
      result(Self.error("invalid_image", "The image could not be read."))
      return
    }
    guard begin(result) else { return }
    let options = Options(call.arguments)
    let image = LiveTextImages.upright(source, maxDimension: options.maxDimension)
    let screen = TextSelectionViewController(
      image: image,
      locales: options.locales,
      labels: options.labels,
      accent: options.accent,
      allowRetake: false
    )
    screen.onCancel = { [weak self] in self?.finish(nil) }
    screen.onUse = { [weak self] text in self?.finish(text) }
    present(screen)
  }

  private func captureAndSelect(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard #available(iOS 17.0, *), ImageAnalyzer.isSupported else {
      result(Self.error("unsupported", "Text selection needs iOS 17 and Live Text."))
      return
    }
    guard begin(result) else { return }
    let options = Options(call.arguments)
    withCamera {
      let camera = CameraViewController(labels: options.labels, accent: options.accent)
      camera.onCancel = { [weak self] in self?.finish(nil) }
      camera.onPhoto = { [weak self, weak camera] photo in
        let image = LiveTextImages.upright(photo, maxDimension: options.maxDimension)
        let screen = TextSelectionViewController(
          image: image,
          locales: options.locales,
          labels: options.labels,
          accent: options.accent,
          allowRetake: true
        )
        screen.onCancel = { [weak self] in self?.finish(nil) }
        screen.onRetake = { [weak camera] in
          camera?.navigationController?.popViewController(animated: true)
        }
        screen.onUse = { [weak self] text in
          let data = image.jpegData(compressionQuality: 0.9) ?? Data()
          self?.finish([
            "text": text,
            "image": FlutterStandardTypedData(bytes: data),
          ] as [String: Any])
        }
        camera?.navigationController?.pushViewController(screen, animated: true)
      }
      self.present(camera)
    }
  }
}

// MARK: - Labels

/// Texts of the native screens (from Dart; Japanese defaults).
struct LiveTextLabels {
  var cancel = "キャンセル"
  var use = "この文章を使う"
  var retake = "撮り直す"
  var hint = "文章を長押しして、つまみを動かして範囲を選んでください"
  var notSelected = "使いたい文章を長押しして選んでください"
  var noText = "文字が見つかりませんでした。撮り直すか、別の写真をお試しください"
  var analyzing = "文字を探しています…"
  var failed = "読み取りに失敗しました。もう一度お試しください"
  var cameraHint = "引用したいページを撮影してください"
  var shutter = "撮影"
  var light = "ライト"

  init(_ raw: Any?) {
    guard let map = raw as? [String: Any] else { return }
    func text(_ key: String) -> String? {
      guard let value = map[key] as? String, !value.isEmpty else { return nil }
      return value
    }
    if let v = text("cancel") { cancel = v }
    if let v = text("use") { use = v }
    if let v = text("retake") { retake = v }
    if let v = text("hint") { hint = v }
    if let v = text("notSelected") { notSelected = v }
    if let v = text("noText") { noText = v }
    if let v = text("analyzing") { analyzing = v }
    if let v = text("failed") { failed = v }
    if let v = text("cameraHint") { cameraHint = v }
    if let v = text("shutter") { shutter = v }
    if let v = text("light") { light = v }
  }
}

// MARK: - Images

enum LiveTextImages {
  /// Draws the image upright (EXIF orientation applied), scaling the longer
  /// side down to maxDimension pixels when it is larger.
  static func upright(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
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

// MARK: - Shared controls

enum LiveTextControls {
  static func textButton(_ title: String, target: Any?, action: Selector) -> UIButton {
    let button = UIButton(type: .system)
    button.setTitle(title, for: .normal)
    button.setTitleColor(.white, for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 17)
    button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
    button.addTarget(target, action: action, for: .touchUpInside)
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
  }

  static func filledButton(_ title: String, accent: UIColor, target: Any?, action: Selector) -> UIButton {
    let button = UIButton(type: .system)
    button.setTitle(title, for: .normal)
    button.setTitleColor(.white, for: .normal)
    button.setTitleColor(UIColor.white.withAlphaComponent(0.5), for: .disabled)
    button.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
    button.backgroundColor = accent
    button.layer.cornerRadius = 12
    button.contentEdgeInsets = UIEdgeInsets(top: 14, left: 20, bottom: 14, right: 20)
    button.addTarget(target, action: action, for: .touchUpInside)
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
  }

  static func hintLabel() -> UILabel {
    let label = UILabel()
    label.textColor = UIColor.white.withAlphaComponent(0.85)
    label.font = .systemFont(ofSize: 14)
    label.numberOfLines = 0
    label.textAlignment = .center
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }
}

// MARK: - Camera

/// Full-screen in-app camera: preview, tap to focus, light, shutter. The
/// photo goes straight to [onPhoto] (no "Retake / Use Photo" screen).
final class CameraViewController: UIViewController, AVCapturePhotoCaptureDelegate {
  var onPhoto: ((UIImage) -> Void)?
  var onCancel: (() -> Void)?

  private let labels: LiveTextLabels
  private let accent: UIColor
  private let session = AVCaptureSession()
  private let output = AVCapturePhotoOutput()
  private let sessionQueue = DispatchQueue(label: "bookat_live_text.camera")
  private var device: AVCaptureDevice?
  private var configured = false
  private var capturing = false
  private let preview = CameraPreviewView()
  private let shutter = UIButton(type: .custom)
  private var lightButton: UIButton?
  private let flash = UIView()

  /// Virtual multi-camera devices switch lenses for close-up pages.
  private static let deviceTypes: [AVCaptureDevice.DeviceType] = [
    .builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera,
  ]

  static var hasCamera: Bool { bestDevice() != nil }

  private static func bestDevice() -> AVCaptureDevice? {
    AVCaptureDevice.DiscoverySession(
      deviceTypes: deviceTypes, mediaType: .video, position: .back
    ).devices.first
  }

  init(labels: LiveTextLabels, accent: UIColor) {
    self.labels = labels
    self.accent = accent
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var prefersStatusBarHidden: Bool { true }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black

    preview.translatesAutoresizingMaskIntoConstraints = false
    preview.videoPreviewLayer.session = session
    preview.videoPreviewLayer.videoGravity = .resizeAspect
    view.addSubview(preview)
    preview.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(focusTap(_:))))

    let cancel = LiveTextControls.textButton(labels.cancel, target: self, action: #selector(cancelTapped))
    view.addSubview(cancel)

    let hint = LiveTextControls.hintLabel()
    hint.text = labels.cameraHint
    view.addSubview(hint)

    shutter.translatesAutoresizingMaskIntoConstraints = false
    shutter.backgroundColor = .white
    shutter.layer.cornerRadius = 34
    shutter.layer.borderWidth = 4
    shutter.layer.borderColor = UIColor.white.withAlphaComponent(0.4).cgColor
    shutter.accessibilityLabel = labels.shutter
    shutter.addTarget(self, action: #selector(shutterTapped), for: .touchUpInside)
    view.addSubview(shutter)

    flash.translatesAutoresizingMaskIntoConstraints = false
    flash.backgroundColor = .white
    flash.alpha = 0
    flash.isUserInteractionEnabled = false
    view.addSubview(flash)

    let guide = view.safeAreaLayoutGuide
    var constraints: [NSLayoutConstraint] = [
      cancel.topAnchor.constraint(equalTo: guide.topAnchor, constant: 4),
      cancel.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 8),
      preview.topAnchor.constraint(equalTo: cancel.bottomAnchor, constant: 4),
      preview.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      preview.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      hint.topAnchor.constraint(equalTo: preview.bottomAnchor, constant: 8),
      hint.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 24),
      hint.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -24),
      shutter.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 12),
      shutter.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      shutter.widthAnchor.constraint(equalToConstant: 68),
      shutter.heightAnchor.constraint(equalToConstant: 68),
      shutter.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -16),
      flash.topAnchor.constraint(equalTo: view.topAnchor),
      flash.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      flash.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      flash.trailingAnchor.constraint(equalTo: view.trailingAnchor),
    ]

    if let device = Self.bestDevice(), device.hasTorch {
      let light = LiveTextControls.textButton(labels.light, target: self, action: #selector(lightTapped))
      light.setImage(UIImage(systemName: "flashlight.off.fill"), for: .normal)
      light.tintColor = .white
      view.addSubview(light)
      lightButton = light
      constraints += [
        light.centerYAnchor.constraint(equalTo: shutter.centerYAnchor),
        light.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
      ]
    }
    NSLayoutConstraint.activate(constraints)
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    capturing = false
    shutter.isEnabled = true
    sessionQueue.async { [weak self] in
      guard let self = self else { return }
      if !self.configured { self.configure() }
      if self.configured && !self.session.isRunning { self.session.startRunning() }
    }
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    setTorch(false)
    sessionQueue.async { [weak self] in
      guard let self = self, self.session.isRunning else { return }
      self.session.stopRunning()
    }
  }

  /// On the session queue.
  private func configure() {
    guard let device = Self.bestDevice(),
      let input = try? AVCaptureDeviceInput(device: device)
    else { return }
    session.beginConfiguration()
    session.sessionPreset = .photo
    if session.canAddInput(input) { session.addInput(input) }
    if session.canAddOutput(output) {
      session.addOutput(output)
      output.maxPhotoQualityPrioritization = .quality
    }
    session.commitConfiguration()
    if (try? device.lockForConfiguration()) != nil {
      if device.isFocusModeSupported(.continuousAutoFocus) {
        device.focusMode = .continuousAutoFocus
      }
      if device.isExposureModeSupported(.continuousAutoExposure) {
        device.exposureMode = .continuousAutoExposure
      }
      device.isSubjectAreaChangeMonitoringEnabled = true
      device.unlockForConfiguration()
    }
    self.device = device
    configured = true
  }

  @objc private func cancelTapped() {
    onCancel?()
  }

  @objc private func focusTap(_ gesture: UITapGestureRecognizer) {
    let layerPoint = gesture.location(in: preview)
    let point = preview.videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: layerPoint)
    sessionQueue.async { [weak self] in
      guard let device = self?.device, (try? device.lockForConfiguration()) != nil else { return }
      if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
        device.focusPointOfInterest = point
        device.focusMode = .autoFocus
      }
      if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.autoExpose) {
        device.exposurePointOfInterest = point
        device.exposureMode = .autoExpose
      }
      device.unlockForConfiguration()
    }
  }

  @objc private func lightTapped() {
    let on = device?.torchMode != .on
    setTorch(on)
    lightButton?.setImage(
      UIImage(systemName: on ? "flashlight.on.fill" : "flashlight.off.fill"), for: .normal)
  }

  private func setTorch(_ on: Bool) {
    sessionQueue.async { [weak self] in
      guard let device = self?.device, device.hasTorch,
        (try? device.lockForConfiguration()) != nil
      else { return }
      device.torchMode = on ? .on : .off
      device.unlockForConfiguration()
    }
  }

  @objc private func shutterTapped() {
    guard !capturing, configured else { return }
    capturing = true
    shutter.isEnabled = false
    UIView.animate(withDuration: 0.08, animations: { self.flash.alpha = 0.7 }) { _ in
      UIView.animate(withDuration: 0.2) { self.flash.alpha = 0 }
    }
    sessionQueue.async { [weak self] in
      guard let self = self else { return }
      let settings: AVCapturePhotoSettings
      if self.output.availablePhotoCodecTypes.contains(.jpeg) {
        settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
      } else {
        settings = AVCapturePhotoSettings()
      }
      settings.photoQualityPrioritization = .balanced
      if let connection = self.output.connection(with: .video) {
        if #available(iOS 17.0, *) {
          if connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
          }
        } else if connection.isVideoOrientationSupported {
          connection.videoOrientation = .portrait
        }
      }
      self.output.capturePhoto(with: settings, delegate: self)
    }
  }

  func photoOutput(
    _ output: AVCapturePhotoOutput,
    didFinishProcessingPhoto photo: AVCapturePhoto,
    error: Error?
  ) {
    let image = photo.fileDataRepresentation().flatMap { UIImage(data: $0) }
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      guard let image = image, error == nil else {
        self.capturing = false
        self.shutter.isEnabled = true
        return
      }
      self.onPhoto?(image)
    }
  }
}

final class CameraPreviewView: UIView {
  override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
  var videoPreviewLayer: AVCaptureVideoPreviewLayer {
    // layerClass guarantees the type.
    layer as! AVCaptureVideoPreviewLayer
  }
}

// MARK: - Text selection (Live Text, like the Photos app)

/// The photo full screen with ImageAnalysisInteraction text selection and
/// pinch zoom. Long-press text and drag the handles, then 「この文章を使う」.
@available(iOS 17.0, *)
final class TextSelectionViewController: UIViewController, UIScrollViewDelegate {
  var onUse: ((String) -> Void)?
  var onCancel: (() -> Void)?
  var onRetake: (() -> Void)?

  private let image: UIImage
  private let locales: [String]
  private let labels: LiveTextLabels
  private let accent: UIColor
  private let allowRetake: Bool

  private let scrollView = UIScrollView()
  private let imageView = UIImageView()
  private let interaction = ImageAnalysisInteraction()
  private let analyzer = ImageAnalyzer()
  private let hint = LiveTextControls.hintLabel()
  private let spinner = UIActivityIndicatorView(style: .medium)
  private var useButton: UIButton!
  private var analysisTask: Task<Void, Never>?

  init(image: UIImage, locales: [String], labels: LiveTextLabels, accent: UIColor, allowRetake: Bool) {
    self.image = image
    self.locales = locales
    self.labels = labels
    self.accent = accent
    self.allowRetake = allowRetake
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var prefersStatusBarHidden: Bool { true }

  deinit {
    analysisTask?.cancel()
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black

    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.delegate = self
    scrollView.minimumZoomScale = 1
    scrollView.maximumZoomScale = 5
    scrollView.showsVerticalScrollIndicator = false
    scrollView.showsHorizontalScrollIndicator = false
    scrollView.contentInsetAdjustmentBehavior = .never
    view.addSubview(scrollView)

    imageView.image = image
    imageView.contentMode = .scaleAspectFit
    imageView.isUserInteractionEnabled = true
    imageView.addInteraction(interaction)
    scrollView.addSubview(imageView)

    interaction.preferredInteractionTypes = []
    interaction.isSupplementaryInterfaceHidden = true

    let cancel = LiveTextControls.textButton(labels.cancel, target: self, action: #selector(cancelTapped))
    view.addSubview(cancel)

    useButton = LiveTextControls.filledButton(labels.use, accent: accent, target: self, action: #selector(useTapped))
    useButton.isEnabled = false
    useButton.alpha = 0.5
    view.addSubview(useButton)

    hint.text = labels.analyzing
    view.addSubview(hint)

    spinner.color = .white
    spinner.translatesAutoresizingMaskIntoConstraints = false
    spinner.hidesWhenStopped = true
    view.addSubview(spinner)
    spinner.startAnimating()

    let guide = view.safeAreaLayoutGuide
    var constraints: [NSLayoutConstraint] = [
      cancel.topAnchor.constraint(equalTo: guide.topAnchor, constant: 4),
      cancel.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 8),
      scrollView.topAnchor.constraint(equalTo: cancel.bottomAnchor, constant: 4),
      scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      hint.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 10),
      hint.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 24),
      hint.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -24),
      useButton.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 12),
      useButton.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
      useButton.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -12),
      spinner.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
      spinner.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
    ]
    if allowRetake {
      let retake = LiveTextControls.textButton(labels.retake, target: self, action: #selector(retakeTapped))
      view.addSubview(retake)
      constraints += [
        retake.centerYAnchor.constraint(equalTo: useButton.centerYAnchor),
        retake.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 8),
        useButton.leadingAnchor.constraint(greaterThanOrEqualTo: retake.trailingAnchor, constant: 12),
      ]
    } else {
      constraints.append(useButton.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16))
    }
    NSLayoutConstraint.activate(constraints)

    analyze()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    if scrollView.zoomScale == 1 {
      imageView.frame = scrollView.bounds
      scrollView.contentSize = scrollView.bounds.size
    }
    interaction.setContentsRectNeedsUpdate()
  }

  private func analyze() {
    analysisTask = Task { @MainActor [weak self] in
      guard let self = self else { return }
      var configuration = ImageAnalyzer.Configuration([.text])
      if !self.locales.isEmpty {
        configuration.locales = self.locales
      }
      do {
        let analysis = try await self.analyzer.analyze(self.image, configuration: configuration)
        if Task.isCancelled { return }
        self.spinner.stopAnimating()
        self.interaction.analysis = analysis
        if analysis.hasResults(for: .text) {
          self.interaction.preferredInteractionTypes = .textSelection
          self.hint.text = self.labels.hint
          self.useButton.isEnabled = true
          self.useButton.alpha = 1
        } else {
          self.hint.text = self.labels.noText
        }
      } catch {
        if Task.isCancelled { return }
        self.spinner.stopAnimating()
        self.hint.text = self.labels.failed
      }
    }
  }

  @objc private func cancelTapped() {
    onCancel?()
  }

  @objc private func retakeTapped() {
    onRetake?()
  }

  @objc private func useTapped() {
    let text = interaction.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      hint.text = labels.notSelected
      UINotificationFeedbackGenerator().notificationOccurred(.warning)
      return
    }
    onUse?(text)
  }

  // MARK: UIScrollViewDelegate

  func viewForZooming(in scrollView: UIScrollView) -> UIView? {
    imageView
  }

  func scrollViewDidZoom(_ scrollView: UIScrollView) {
    // Keep the image centered while it is smaller than the screen.
    let offsetX = max((scrollView.bounds.width - scrollView.contentSize.width) / 2, 0)
    let offsetY = max((scrollView.bounds.height - scrollView.contentSize.height) / 2, 0)
    imageView.center = CGPoint(
      x: scrollView.contentSize.width / 2 + offsetX,
      y: scrollView.contentSize.height / 2 + offsetY
    )
    interaction.setContentsRectNeedsUpdate()
  }
}
