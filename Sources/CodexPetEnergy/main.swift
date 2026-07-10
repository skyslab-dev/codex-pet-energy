import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var overlay: OverlayPanelController!
    private var menuBar: MenuBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model = AppModel()
        overlay = OverlayPanelController(model: model)
        menuBar = MenuBarController(model: model, overlay: overlay)
        model.start()
        overlay.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        overlay.stop()
        model.stop()
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
