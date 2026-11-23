import Flutter
import UIKit

/// One process engine for both headless call wake and the later scene. Disabled
/// until native compilation, full root ownership and physical acceptance review.
/// Never create a second engine as a fallback to a failed/adopted engine.
final class NativeCallEngine {
  static let enabled = false
  private var engine: FlutterEngine?
  private var failed = false
  private var configured = false
  var configure: ((FlutterEngine) -> Void)?
  var ready: Bool { Self.enabled && engine != nil && configured && !failed }

  func ensure() -> FlutterEngine? {
    precondition(Thread.isMainThread)
    guard Self.enabled, !failed else { return nil }
    if let engine = engine { return engine }
    let created = FlutterEngine(name: "sanjaal-process-call", project: nil, allowHeadlessExecution: true)
    engine = created // Publish identity before plugin callbacks can reenter.
    guard created.run() else {
      engine = nil; failed = true; return nil
    }
    if !configured {
      configured = true
      configure?(created)
    }
    return created
  }

  func controller() -> FlutterViewController? {
    guard let engine = ensure() else { return nil }
    // A connected scene retains its view controller. Returning another here
    // would silently detach foreground UI from the same engine.
    if let existing = engine.viewController { return existing }
    return FlutterViewController(engine: engine, nibName: nil, bundle: nil)
  }
}
