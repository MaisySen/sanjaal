import Foundation

/// Push metadata is a presentation hint, never an authenticated action/media grant.
struct CallWakeEnvelope {
  let recipient: String
  let call: UUID
  let conversation: UUID
  let video: Bool
  let expiresAt: Date

  static func parse(_ data: [AnyHashable: Any], owner: String, now: Date = Date()) -> CallWakeEnvelope? {
    guard data["type"] as? String == "incoming_call", data["call_version"] as? String == "1",
      let recipient = data["recipient"] as? String, UUID(uuidString: recipient) != nil,
      recipient.lowercased() == owner.lowercased(),
      let callText = data["call"] as? String, let call = UUID(uuidString: callText),
      let conversationText = data["conversation"] as? String, let conversation = UUID(uuidString: conversationText),
      let kind = data["kind"] as? String, ["voice", "video"].contains(kind),
      let issuedText = data["issued_at"] as? String, let issued = Int64(issuedText),
      let expiresText = data["expires_at"] as? String, let expires = Int64(expiresText) else { return nil }
    let seconds = Int64(now.timeIntervalSince1970)
    // Bound before arithmetic, including malformed integer extremes.
    guard issued <= seconds + 5, issued >= seconds - 40,
      expires > seconds, expires <= seconds + 45, expires - issued == 40 else { return nil }
    return CallWakeEnvelope(recipient: recipient.lowercased(), call: call,
      conversation: conversation, video: kind == "video", expiresAt: Date(timeIntervalSince1970: TimeInterval(expires)))
  }
}
