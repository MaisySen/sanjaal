import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private var posterBusy = false
  private let posterQueue = DispatchQueue(label: "sanjaal-poster")

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SanjaalVideoPoster") else { return }
    let channel = FlutterMethodChannel(name: "au.fintex.sanjaal/video-poster", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "extract" else { result(FlutterMethodNotImplemented); return }
      guard let self = self, !self.posterBusy,
        let args = call.arguments as? [String: Any], let path = args["path"] as? String,
        !path.contains("://") else { result(nil); return }
      let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
      let roots = [URL(fileURLWithPath: NSTemporaryDirectory())] + FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask) + FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
      guard roots.contains(where: { url.path.hasPrefix($0.resolvingSymlinksInPath().path + "/") }),
        let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
        size > 0, size <= 25 * 1024 * 1024 else { result(nil); return }
      self.posterBusy = true
      self.posterQueue.async {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 320)
        var bytes: Data? = nil
        if let frame = try? generator.copyCGImage(at: .zero, actualTime: nil),
          let jpeg = UIImage(cgImage: frame).jpegData(compressionQuality: 0.75), jpeg.count <= 256 * 1024 {
          bytes = jpeg
        }
        DispatchQueue.main.async {
          self.posterBusy = false
          result(bytes.map { FlutterStandardTypedData(bytes: $0) })
        }
      }
    }
  }
}
