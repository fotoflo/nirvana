import SwiftUI
import AppKit

// MARK: - Entry Point
// Use a pure AppKit lifecycle so the menu bar app stays alive
// even when all windows are closed. SwiftUI's App lifecycle
// can aggressively terminate accessory apps with no visible scenes.

@main
enum NirvanaEntry {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var gridModel = GridModel.shared
    private var hotkeyListener: HotkeyListener?
    private var spaceBridge: SpaceBridge?
    private var pagerController: PagerOverlayController?
    private var teleportFlash: TeleportFlashController?
    private var onboardingWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var dockHideObserver: NSObjectProtocol?

    // Keep running when all windows close — we're a menu bar app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupSpaceBridge()
        setupHotkeyListener()
        setupPagerController()
        teleportFlash = TeleportFlashController(gridModel: gridModel)

        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "nirvana.onboardingCompleted")
        if !hasCompletedOnboarding {
            showOnboarding()
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: - Onboarding

    private func showOnboarding() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let onboardingView = OnboardingView(gridModel: gridModel) { [weak self] in
            self?.dismissOnboarding()
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor(red: 0.1, green: 0.1, blue: 0.18, alpha: 1)
        window.contentView = NSHostingView(rootView: onboardingView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.isReleasedWhenClosed = false
        window.delegate = self
        onboardingWindow = window
    }

    private func dismissOnboarding() {
        UserDefaults.standard.set(true, forKey: "nirvana.onboardingCompleted")
        onboardingWindow?.close()
        onboardingWindow = nil
        NSApp.setActivationPolicy(.accessory)
    }

    // Handle close via X button.
    func windowWillClose(_ notification: Notification) {
        if let closingWindow = notification.object as? NSWindow,
           closingWindow === onboardingWindow {
            UserDefaults.standard.set(true, forKey: "nirvana.onboardingCompleted")
            onboardingWindow = nil
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            let renderer = MenuBarIconRenderer(gridModel: gridModel)
            button.image = renderer.render()

            NotificationCenter.default.addObserver(
                forName: .gridPositionChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    let renderer = MenuBarIconRenderer(gridModel: self.gridModel)
                    button.image = renderer.render()
                }
            }
            NotificationCenter.default.addObserver(
                forName: .gridConfigChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                let renderer = MenuBarIconRenderer(gridModel: self.gridModel)
                button.image = renderer.render()
            }
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "About Nirvana", action: #selector(openAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Nirvana", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    // MARK: - Core Setup

    private func setupSpaceBridge() {
        spaceBridge = SpaceBridge(gridModel: gridModel)
        spaceBridge?.startMonitoring()
    }

    private func setupHotkeyListener() {
        hotkeyListener = HotkeyListener(gridModel: gridModel)
        hotkeyListener?.onPagerToggle = { [weak self] show in
            if show {
                self?.pagerController?.show()
            } else {
                self?.pagerController?.dismissWithFocusCollapse()
            }
        }
        hotkeyListener?.onNavigate = { [weak self] _ in
            self?.switchToCurrentGridSpace()
        }
        hotkeyListener?.start()
    }

    /// Switch macOS to the Space corresponding to the grid model's current position.
    private func switchToCurrentGridSpace() {
        guard let bridge = spaceBridge else {
            NSLog("[Nirvana] switchToCurrentGridSpace: no bridge")
            return
        }
        let enabledCells = gridModel.enabledCells
        guard let cellIndex = enabledCells.firstIndex(where: {
            $0.row == gridModel.currentRow && $0.col == gridModel.currentCol
        }) else {
            NSLog("[Nirvana] switchToCurrentGridSpace: current cell not found in enabledCells")
            return
        }
        let spaces = bridge.listSpaceIDs()
        guard cellIndex < spaces.count else {
            NSLog("[Nirvana] switchToCurrentGridSpace: cellIndex %d >= spaces count %d", cellIndex, spaces.count)
            return
        }
        bridge.switchToSpace(spaces[cellIndex])
    }

    private func setupPagerController() {
        pagerController = PagerOverlayController(gridModel: gridModel)
        pagerController?.onSpaceSelected = { [weak self] _, _ in
            self?.switchToCurrentGridSpace()
        }
    }

    // MARK: - Menu Actions

    @objc private func openPreferences() {
        if settingsWindow == nil {
            let settingsView = ConfigView()
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Nirvana Preferences"
            window.contentView = NSHostingView(rootView: settingsView)
            window.center()
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        scheduleDockIconHide()
    }

    @objc private func openAbout() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
        scheduleDockIconHide()
    }

    /// Hide the dock icon once the app loses focus.
    private func scheduleDockIconHide() {
        if let existing = dockHideObserver {
            NotificationCenter.default.removeObserver(existing)
            dockHideObserver = nil
        }
        dockHideObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if let obs = self.dockHideObserver {
                NotificationCenter.default.removeObserver(obs)
                self.dockHideObserver = nil
            }
            if self.onboardingWindow == nil {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
