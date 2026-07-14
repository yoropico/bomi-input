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
        let name = Bundle.main.infoDictionary?["InputMethodConnectionName"] as! String
        server = IMKServer(name: name, bundleIdentifier: Bundle.main.bundleIdentifier)
    }
}

let app = BomiApplication.shared
app.run()
