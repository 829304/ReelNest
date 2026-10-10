import Cocoa
import FlutterMacOS
import desktop_multi_window

private class PlaybackSleepPlugin: NSObject, FlutterPlugin {
  private var activity: NSObjectProtocol?
  static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = PlaybackSleepPlugin()
    let channel = FlutterMethodChannel(name: "reelnest/playback_sleep", binaryMessenger: registrar.messenger)
    registrar.addMethodCallDelegate(plugin, channel: channel)
  }
  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "setActive" else { result(FlutterMethodNotImplemented); return }
    guard let active = call.arguments as? Bool else {
      result(FlutterError(code: "invalid_argument", message: "Expected boolean", details: nil)); return
    }
    if active, activity == nil {
      activity = ProcessInfo.processInfo.beginActivity(
        options: [.idleDisplaySleepDisabled, .idleSystemSleepDisabled],
        reason: "ReelNest 正在播放视频")
    } else if !active { releaseActivity() }
    result(nil)
  }
  private func releaseActivity() {
    if let activity { ProcessInfo.processInfo.endActivity(activity) }
    activity = nil
  }
  deinit { releaseActivity() }
}

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    // ContentView.MainWindowToolbarVisibilityGuard.minimumContentSize.
    self.contentMinSize = NSSize(width: 1088, height: 720)
    let contentSize = self.contentRect(forFrameRect: self.frame).size
    self.setContentSize(NSSize(
      width: max(contentSize.width, 1088), height: max(contentSize.height, 720)))

    RegisterGeneratedPlugins(registry: flutterViewController)
    PlaybackSleepPlugin.register(with: flutterViewController.registrar(forPlugin: "ReelNestPlaybackSleep"))
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      RegisterGeneratedPlugins(registry: controller)
      PlaybackSleepPlugin.register(with: controller.registrar(forPlugin: "ReelNestPlaybackSleep"))
    }

    super.awakeFromNib()
  }
}
