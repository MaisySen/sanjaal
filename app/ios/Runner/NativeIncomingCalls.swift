import Foundation
import CallKit
import PushKit
import AVFoundation
import Flutter

/// Native process-owned call UI. No API credentials or network actions live here.
/// Not constructed/registered by AppDelegate until the complete integration is reviewed.
final class NativeIncomingCalls: NSObject, PKPushRegistryDelegate, CXProviderDelegate {
  private let defaults: UserDefaults
  private let provider: CXProvider
  private var registry: PKPushRegistry?
  private var channel: FlutterMethodChannel?
  private var current: CallWakeEnvelope?
  private var expiry: DispatchWorkItem?
  private var queued: [[String: Any]] = []
  private var answer: CXAnswerCallAction?
  private var end: CXEndCallAction?
  private var owner: String?
  private var generation: String?
  private var seen = Set<UUID>()
  private var claimed = Set<String>()
  private var token: String?
  private var active = false
  private var connected = false
  var wakeEngine: (() -> Void)?
  // Enabling must be acknowledged by the pinned native SDK. Disabling before
  // engine creation may be deferred there, but enabling may never be assumed.
  var audioAvailability: ((Bool) -> Bool)?

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    let config = CXProviderConfiguration()
    config.supportsVideo = true
    config.maximumCallGroups = 1
    config.maximumCallsPerCallGroup = 1
    config.supportedHandleTypes = [.generic]
    config.includesCallsInRecents = false
    provider = CXProvider(configuration: config)
    owner = defaults.string(forKey: "sanjaal.call.owner")
    generation = defaults.string(forKey: "sanjaal.call.generation")
    super.init()
    provider.setDelegate(self, queue: .main)
  }

  /// Provider registration is explicit. Merely linking this file does not register.
  func activate() {
    guard !active else { return }
    active = true
    _ = audioAvailability?(false)
    let value = PKPushRegistry(queue: .main)
    value.delegate = self
    value.desiredPushTypes = [.voIP]
    registry = value
  }

  func attach(_ messenger: FlutterBinaryMessenger) {
    let value = FlutterMethodChannel(name: "au.fintex.sanjaal/incoming-calls", binaryMessenger: messenger)
    channel = value
    value.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      let args = call.arguments as? [String: Any] ?? [:]
      if ["drain", "claim", "acknowledge"].contains(call.method) &&
          (args["owner"] as? String != self.owner || args["generation"] as? String != self.generation) {
        result(FlutterError(code: "STALE_OWNER", message: "Call account binding changed.", details: nil)); return
      }
      switch call.method {
      case "bind":
        guard let owner = args["owner"] as? String, UUID(uuidString: owner) != nil,
          let generation = args["generation"] as? String, UUID(uuidString: generation) != nil else {
          result(FlutterError(code: "INVALID_OWNER", message: "Call account binding is invalid.", details: nil)); return
        }
        if self.owner != owner.lowercased() || self.generation != generation { self.reset(reason: .failed); self.claimed.removeAll(); self.seen.removeAll() }
        self.owner = owner.lowercased(); self.generation = generation
        self.defaults.set(self.owner, forKey: "sanjaal.call.owner")
        self.defaults.set(generation, forKey: "sanjaal.call.generation")
        var response: [String: Any] = ["registered": self.active]
        if let token = self.token { response["token"] = token }
        result(response)
      case "clear":
        self.reset(reason: .failed); self.claimed.removeAll(); self.seen.removeAll(); self.owner = nil; self.generation = nil
        self.defaults.removeObject(forKey: "sanjaal.call.owner")
        self.defaults.removeObject(forKey: "sanjaal.call.generation")
        result(nil)
      case "drain":
        result(self.queued)
      case "claim":
        guard let id = args["event_id"] as? String, self.queued.contains(where: { $0["event_id"] as? String == id }),
          !self.claimed.contains(id), self.claimed.count < 320 else { result(false); return }
        self.claimed.insert(id); result(true)
      case "acknowledge":
        guard let id = args["event_id"] as? String else { result(false); return }
        self.queued.removeAll { $0["event_id"] as? String == id }; result(true)
      case "complete":
        guard let id = args["call"] as? String, self.current?.call.uuidString.lowercased() == id.lowercased(),
          args["generation"] as? String == self.generation else { result(false); return }
        if args["connected"] as? Bool == true {
          self.answer?.fulfill(); self.answer = nil; self.expiry?.cancel(); self.connected = true
          result(true)
        } else {
          self.answer?.fail(); self.answer = nil
          self.end?.fulfill(); self.end = nil
          self.reset(reason: .failed); result(true)
        }
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  private func emit(_ action: String, envelope: CallWakeEnvelope) {
    let id = "\(envelope.call.uuidString.lowercased()):\(action)"
    guard !queued.contains(where: { $0["event_id"] as? String == id }) else { return }
    let event: [String: Any] = ["event_id": id, "action": action, "recipient": envelope.recipient,
      "call": envelope.call.uuidString.lowercased(), "conversation": envelope.conversation.uuidString.lowercased(),
      "kind": envelope.video ? "video" : "voice", "expires_at": Int(envelope.expiresAt.timeIntervalSince1970),
      "generation": generation ?? ""]
    if queued.count < 8 { queued.append(event) }
    channel?.invokeMethod("changed", arguments: nil)
    wakeEngine?()
  }

  func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType) {
    guard type == .voIP else { return }
    token = credentials.token.map { String(format: "%02x", $0) }.joined()
    channel?.invokeMethod("tokenChanged", arguments: token)
  }
  func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
    token = nil; channel?.invokeMethod("tokenChanged", arguments: nil)
  }
  func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType, completion: @escaping () -> Void) {
    guard type == .voIP else { completion(); return }
    let openedOwner = owner
    let openedGeneration = generation
    let envelope = CallWakeEnvelope.parse(payload.dictionaryPayload, owner: owner ?? "")
    // Every VoIP callback is reported promptly, before any network/Flutter work.
    // Invalid or duplicate requests are immediately ended after reporting.
    let candidate = envelope?.call
    let duplicate = candidate.map { seen.contains($0) || current?.call == $0 } ?? false
    let id = duplicate ? UUID() : (candidate ?? UUID())
    let update = CXCallUpdate()
    update.remoteHandle = CXHandle(type: .generic, value: "Sanjaal call")
    update.localizedCallerName = "Sanjaal"
    update.hasVideo = envelope?.video ?? false
    update.supportsHolding = false; update.supportsGrouping = false; update.supportsUngrouping = false
    let leaseMatches = payload.dictionaryPayload["login_lease"] as? String == generation && generation != nil
    let accepted = leaseMatches && envelope != nil && current == nil && candidate == id && !seen.contains(id) && seen.count < 64
    provider.reportNewIncomingCall(with: id, update: update) { [weak self] error in
      guard let self = self else { completion(); return }
      defer { completion() }
      guard error == nil else { return }
      guard accepted, let envelope = envelope, envelope.expiresAt > Date(), self.current == nil,
        self.owner == openedOwner, self.generation == openedGeneration else {
        self.provider.reportCall(with: id, endedAt: Date(), reason: .failed); return
      }
      self.seen.insert(id)
      self.current = envelope
      let expiry = DispatchWorkItem { [weak self] in self?.reset(reason: .unanswered) }
      self.expiry = expiry
      DispatchQueue.main.asyncAfter(deadline: .now() + max(0, envelope.expiresAt.timeIntervalSinceNow), execute: expiry)
      self.emit("incoming", envelope: envelope)
    }
  }

  func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    guard let envelope = current, envelope.call == action.callUUID, envelope.expiresAt > Date(), answer == nil else {
      action.fail(); return
    }
    answer = action
    emit("answer", envelope: envelope)
    // Fulfilled only after exact authenticated state and media connection.
  }
  func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    guard let envelope = current, envelope.call == action.callUUID else { action.fulfill(); return }
    end = action
    emit(connected ? "end" : "decline", envelope: envelope)
    answer?.fail(); answer = nil
    action.fulfill(); end = nil
    reset(reason: .remoteEnded, keepEvents: true)
  }
  func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
    action.fail(); reset(reason: .failed)
  }
  func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
    guard audioAvailability?(true) == true else { reset(reason: .failed); return }
  }
  func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) { _ = audioAvailability?(false) }
  func providerDidReset(_ provider: CXProvider) { reset(reason: .failed) }
  private func reset(reason: CXCallEndedReason, keepEvents: Bool = false) {
    expiry?.cancel(); expiry = nil
    answer?.fail(); answer = nil; end?.fail(); end = nil
    if let envelope = current { provider.reportCall(with: envelope.call, endedAt: Date(), reason: reason) }
    current = nil; connected = false
    if !keepEvents { queued.removeAll() }
    _ = audioAvailability?(false)
  }
}
