import Flutter
import UIKit
import Photos
import AVFoundation
import livekit_client

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Process-owned, but PushKit registration remains explicitly inactive. This
  // lazy owner is attached to the ordinary scene engine only; a killed-state
  // headless-engine handoff must not create a second media owner.
  private lazy var incomingCalls: NativeIncomingCalls = {
    let owner = NativeIncomingCalls()
    owner.audioAvailability = { available in
      LiveKitPlugin.setEngineAvailability(isInputAvailable: available, isOutputAvailable: available)
    }
    return owner
  }()

  private var posterBusy = false
  private let posterQueue = DispatchQueue(label: "sanjaal-poster")

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SanjaalVideoPoster") else { return }
    incomingCalls.attach(registrar.messenger())
    registerDeviceAccess(registrar.messenger())
    registrar.register(MemoryVideoFactory(messenger: registrar.messenger()), withId: "au.fintex.sanjaal/memory-video")
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

// Permission state only. No media lookup, permission request or capture occurs.
private func registerDeviceAccess(_ messenger: FlutterBinaryMessenger) {
  let channel = FlutterMethodChannel(name: "au.fintex.sanjaal/device-access", binaryMessenger: messenger)
  func captureState(_ media: AVMediaType) -> String {
    switch AVCaptureDevice.authorizationStatus(for: media) {
    case .authorized: return "allowed"
    case .denied: return "not_allowed"
    case .notDetermined: return "not_requested"
    case .restricted: return "restricted"
    @unknown default: return "unknown"
    }
  }
  func photoState() -> String {
    let status: PHAuthorizationStatus
    if #available(iOS 14, *) {
      status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
      if status == .limited { return "limited" }
    } else {
      status = PHPhotoLibrary.authorizationStatus()
    }
    switch status {
    case .authorized: return "allowed"
    case .denied: return "not_allowed"
    case .notDetermined: return "not_requested"
    case .restricted: return "restricted"
    default: return "unknown"
    }
  }
  channel.setMethodCallHandler { call, result in
    switch call.method {
    case "status":
      let photos = photoState()
      result(["platform": "ios", "states": ["camera": captureState(.video),
        "microphone": captureState(.audio), "photos": photos, "videos": photos]] as [String: Any])
    case "settings":
      guard let url = URL(string: UIApplication.openSettingsURLString) else { result(false); return }
      UIApplication.shared.open(url, options: [:]) { opened in result(opened) }
    default: result(FlutterMethodNotImplemented)
    }
  }
}
