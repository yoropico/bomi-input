import Foundation

/// File logging for the IME process.
///
/// **Why a file and not `os_log`/`NSLog`:** this process runs as a background
/// input method and nothing it writes to the unified log ever shows up in
/// Console.app or `log stream`. Every real bug in this IME was found by writing
/// to a file instead, so that capability lives here permanently rather than
/// being re-added and deleted each time.
///
/// Silent unless the switch file exists, so a shipped build logs nothing:
///
///     touch /tmp/bomi-debug.on && killall Bomi   # enable (IME relaunches on next keystroke)
///     rm /tmp/bomi-debug.on && killall Bomi      # disable
///
/// The switch is read **once** at startup: `handle(_:client:)` runs on every
/// keystroke, and a `stat()` per event is not free.
///
/// Everything here is `nonisolated`: the target's default isolation is
/// `MainActor`, but the log is also written from `handle(_:client:)` before the
/// hop onto the main actor.
nonisolated enum DebugLog {
    private static let switchPath = "/tmp/bomi-debug.on"
    private static let logPath = "/tmp/bomi-debug.log"

    static let isEnabled = FileManager.default.fileExists(atPath: switchPath)

    /// Writes are serialized off the input thread — logging must never add
    /// latency to a keystroke.
    private static let queue = DispatchQueue(label: "com.bomi.debuglog", qos: .utility)

    /// The message is a **non-escaping** `@autoclosure`: it is evaluated on the
    /// calling thread (so it may read main-actor state such as `mode`) and only
    /// the finished string crosses onto the writer queue. Making it `@escaping`
    /// would make it `@Sendable`, and then nothing actor-isolated could be logged.
    /// Non-escaping also means the interpolation is skipped entirely when off.
    static func log(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let at = Date()
        let text = message()
        let path = logPath
        queue.async {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss.SSS"
            guard let data = "\(f.string(from: at)) \(text)\n".data(using: .utf8) else { return }
            if let h = FileHandle(forWritingAtPath: path) {
                h.seekToEndOfFile()
                h.write(data)
                try? h.close()
            } else {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
    }
}
