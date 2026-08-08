import Foundation
import ServiceManagement

@MainActor
enum AutomaticStartup {
    private static let configurationKey = "didConfigureAutomaticStartupV1"

    static func registerIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: configurationKey) else { return }

        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            defaults.set(true, forKey: configurationKey)
        case .notRegistered:
            do {
                try SMAppService.mainApp.register()
                defaults.set(true, forKey: configurationKey)
            } catch {
                // Retry on a future launch. Registration can fail while the app
                // is still being moved into Applications.
            }
        case .notFound:
            break
        @unknown default:
            break
        }
    }
}
