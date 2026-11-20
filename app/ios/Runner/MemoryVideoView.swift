import Flutter
import UIKit
import AVFoundation

// Private bounded bytes only. This custom scheme is serviced in-process; it has
// no URLSession, file path, local HTTP listener or decrypted temporary file.
private final class MemoryVideoSource: NSObject, AVAssetResourceLoaderDelegate {
  private var bytes: Data?
  private let type: String
  init(bytes: Data, type: String) { self.bytes = bytes; self.type = type }
  func clear() { let count = bytes?.count ?? 0; bytes?.resetBytes(in: 0..<count); bytes = nil }
  func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest) -> Bool {
    guard let bytes = bytes else { request.finishLoading(with: NSError(domain: "MemoryVideo", code: 1)); return true }
    if let info = request.contentInformationRequest {
      info.contentType = type
      info.contentLength = Int64(bytes.count)
      info.isByteRangeAccessSupported = true
    }
    if let data = request.dataRequest {
      let offset = max(data.requestedOffset, data.currentOffset)
      guard offset >= 0, offset <= Int64(bytes.count) else { request.finishLoading(with: NSError(domain: "MemoryVideo", code: 2)); return true }
      let start = Int(offset)
      let count = data.requestsAllDataToEndOfResource ? bytes.count - start : min(data.requestedLength, bytes.count - start)
      if count > 0 { data.respond(with: bytes.subdata(in: start..<(start + count))) }
    }
    request.finishLoading()
    return true
  }
}
private final class MemoryPlayerSurface: UIView {
  override class var layerClass: AnyClass { AVPlayerLayer.self }
  var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
final class MemoryVideoFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger
  init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    MemoryVideoView(frame: frame, id: viewId, args: args, messenger: messenger)
  }
}
final class MemoryVideoView: NSObject, FlutterPlatformView {
  private static weak var current: MemoryVideoView?
  private let surface: MemoryPlayerSurface
  private let channel: FlutterMethodChannel
  private var source: MemoryVideoSource?
  private var asset: AVURLAsset?
  private var player: AVPlayer?
  private var background: NSObjectProtocol?
  private var disposed = false
  private var failed = false
  init(frame: CGRect, id: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
    surface = MemoryPlayerSurface(frame: frame)
    channel = FlutterMethodChannel(name: "au.fintex.sanjaal/memory-video/\(id)", binaryMessenger: messenger)
    super.init()
    Self.current?.dispose()
    Self.current = self
    surface.backgroundColor = .black
    surface.playerLayer.videoGravity = .resizeAspect
    if let args = args as? [String: Any], let value = args["bytes"] as? FlutterStandardTypedData,
       value.data.count > 0, value.data.count <= 25 * 1024 * 1024,
       let kind = args["type"] as? String, ["mp4", "mov"].contains(kind) {
      let source = MemoryVideoSource(bytes: value.data, type: kind == "mov" ? "com.apple.quicktime-movie" : "public.mpeg-4")
      // A fixed non-network URL whose bytes only this loader can supply.
      let asset = AVURLAsset(url: URL(string: "sanjaal-memory://preview/video.\(kind)")!)
      asset.resourceLoader.setDelegate(source, queue: .main)
      self.source = source; self.asset = asset
      let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
      player.actionAtItemEnd = .pause
      self.player = player; surface.playerLayer.player = player
    } else { failed = true }
    background = NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.player?.pause() }
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "state":
        let item = self.player?.currentItem
        let ready = item?.status == .readyToPlay && !self.disposed
        let size = item?.presentationSize ?? .zero
        if item?.status == .failed { self.failed = true; self.releasePlayer() }
        result(["ready": ready, "failed": self.failed, "playing": self.player?.rate != 0 && self.player != nil,
                "position": Int((self.player?.currentTime().seconds ?? 0).isFinite ? max(0, self.player?.currentTime().seconds ?? 0) * 1000 : 0),
                "width": size.width, "height": size.height])
      case "play":
        if !self.disposed, self.player?.currentItem?.status == .readyToPlay {
          let now = self.player!.currentTime().seconds
          let end = self.player!.currentItem!.duration.seconds
          if end.isFinite && now >= end - 0.05 { self.player?.seek(to: .zero) }
          self.player?.play()
        }
        result(nil)
      case "pause": self.player?.pause(); result(nil)
      case "dispose": self.dispose(); result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }
  func view() -> UIView { surface }
  private func releasePlayer() {
    player?.pause(); surface.playerLayer.player = nil
    player?.replaceCurrentItem(with: nil); player = nil
    asset?.cancelLoading(); asset?.resourceLoader.setDelegate(nil, queue: nil); asset = nil
    source?.clear(); source = nil
    surface.isHidden = true
  }
  private func dispose() {
    if disposed { return }; disposed = true
    releasePlayer(); channel.setMethodCallHandler(nil)
    if let observer = background { NotificationCenter.default.removeObserver(observer); background = nil }
  }
  deinit { releasePlayer(); if let observer = background { NotificationCenter.default.removeObserver(observer) } }
}
