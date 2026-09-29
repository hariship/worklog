import AppKit
import Combine
import ServiceManagement
import SwiftUI
import WorklogCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
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
        NSApp.mainMenu = mainMenu()

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
        // Opened by you (Spotlight, Finder, Dock): show the window. At login: stay in the menu bar.
        let debug = ["WORKLOG_SELFTEST", "WORKLOG_SNAPSHOT", "WORKLOG_SIMULATE_SLEEP"]
            .contains { ProcessInfo.processInfo.environment[$0] != nil }
        if !launchedAtLogin && !debug {
            DispatchQueue.main.async { self.openWindow(search: false) }
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

        // Debug: WORKLOG_SNAPSHOT=1 shows the popover content in a window for screenshots;
        // WORKLOG_SNAPSHOT=page:<name> opens the main window on that page.
        if let value = ProcessInfo.processInfo.environment["WORKLOG_SNAPSHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                if value.hasPrefix("page:") {
                    self.openWindow(search: false)
                    self.nav.doc = .page(String(value.dropFirst(5)))
                } else {
                    self.snapshotPopover(to: value)
                }
            }
        }

        // Timers left running while the Mac sleeps would count the whole night.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopTimersForSleep() }
        }
        Self.registerLoginItemOnFirstInstall()
        if ProcessInfo.processInfo.environment["WORKLOG_SIMULATE_SLEEP"] == "1" {
            // Debug: deliver the same notification macOS sends before sleeping.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
            }
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
            w.contentViewController = NSHostingController(rootView: MainWindowView(model: model, nav: nav, notes: notes))
            w.delegate = self
            w.setFrameAutosaveName("WorklogMain")
            if !w.setFrameUsingName("WorklogMain") { w.center() }
            window = w
        }
        if search {
            nav.focusSearch += 1
        } else {
            nav.query = ""
            nav.doc = .day(Calendar.current.startOfDay(for: Date()))
        }
        show(window)
    }

    private func openSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(tick: tick, notes: notes, root: model.store.root)))
            w.title = "Worklog Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            // A grouped Form has no intrinsic height; without this the window is just a title bar.
            w.setContentSize(NSSize(width: 480, height: 580))
            w.delegate = self
            w.center()
            settingsWindow = w
        }
        show(settingsWindow)
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

    private func stopTimersForSleep() {
        guard UserDefaults.standard.object(forKey: "stopOnSleep") as? Bool ?? true else { return }
        let now = Date()
        let stopped = model.stopAll(at: now)
        if stopped > 0 {
            let s = stopped == 1 ? "timer" : "timers"
            model.notice = "Stopped \(stopped) \(s) at \(DayFile.clock(DayFile.minutesSinceMidnight(now))) when the Mac slept"
        }
    }

    /// The first time Worklog runs from /Applications, turn on Open at Login. After that the
    /// Settings toggle decides.
    private static func registerLoginItemOnFirstInstall() {
        guard Bundle.main.bundlePath.hasPrefix("/Applications/"),
              !UserDefaults.standard.bool(forKey: "loginItemInitialised") else { return }
        UserDefaults.standard.set(true, forKey: "loginItemInitialised")
        try? SMAppService.mainApp.register()
    }

    private func revealFolder() {
        popover.performClose(nil)
        try? FileManager.default.createDirectory(at: model.store.root, withIntermediateDirectories: true)
        NSWorkspace.shared.open(model.store.root)
    }

    // MARK: Dock and windows

    /// Become a Dock app first, then activate, then bring the window up. In any other order the
    /// window can end up created but off screen.
    private func show(_ w: NSWindow?) {
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
        NSApp.activate(ignoringOtherApps: true)
        w?.makeKeyAndOrderFront(nil)
    }

    /// A Dock icon and Command Tab while a window is open; menu bar only otherwise.
    private func updateDockPresence() {
        let anyOpen = [window, settingsWindow].contains { $0?.isVisible == true }
        let policy: NSApplication.ActivationPolicy = anyOpen ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        if anyOpen { NSApp.activate(ignoringOtherApps: true) }
    }

    func windowWillClose(_ notification: Notification) {
        // isVisible is still true inside willClose.
        DispatchQueue.main.async { self.updateDockPresence() }
    }

    /// Clicking the Dock icon, or opening Worklog again from Spotlight, shows the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if window?.isVisible != true { openWindow(search: false) }
        return true
    }

    private var launchedAtLogin = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        // The launch Apple Event says whether this is a login launch. As a fallback, a launch in the
        // first two minutes after boot is treated as one too.
        let event = NSAppleEventManager.shared().currentAppleEvent
        let loginItem = event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        launchedAtLogin = loginItem || ProcessInfo.processInfo.systemUptime < 120
    }

    @objc private func menuNewPage() { openWindow(search: false); nav.newPageRequest += 1 }
    @objc private func menuToday() { openWindow(search: false) }
    @objc private func menuSearch() { openWindow(search: true) }
    @objc private func menuSettings() { openSettings() }
    @objc private func menuOpenNote() { notes.open(notes.noteName) }

    private func mainMenu() -> NSMenu {
        let main = NSMenu()
        func submenu(_ title: String, _ items: [NSMenuItem]) {
            let item = NSMenuItem()
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            item.submenu = menu
            main.addItem(item)
        }
        func item(_ title: String, _ action: Selector, _ key: String, _ mods: NSEvent.ModifierFlags = .command,
                  target: AnyObject? = nil, tag: Int = 0) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            i.target = target
            i.tag = tag
            return i
        }
        submenu("Worklog", [
            item("About Worklog", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), ""),
            .separator(),
            item("Settings...", #selector(menuSettings), ",", target: self),
            .separator(),
            item("Hide Worklog", #selector(NSApplication.hide(_:)), "h"),
            item("Quit Worklog", #selector(NSApplication.terminate(_:)), "q"),
        ])
        submenu("File", [
            item("New Page", #selector(menuNewPage), "n", target: self),
            item("Today", #selector(menuToday), "t", target: self),
            item("Search All Notes", #selector(menuSearch), "f", [.command, .shift], target: self),
            item("Open Weekly Notes in Apple Notes", #selector(menuOpenNote), "w", [.command, .shift], target: self),
            .separator(),
            item("Close Window", #selector(NSWindow.performClose(_:)), "w"),
        ])
        // Standard selectors so copy, paste, undo and find work in the editor.
        submenu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            item("Find...", #selector(NSTextView.performFindPanelAction(_:)), "f", tag: Int(NSFindPanelAction.showFindPanel.rawValue)),
        ])
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        let windowItem = NSMenuItem()
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu
        return main
    }
}
