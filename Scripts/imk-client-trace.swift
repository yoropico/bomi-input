#!/usr/bin/env swift
//
// Record what an input method actually sends a text client.
//
// Why this exists: three fixes for the Apple Mail recipient bug failed in a row,
// and every one of them reasoned about our own side of the boundary. Bomi's debug
// log shows what Bomi sends; the client probe shows what the field ends up
// holding. Neither can say how that differs from what Apple's own Korean input
// method sends, and after 2026-08-24 that difference is the whole question:
// typing 김형린 into Mail's To: field, Apple 2-Set resolves the right contact and
// Bomi offers 김상태 until the last syllable is committed.
//
// So this puts a plain NSTextView behind a logging NSTextInputClient and prints
// every call. Type the same text with each input method and diff the two traces;
// the first line that differs is the thing to fix.
//
//     swift Scripts/imk-client-trace.swift
//
// Type into the window, switch input source, type again. Ctrl-C to stop.
// Output is one line per call, with the field's full contents after it.
//
import AppKit

final class TracingTextView: NSTextView {
    private let start = Date()

    private func stamp() -> String {
        String(format: "%7.3f", Date().timeIntervalSince(start))
    }

    private func describe(_ r: NSRange) -> String {
        r.location == NSNotFound ? "none" : "\(r.location)+\(r.length)"
    }

    /// Printed after every call so the trace shows the resulting state, the same
    /// shape as Bomi's own CLIENT[...] probe lines.
    private func state() -> String {
        "text='\(string)' sel=\(describe(selectedRange())) marked=\(describe(markedRange()))"
    }

    private func trace(_ call: String) {
        print("\(stamp()) \(call)")
        print("          -> \(state())")
        fflush(stdout)
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        trace("insertText '\(string)' replacementRange=\(describe(replacementRange))")
        super.insertText(string, replacementRange: replacementRange)
        trace("  (after insertText)")
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        trace("setMarkedText '\(string)' selectedRange=\(describe(selectedRange)) "
              + "replacementRange=\(describe(replacementRange))")
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        trace("  (after setMarkedText)")
    }

    override func unmarkText() {
        trace("unmarkText")
        super.unmarkText()
        trace("  (after unmarkText)")
    }

    /// The completion path Mail's recipient field rides on. NSTextView refuses to
    /// complete while marked text exists (`rangeForUserCompletion` returns none),
    /// so seeing WHEN this turns into a real range is half the answer.
    override var rangeForUserCompletion: NSRange {
        let r = super.rangeForUserCompletion
        trace("rangeForUserCompletion asked -> \(describe(r))")
        return r
    }

    override func doCommand(by selector: Selector) {
        trace("doCommand \(NSStringFromSelector(selector))")
        super.doCommand(by: selector)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ note: Notification) {
        let frame = NSRect(x: 0, y: 0, width: 560, height: 160)
        window = NSWindow(contentRect: frame,
                          styleMask: [.titled, .closable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "IMK client trace — type here"

        let view = TracingTextView(frame: frame)
        view.isAutomaticTextCompletionEnabled = true
        view.font = NSFont.systemFont(ofSize: 24)
        window.contentView = view
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        view.window?.makeFirstResponder(view)

        print("# ready — type the same text with each input source, Ctrl-C to stop")
        fflush(stdout)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
