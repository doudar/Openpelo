import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    configureNativeFilePicker(flutterViewController)

    super.awakeFromNib()
  }

  private func configureNativeFilePicker(_ flutterViewController: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "openpelo/native_file_picker",
      binaryMessenger: flutterViewController.engine.binaryMessenger)

    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "pickApk" else {
        result(FlutterMethodNotImplemented)
        return
      }

      DispatchQueue.main.async {
        let panel = NSOpenPanel()
        panel.title = "Select APK to install"
        panel.prompt = "Install"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = ["apk"]
        panel.allowsOtherFileTypes = false

        if let window = self {
          panel.beginSheetModal(for: window) { response in
            result(response == .OK ? panel.url?.path : nil)
          }
        } else {
          result(panel.runModal() == .OK ? panel.url?.path : nil)
        }
      }
    }
  }
}
