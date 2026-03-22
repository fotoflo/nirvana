import SwiftUI
import AppKit

@main
struct NirvanaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            ConfigView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var gridModel = GridModel.shared
    private var hotkeyListener: HotkeyListener?
    private var spaceBridge: SpaceBridge?
    private var pagerController: PagerOverlayController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupSpaceBridge()
        setupHotkeyListener()
        setupPagerController()

        // Hide dock icon — menu bar app only
        NSApp.setActivationPolicy(.accessory)
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            let renderer = MenuBarIconRenderer(gridModel: gridModel)
            button.image = renderer.render()

            // Update icon when position changes
            NotificationCenter.default.addObserver(
                forName: .gridPositionChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self = self else { return }
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
        hotkeyListener?.start()
    }

    private func setupPagerController() {
        pagerController = PagerOverlayController(gridModel: gridModel)
    }

    @objc private func openPreferences() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc private func openAbout() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}
