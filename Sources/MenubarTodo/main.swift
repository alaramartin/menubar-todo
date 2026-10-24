import AppKit
import ApplicationServices
import Combine
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = TodoStore()
    private let overlay = GoalOverlay()
    private let updater = Updater()
    private var statusItem: NSStatusItem!
    private var popup: PopupPanel!
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "To-do list")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popup = PopupPanel(rootView: TodoView(store: store, updater: updater), store: store, updater: updater)
        popup.onOpenChange = { [weak self] open in self?.setHighlighted(open) }

        overlay.appearanceSource = { [weak self] in self?.statusItem.button?.effectiveAppearance }
        overlay.onClick = { [weak self] in self?.togglePopup() }
        store.$items.combineLatest(store.$goalID)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateGoal() }
            .store(in: &cancellables)

        setUpOnFirstLaunch()
        updater.start()
    }

    private func updateGoal() {
        // A checked-off goal no longer shows in the menu bar.
        let goal = store.goal
        overlay.setText(goal?.done == false ? goal?.title : nil)
    }

    /// Keeps the icon and the goal highlighted for as long as the popup is open.
    private func setHighlighted(_ on: Bool) {
        overlay.highlighted = on
        // The button un-highlights itself when its click finishes, so set it after that.
        DispatchQueue.main.async { [weak self] in self?.statusItem.button?.highlight(on) }
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            togglePopup()
        }
    }

    private func togglePopup() {
        if popup.isVisible {
            popup.close()
        } else if let button = statusItem.button, let buttonWindow = button.window {
            let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
            popup.show(below: anchor)
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        if !AXIsProcessTrusted() {
            let ax = NSMenuItem(title: "Allow Accessibility (better goal placement)…", action: #selector(requestAccessibility), keyEquivalent: "")
            ax.target = self
            menu.addItem(ax)
        }
        if let update = updater.available {
            let item = NSMenuItem(title: "Update Available (\(update.version))…", action: #selector(openUpdate), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        } else {
            let item = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Menubar Todo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openUpdate() {
        if let url = updater.available?.url { NSWorkspace.shared.open(url) }
    }

    @objc private func checkForUpdates() {
        Task {
            let alert = NSAlert()
            do {
                if let update = try await updater.check() {
                    alert.messageText = "Version \(update.version) is available"
                    alert.informativeText = "You have version \(updater.currentVersion)."
                    alert.addButton(withTitle: "Download")
                    alert.addButton(withTitle: "Later")
                } else {
                    alert.messageText = "You're up to date"
                    alert.informativeText = "Menubar Todo \(updater.currentVersion) is the latest version."
                }
            } catch {
                alert.messageText = "Couldn't check for updates"
                alert.informativeText = error.localizedDescription
            }
            NSApp.activate()
            if alert.runModal() == .alertFirstButtonReturn, let url = updater.available?.url {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("menubar-todo: login item change failed: \(error)")
        }
    }

    @objc private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// On the very first launch: start at login (so the list is back after a restart)
    /// and ask for Accessibility so the goal can steer around each app's menus.
    private func setUpOnFirstLaunch() {
        let key = "didFirstLaunchSetup"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        try? SMAppService.mainApp.register()
        requestAccessibility()
    }
}

/// The plain white popup under the menu bar icon.
@MainActor
final class PopupPanel: NSPanel {
    private let hosting: NSHostingView<TodoView>
    private var anchor: NSRect = .zero
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    private let store: TodoStore
    private var cancellables: Set<AnyCancellable> = []
    var onOpenChange: ((Bool) -> Void)?

    init(rootView: TodoView, store: TodoStore, updater: Updater) {
        self.store = store
        hosting = NSHostingView(rootView: rootView)
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.white.cgColor
        container.layer?.cornerRadius = 10
        container.layer?.masksToBounds = true
        hosting.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        contentView = container

        // Grow/shrink with the list.
        for publisher in [store.objectWillChange.eraseToAnyPublisher(), updater.objectWillChange.eraseToAnyPublisher()] {
            publisher.sink { [weak self] _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.layoutToFit() } }
            }
            .store(in: &cancellables)
        }
    }

    override var canBecomeKey: Bool { true }

    // The app has no Edit menu (it's an accessory app), so route the standard editing shortcuts to the text field ourselves.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let action: Selector? = switch (mods, event.charactersIgnoringModifiers?.lowercased()) {
        case ([.command], "x"): #selector(NSText.cut(_:))
        case ([.command], "c"): #selector(NSText.copy(_:))
        case ([.command], "v"): #selector(NSText.paste(_:))
        case ([.command], "a"): #selector(NSText.selectAll(_:))
        case ([.command], "z"): Selector(("undo:"))
        case ([.command, .shift], "z"): Selector(("redo:"))
        default: nil
        }
        if let action, NSApp.sendAction(action, to: nil, from: self) { return true }
        return super.performKeyEquivalent(with: event)
    }

    func show(below anchor: NSRect) {
        self.anchor = anchor
        layoutToFit()
        NSApp.activate()
        makeKeyAndOrderFront(nil)
        onOpenChange?(true)

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape: cancel an edit, otherwise close
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if self.store.editingID != nil {
                        self.store.editingID = nil
                    } else {
                        self.close()
                    }
                }
                return nil
            }
            return event
        }
    }

    override func close() {
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        makeFirstResponder(nil) // commits an in-progress edit
        super.close()
        onOpenChange?(false)
    }

    override func resignKey() {
        super.resignKey()
        close()
    }

    private func layoutToFit() {
        let size = hosting.fittingSize
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        var x = anchor.midX - size.width / 2
        if let vf = screen?.visibleFrame {
            x = min(max(x, vf.minX + 6), vf.maxX - size.width - 6)
        }
        let frame = NSRect(x: x, y: anchor.minY - 6 - size.height, width: size.width, height: size.height)
        setFrame(frame, display: true)
        invalidateShadow()
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
