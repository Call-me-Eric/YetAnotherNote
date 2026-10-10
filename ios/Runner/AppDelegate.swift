import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    ApplePencilSideButton.shared.register(messenger: engineBridge.applicationRegistrar.messenger())
    DispatchQueue.main.async {
      ApplePencilSideButton.shared.attachToForeground(UIApplication.shared)
    }
  }
}

/// iOS adapter for [StylusSideButton]. Apple Pencil Pro squeeze is reported
/// as a side-button press. The channel method is `sideButton`.
final class ApplePencilSideButton {
  static let shared = ApplePencilSideButton()

  var channel: FlutterMethodChannel?
  private var squeezeRelay: AnyObject?

  func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "dev.yetanotherpage/stylus", binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { call, result in
      if call.method == "selectionHaptic" {
        ApplePencilSideButton.playSelectionHaptic(call.arguments)
        result(nil)
        return
      }
      result(FlutterMethodNotImplemented)
    }
    NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { _ in
      ApplePencilSideButton.shared.attachToForeground(UIApplication.shared)
    }
  }

  func attachToForeground(_ application: UIApplication) {
    for scene in application.connectedScenes {
      guard let windowScene = scene as? UIWindowScene else { continue }
      for window in windowScene.windows {
        attach(window: window)
      }
    }
  }

  func attach(window: UIWindow?) {
    guard let view = window?.rootViewController?.view else { return }
    if view.interactions.contains(where: { $0 is UIPencilInteraction }) { return }
    let relay = PencilRelay()
    squeezeRelay = relay
    let interaction = UIPencilInteraction()
    interaction.delegate = relay
    view.addInteraction(interaction)
  }

  static func playSelectionHaptic(_ arguments: Any?) {
    guard #available(iOS 17.5, *) else { return }
    let point = hapticPoint(arguments)
    let generator = UICanvasFeedbackGenerator()
    generator.prepare()
    generator.alignmentOccurred(at: point)
  }

  private static func hapticPoint(_ arguments: Any?) -> CGPoint {
    guard let map = arguments as? [String: Any],
          let x = map["x"] as? Double,
          let y = map["y"] as? Double else {
      return .zero
    }
    return CGPoint(x: x, y: y)
  }
}

final class PencilRelay: NSObject, UIPencilInteractionDelegate {
  func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
    ApplePencilSideButton.shared.channel?.invokeMethod("doubleTap", arguments: nil)
  }

  @available(iOS 17.5, *)
  func pencilInteraction(
    _ interaction: UIPencilInteraction,
    didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze
  ) {
    guard squeeze.phase == .ended else { return }
    var args: [String: Double] = [:]
    if let pose = squeeze.hoverPose {
      args["x"] = pose.location.x
      args["y"] = pose.location.y
    }
    ApplePencilSideButton.shared.channel?.invokeMethod("sideButton", arguments: args)
  }
}
