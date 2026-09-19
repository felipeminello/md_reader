import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Give the app delegate a channel to the engine so files opened from
    // Finder can be pushed to the Flutter side.
    (NSApp.delegate as? AppDelegate)?.registerFileOpenChannel(with: flutterViewController)

    super.awakeFromNib()
  }
}
