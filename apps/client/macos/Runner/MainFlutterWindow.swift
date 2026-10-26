import Cocoa
import FlutterMacOS
import desktop_multi_window

private class ExternalPlayerPlugin: NSObject, FlutterPlugin {
  private static let players = [
    ("IINA", "com.colliderli.iina", "/Applications/IINA.app"),
    ("VLC", "org.videolan.vlc", "/Applications/VLC.app"),
    ("Movist Pro", "com.movist.MovistPro", "/Applications/Movist Pro.app"),
    ("QuickTime Player", "com.apple.QuickTimePlayerX", "/System/Applications/QuickTime Player.app")
  ]
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "reelnest/external_player", binaryMessenger: registrar.messenger)
    registrar.addMethodCallDelegate(ExternalPlayerPlugin(), channel: channel)
  }
  private func available() -> [(String, URL)] {
    return Self.players.compactMap { name, identifier, fallback in
      let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) ?? URL(fileURLWithPath: fallback)
      return FileManager.default.fileExists(atPath: url.path) ? (name, url) : nil
    }
  }
  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "availablePlayers" {
      result(available().map { ["name": $0.0, "path": $0.1.path] })
      return
    }
    guard call.method == "open", let args = call.arguments as? [String: Any], let location = args["location"] as? String else {
      result(FlutterMethodNotImplemented)
      return
    }
    let remote = URL(string: location).map { ["http", "https"].contains($0.scheme?.lowercased() ?? "") } ?? false
    let media = remote ? URL(string: location)! : URL(fileURLWithPath: location)
    if !remote && !FileManager.default.fileExists(atPath: media.path) {
      result(FlutterError(code: "media_missing", message: "Media unavailable", details: nil))
      return
    }
    let workspace = NSWorkspace.shared
    let application: URL?
    if let path = args["applicationPath"] as? String, !path.isEmpty {
      application = URL(fileURLWithPath: path)
    } else if remote, let known = available().first {
      application = known.1
    } else {
      application = workspace.urlForApplication(toOpen: media)
    }
    guard let app = application, app.resolvingSymlinksInPath().standardizedFileURL != Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL else {
      result(FlutterError(code: "application_missing", message: "External application unavailable", details: nil))
      return
    }
    workspace.open([media], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { application, error in
      DispatchQueue.main.async {
        if application != nil && error == nil { result(nil) }
        else { result(FlutterError(code: "launch_failed", message: "External application launch failed", details: nil)) }
      }
    }
  }
}

/// Keep resolved URLs alive in the engine which owns the decoder. Bookmark
/// bytes cross engines in memory and are never written to user defaults/files.
private class TransientFileAccessPlugin: NSObject, FlutterPlugin {
  private var leases: [String: (URL, Bool)] = [:]
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "reelnest/transient_file_access", binaryMessenger: registrar.messenger)
    registrar.addMethodCallDelegate(TransientFileAccessPlugin(), channel: channel)
  }
  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    if call.method == "release", let token = args["token"] as? String {
      if let lease = leases.removeValue(forKey: token), lease.1 { lease.0.stopAccessingSecurityScopedResource() }
      result(nil)
      return
    }
    guard call.method == "acquire", let path = args["path"] as? String else {
      result(FlutterMethodNotImplemented)
      return
    }
    do {
      var url = URL(fileURLWithPath: path).standardizedFileURL
      if let data = args["bookmark"] as? FlutterStandardTypedData {
        var stale = false
        let resolved = try URL(resolvingBookmarkData: data.data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale).standardizedFileURL
        guard resolved.isFileURL, resolved.path == url.path else {
          result(FlutterError(code: "file_access_denied", message: "File access denied", details: nil))
          return
        }
        url = resolved
      }
      let started = url.startAccessingSecurityScopedResource()
      guard started || FileManager.default.isReadableFile(atPath: url.path) else {
        result(FlutterError(code: "file_access_denied", message: "File access denied", details: nil))
        return
      }
      do {
        let data = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        let token = UUID().uuidString
        leases[token] = (url, started)
        result(["token": token, "bookmark": FlutterStandardTypedData(bytes: data)])
      } catch {
        if started { url.stopAccessingSecurityScopedResource() }
        throw error
      }
    } catch {
      result(FlutterError(code: "file_access_denied", message: "File access denied", details: nil))
    }
  }
  deinit {
    for lease in leases.values where lease.1 { lease.0.stopAccessingSecurityScopedResource() }
  }
}

private class SubtitleFontsPlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "reelnest/subtitle_fonts", binaryMessenger: registrar.messenger)
    registrar.addMethodCallDelegate(SubtitleFontsPlugin(), channel: channel)
  }
  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "families" else { result(FlutterMethodNotImplemented); return }
    result(NSFontManager.shared.availableFontFamilies)
  }
}

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
    ExternalPlayerPlugin.register(with: flutterViewController.registrar(forPlugin: "ReelNestExternalPlayer"))
    TransientFileAccessPlugin.register(with: flutterViewController.registrar(forPlugin: "ReelNestTransientFileAccess"))
    PlaybackSleepPlugin.register(with: flutterViewController.registrar(forPlugin: "ReelNestPlaybackSleep"))
    SubtitleFontsPlugin.register(with: flutterViewController.registrar(forPlugin: "ReelNestSubtitleFonts"))
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      RegisterGeneratedPlugins(registry: controller)
      ExternalPlayerPlugin.register(with: controller.registrar(forPlugin: "ReelNestExternalPlayer"))
      TransientFileAccessPlugin.register(with: controller.registrar(forPlugin: "ReelNestTransientFileAccess"))
      PlaybackSleepPlugin.register(with: controller.registrar(forPlugin: "ReelNestPlaybackSleep"))
      SubtitleFontsPlugin.register(with: controller.registrar(forPlugin: "ReelNestSubtitleFonts"))
    }

    super.awakeFromNib()
  }
}
