import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions) {
    guard NativeCallEngine.enabled else {
      super.scene(scene, willConnectTo: session, options: connectionOptions); return
    }
    guard let scene = scene as? UIWindowScene,
      let app = UIApplication.shared.delegate as? AppDelegate,
      let controller = app.callEngine.controller() else { return }
    let value = UIWindow(windowScene: scene)
    value.rootViewController = controller
    window = value
    // FlutterSceneDelegate associates this one root engine with its scene.
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    value.makeKeyAndVisible()
  }
}
