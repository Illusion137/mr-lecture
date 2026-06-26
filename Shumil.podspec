require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "Shumil"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = package["license"]
  s.authors      = package["author"]

  s.platforms    = { :ios => min_ios_version_supported, :visionos => 1.0 }
  s.source       = { :git => "https://github.com/illusion137/react-native-shumil.git", :tag => "#{s.version}" }

  s.source_files = [
    # Implementation (Swift)
    "ios/**/*.{swift}",
    # Autolinking/Registration (Objective-C++)
    "ios/**/*.{m,mm}",
    # Implementation (C++ objects)
    "cpp/**/*.{hpp,cpp}",
  ]

  load 'nitrogen/generated/ios/MrLecture+autolinking.rb'
  add_nitrogen_files(s)

  s.dependency 'React-jsi'
  s.dependency 'React-callinvoker'
  install_modules_dependencies(s)

  # Piper TTS engine. The local `SherpaOnnx` pod (ios/SherpaOnnx) vendors the
  # sherpa-onnx framework and exposes its C API as the `SherpaOnnx` Clang module,
  # which makes `#if canImport(SherpaOnnx)` in PiperEngine.swift resolve true and
  # lets the baked-in SherpaOnnxAPI.swift wrapper compile. Provided in the app
  # Podfile via `pod 'SherpaOnnx', :path => './SherpaOnnx'`.
  s.dependency 'SherpaOnnx'
end
