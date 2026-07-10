import AppKit
import ServiceManagement

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let overlay: OverlayPanelController
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let status = NSMenuItem(title: "Connecting to Codex…", action: nil, keyEquivalent: "")
    private let toggleOverlay = NSMenuItem(title: "Enable Usage Overlay", action: #selector(toggleOverlayAction), keyEquivalent: "")
    private let launchAtLogin = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")

    init(model: AppModel, overlay: OverlayPanelController) {
        self.model = model
        self.overlay = overlay
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "bolt.horizontal.circle", accessibilityDescription: "Codex Pet Energy")
        statusItem.button?.toolTip = "Codex Pet Energy"
        menu.delegate = self
        menu.autoenablesItems = false
        status.isEnabled = false
        toggleOverlay.target = self
        launchAtLogin.target = self
        let refresh = NSMenuItem(title: "Refresh Usage Now", action: #selector(refreshAction), keyEquivalent: "r")
        refresh.target = self
        let quit = NSMenuItem(title: "Quit Codex Pet Energy", action: #selector(quitAction), keyEquivalent: "q")
        quit.target = self
        menu.items = [status, .separator(), toggleOverlay, refresh, launchAtLogin, .separator(), quit]
        statusItem.menu = menu
        updateMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateMenu()
    }

    private func updateMenu() {
        status.title = model.connectionState.menuDescription
        toggleOverlay.state = model.overlayEnabled ? .on : .off
        launchAtLogin.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func toggleOverlayAction() {
        overlay.setEnabled(!model.overlayEnabled)
        updateMenu()
    }

    @objc private func refreshAction() {
        model.refresh()
        updateMenu()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            status.title = "Could not update Launch at Login"
            return
        }
        updateMenu()
    }

    @objc private func quitAction() {
        NSApplication.shared.terminate(nil)
    }
}
