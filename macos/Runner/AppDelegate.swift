import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// Name of the channel shared with `SystemFileOpener` on the Dart side.
  private static let fileOpenChannelName = "md_reader/system_file_open"

  /// Channel used to hand files opened from Finder to the Flutter side.
  private var fileOpenChannel: FlutterMethodChannel?

  /// File macOS asked us to open before Flutter was ready to receive it.
  /// Only the latest one is kept: the reader shows a single document.
  private var pendingPath: String?

  /// Flipped once Dart has drained `pendingPath`; from then on paths are
  /// pushed through the channel instead of being buffered.
  private var isFlutterReady = false

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// Wires the channel to the engine. Called by `MainFlutterWindow` as soon as
  /// the `FlutterViewController` exists.
  func registerFileOpenChannel(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: AppDelegate.fileOpenChannelName,
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "getInitialFile" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let self = self else {
        result(nil)
        return
      }
      // Dart is listening now: hand over whatever arrived during launch.
      self.isFlutterReady = true
      result(self.pendingPath)
      self.pendingPath = nil
    }
    fileOpenChannel = channel
  }

  /// Documents opened from Finder ("Abrir com", double-click) arrive here on
  /// current macOS versions.
  override func application(_ application: NSApplication, open urls: [URL]) {
    // Keep forwarding to plugins that registered for app lifecycle events.
    super.application(application, open: urls)

    for url in urls where url.isFileURL {
      openFromSystem(path: url.path)
    }
  }

  /// Legacy Apple-event path, kept as a fallback for older macOS versions.
  override func application(_ sender: NSApplication, openFile filename: String) -> Bool {
    openFromSystem(path: filename)
    return true
  }

  private func openFromSystem(path: String) {
    guard isFlutterReady, let channel = fileOpenChannel else {
      // The engine is not up yet; Dart will ask for this on start-up.
      pendingPath = path
      return
    }
    channel.invokeMethod("openFile", arguments: path)
    // The app may already be running in the background when Finder hands us a
    // file, so bring it to the front with the new document.
    NSApp.activate(ignoringOtherApps: true)
  }
}
