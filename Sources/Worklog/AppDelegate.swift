import AppKit
import Combine
import SwiftUI
import WorklogCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = WorklogModel()
    private let nav = Navigation()
    private let tick = TickTickModel()
    private lazy var notes = NotesSync(store: model.store)
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var window: NSWindow?
    private var hotKey: HotKey?
    private var bag: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = Self.editMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Remembers where you Command-drag it, instead of landing leftmost (under the notch) each launch.
        statusItem.autosaveName = "WorklogStatusItem"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.imagePosition = .imageLeading
        updateStatus()

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PopoverView(
            model: model,
            tick: tick,
            notes: notes,
            openDay: { [weak self] in self?.openWindow(search: false) },
            openSearch: { [weak self] in self?.openWindow(search: true) },
            revealFolder: { [weak self] in self?.revealFolder() },
            openSettings: { [weak self] in self?.openSettings() }
        ))

        model.onLogged = { [weak self] text in
            if DayFile.tags(in: text).contains(NotesHTML.weeklyTag) { self?.notes.appendItem(text) }
        }
        if ProcessInfo.processInfo.environment["WORKLOG_SELFTEST"] == "1" {
            // Debug: exercise the real #weekly and week-summary paths against $WORKLOG_NOTE, then quit.
            model.log("Worklog self-test line #weekly", startTimer: false)
            notes.sendWeek(monday: NotesSync.monday(of: Date()))
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { NSApp.terminate(nil) }
        } else {
            notes.sendDueWeek()
        }

        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatus() }
            .store(in: &bag)

        // Debug: WORKLOG_SNAPSHOT=1 shows the popover content in a window for screenshots.
        if let path = ProcessInfo.processInfo.environment["WORKLOG_SNAPSHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.snapshotPopover(to: path) }
        }

        // Control Option L
        hotKey = HotKey(keyCode: 0x25, modifiers: HotKey.control | HotKey.option) { [weak self] in
            self?.togglePopover()
        }
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            model.reload()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func updateStatus() {
        guard let button = statusItem?.button else { return }
        // Icon only: the elapsed time lives in the popover, so the item stays narrow.
        button.title = ""
        button.image = NSImage(systemSymbolName: model.running.isEmpty ? "square.and.pencil" : "timer",
                               accessibilityDescription: "Worklog")
    }

    private func openWindow(search: Bool) {
        popover.performClose(nil)
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 860, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            w.title = "Worklog"
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(rootView: MainWindowView(model: model, nav: nav))
            w.setFrameAutosaveName("WorklogMain")
            if !w.setFrameUsingName("WorklogMain") { w.center() }
            window = w
        }
        if search {
            nav.focusSearch += 1
        } else {
            nav.query = ""
            nav.day = Calendar.current.startOfDay(for: Date())
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    private func openSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(tick: tick, notes: notes, root: model.store.root)))
            w.title = "Worklog Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            // A grouped Form has no intrinsic height; without this the window is just a title bar.
            w.setContentSize(NSSize(width: 480, height: 500))
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()
    }

    /// Shows the popover content in a plain window titled "Worklog Snapshot" so it can be screenshotted.
    private func snapshotPopover(to path: String) {
        guard let view = popover.contentViewController?.view else { return }
        popover.contentViewController = nil
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: view.fittingSize),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Worklog Snapshot"
        window.contentView = view
        window.center()
        window.orderFrontRegardless()
    }

    private func revealFolder() {
        popover.performClose(nil)
        try? FileManager.default.createDirectory(at: model.store.root, withIntermediateDirectories: true)
        NSWorkspace.shared.open(model.store.root)
    }

    /// Accessory apps have no menu bar, but key equivalents still route through the main menu:
    /// without this, copy, paste and undo do nothing in the editor.
    private static func editMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu()
        appItem.submenu?.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appItem.submenu?.addItem(withTitle: "Quit Worklog", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        return main
    }
}
