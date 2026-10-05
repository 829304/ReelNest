import Cocoa
import FlutterMacOS

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

    super.awakeFromNib()
  }
}
