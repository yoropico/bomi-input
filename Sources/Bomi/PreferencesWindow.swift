import AppKit
import BomiCore

/// The "Bomi 설정" window: toggle-key picker plus the per-app default-input table.
/// Lives in the IME process (no separate settings app). Requires `LSUIElement`
/// rather than `LSBackgroundOnly` in Info.plist — a background-only process can
/// never bring a window forward.
final class PreferencesWindow: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    static let shared = PreferencesWindow()

    private let prefs = Preferences.shared
    private var rows: [(bundleID: String, mode: InputMode)] = []
    private var window: NSWindow!
    private let table = NSTableView()
    private let togglePopup = NSPopUpButton(frame: .zero, pullsDown: false)

    func show() {
        if window == nil { build() }
        reload()
        // Sync the toggle popup with what is stored (may have changed via `defaults`).
        let current = prefs.toggleKeyCode
        togglePopup.selectItem(at: Preferences.toggleKeyChoices.firstIndex { $0.keyCode == current } ?? 0)
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func reload() {
        rows = prefs.allDefaultModes()
        table.reloadData()
    }

    private func build() {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 340))

        // Toggle key row.
        let toggleLabel = NSTextField(labelWithString: "한/영 전환 키:")
        toggleLabel.frame = NSRect(x: 20, y: 300, width: 100, height: 20)
        togglePopup.frame = NSRect(x: 120, y: 296, width: 180, height: 26)
        for choice in Preferences.toggleKeyChoices { togglePopup.addItem(withTitle: choice.name) }
        togglePopup.target = self
        togglePopup.action = #selector(toggleKeyChanged(_:))
        content.addSubview(toggleLabel)
        content.addSubview(togglePopup)

        // Per-app table.
        let appLabel = NSTextField(labelWithString: "앱별 기본 입력 (앱으로 전환할 때마다 적용)")
        appLabel.frame = NSRect(x: 20, y: 262, width: 400, height: 20)
        content.addSubview(appLabel)

        let appCol = NSTableColumn(identifier: .init("app"))
        appCol.title = "번들 ID (더블클릭해 편집)"
        appCol.width = 300
        let modeCol = NSTableColumn(identifier: .init("mode"))
        modeCol.title = "기본 입력"
        modeCol.width = 90
        table.addTableColumn(appCol)
        table.addTableColumn(modeCol)
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 22
        let scroll = NSScrollView(frame: NSRect(x: 20, y: 56, width: 400, height: 200))
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        content.addSubview(scroll)

        // +/- buttons.
        let add = NSButton(title: "+", target: self, action: #selector(addApp(_:)))
        add.frame = NSRect(x: 20, y: 20, width: 32, height: 28)
        let remove = NSButton(title: "−", target: self, action: #selector(removeApp(_:)))
        remove.frame = NSRect(x: 54, y: 20, width: 32, height: 28)
        content.addSubview(add)
        content.addSubview(remove)

        window = NSWindow(contentRect: content.frame, styleMask: [.titled, .closable],
                          backing: .buffered, defer: false)
        window.title = "Bomi 설정"
        window.contentView = content
        window.isReleasedWhenClosed = false
    }

    // MARK: actions

    @objc private func toggleKeyChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        guard Preferences.toggleKeyChoices.indices.contains(idx) else { return }
        prefs.setToggleKeyCode(Preferences.toggleKeyChoices[idx].keyCode)
    }

    /// Menu of running apps (the ones a user would pin) not already in the table.
    @objc private func addApp(_ sender: NSButton) {
        let listed = Set(rows.map(\.bundleID))
        let menu = NSMenu()
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> (String, String)? in
                guard let id = app.bundleIdentifier, !listed.contains(id), id != Bundle.main.bundleIdentifier
                else { return nil }
                return (app.localizedName ?? id, id)
            }
            .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
        for (name, id) in apps {
            let item = NSMenuItem(title: name, action: #selector(addSelectedApp(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = id
            menu.addItem(item)
        }
        if !apps.isEmpty { menu.addItem(.separator()) }
        let manual = NSMenuItem(title: "번들 ID 직접 입력…", action: #selector(addManualApp(_:)), keyEquivalent: "")
        manual.target = self
        menu.addItem(manual)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
    }

    @objc private func addSelectedApp(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        prefs.setDefaultMode(.roman, forApp: id)   // English is the common reason to pin an app
        reload()
        if let i = rows.firstIndex(where: { $0.bundleID == id }) {
            table.selectRowIndexes([i], byExtendingSelection: false)
        }
    }

    /// Adds a placeholder row and puts the cursor in its bundle-id field.
    @objc private func addManualApp(_ sender: NSMenuItem) {
        var id = "com.example.app"
        var n = 1
        while rows.contains(where: { $0.bundleID == id }) { n += 1; id = "com.example.app\(n)" }
        prefs.setDefaultMode(.roman, forApp: id)
        reload()
        if let i = rows.firstIndex(where: { $0.bundleID == id }) {
            table.selectRowIndexes([i], byExtendingSelection: false)
            table.editColumn(0, row: i, with: nil, select: true)
        }
    }

    @objc private func removeApp(_ sender: NSButton) {
        let i = table.selectedRow
        guard rows.indices.contains(i) else { return }
        prefs.setDefaultMode(nil, forApp: rows[i].bundleID)
        reload()
    }

    @objc private func modeChanged(_ sender: NSPopUpButton) {
        let i = table.row(for: sender)
        guard rows.indices.contains(i) else { return }
        prefs.setDefaultMode(sender.indexOfSelectedItem == 0 ? .korean : .roman, forApp: rows[i].bundleID)
        reload()
    }

    // MARK: table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = rows[row]
        if tableColumn?.identifier.rawValue == "mode" {
            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            popup.addItems(withTitles: ["한글", "영어"])
            popup.selectItem(at: entry.mode == .korean ? 0 : 1)
            popup.target = self
            popup.action = #selector(modeChanged(_:))
            return popup
        }
        let name = NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == entry.bundleID }?.localizedName
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.bundleID)
                .map { FileManager.default.displayName(atPath: $0.path) }
        // Bundle id is typed directly (double-click): apps not running right now
        // can still be pinned, and a typo is fixed in place.
        let field = NSTextField(string: entry.bundleID)
        field.isBordered = false
        field.drawsBackground = false
        field.lineBreakMode = .byTruncatingMiddle
        field.placeholderString = "com.example.app"
        field.toolTip = name
        field.target = self
        field.action = #selector(bundleIDEdited(_:))
        return field
    }

    /// Rename the row's entry to what was typed, keeping its mode. Empty or
    /// duplicate ids are rejected by reverting the field.
    @objc private func bundleIDEdited(_ sender: NSTextField) {
        let i = table.row(for: sender)
        guard rows.indices.contains(i) else { return }
        let old = rows[i]
        let new = sender.stringValue.trimmingCharacters(in: .whitespaces)
        guard !new.isEmpty, new == old.bundleID || !rows.contains(where: { $0.bundleID == new }) else {
            sender.stringValue = old.bundleID
            return
        }
        guard new != old.bundleID else { return }
        prefs.setDefaultMode(nil, forApp: old.bundleID)
        prefs.setDefaultMode(old.mode, forApp: new)
        reload()
        if let j = rows.firstIndex(where: { $0.bundleID == new }) {
            table.selectRowIndexes([j], byExtendingSelection: false)
        }
    }
}
