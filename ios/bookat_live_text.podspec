Pod::Spec.new do |s|
  s.name             = 'bookat_live_text'
  s.version          = '0.2.0'
  s.summary          = 'On-device text recognition and Live Text selection with VisionKit, plus an in-app camera.'
  s.description      = <<-DESC
On-device text recognition with Apple's VisionKit ImageAnalyzer (the Live Text
engine), including vertical Japanese in reading order (iOS 16+); a full-screen
Live Text selection screen with ImageAnalysisInteraction (iOS 17+); and an
in-app camera without a "Retake / Use Photo" screen.
                       DESC
  s.homepage         = 'https://github.com/watanabeii1023-crypto/bookat-live-text'
  s.license          = { :file => '../LICENSE' }
  s.author           = 'Book@'
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.frameworks       = 'VisionKit', 'AVFoundation'
  s.swift_version    = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
end
