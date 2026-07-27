import AppKit
import InputMethodKit

var server: IMKServer!

@objc(BomiApplication)
final class BomiApplication: NSApplication {
    private let appDelegate = AppDelegate()
    override init() {
        super.init()
        self.delegate = appDelegate
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let name = Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String else {
            fatalError("Info.plist is missing a string value for 'InputMethodConnectionName'")
        }
        server = IMKServer(name: name, bundleIdentifier: Bundle.main.bundleIdentifier)
    }
}

let app = BomiApplication.shared
app.run()
