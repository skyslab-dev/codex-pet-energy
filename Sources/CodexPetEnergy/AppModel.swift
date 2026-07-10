import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var primary: UsageWindow?
    @Published var secondary: UsageWindow?
    @Published var connectionState: ConnectionState = .connecting
    @Published var now = Date()
    @Published var overlayEnabled: Bool {
        didSet { UserDefaults.standard.set(overlayEnabled, forKey: Self.overlayEnabledKey) }
    }
    @Published var petVisible = false

    private(set) var usageClient: CodexUsageClient?
    private var clockTimer: Timer?
    private var refreshedResetDeadlines = Set<TimeInterval>()
    private static let overlayEnabledKey = "usageOverlayEnabled"

    init() {
        if UserDefaults.standard.object(forKey: Self.overlayEnabledKey) == nil {
            overlayEnabled = true
        } else {
            overlayEnabled = UserDefaults.standard.bool(forKey: Self.overlayEnabledKey)
        }

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.now = Date()
                self.refreshAfterReachedResetIfNeeded()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        clockTimer = timer
    }

    func start() {
        let client = CodexUsageClient { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        usageClient = client
        client.start()
    }

    func refresh() {
        connectionState = .connecting
        usageClient?.refresh()
    }

    func stop() {
        clockTimer?.invalidate()
        clockTimer = nil
        usageClient?.stop()
        usageClient = nil
    }

    private func refreshAfterReachedResetIfNeeded() {
        let reached = [primary?.resetsAt, secondary?.resetsAt]
            .compactMap { $0 }
            .filter { $0 <= now }
            .map(\.timeIntervalSince1970)
            .filter { !refreshedResetDeadlines.contains($0) }
        guard !reached.isEmpty else { return }
        refreshedResetDeadlines.formUnion(reached)
        if refreshedResetDeadlines.count > 8 {
            refreshedResetDeadlines = Set(refreshedResetDeadlines.sorted().suffix(4))
        }
        usageClient?.refresh()
    }

    private func handle(_ event: CodexUsageClient.Event) {
        switch event {
        case .connected:
            connectionState = .connected
        case .windows(let primary, let secondary):
            // Rolling rate-limit notifications are sparse. Preserve the most
            // recent value for any window omitted by an update.
            if let primary { self.primary = primary }
            if let secondary { self.secondary = secondary }
            connectionState = .connected
        case .unavailable(let reason):
            connectionState = .unavailable(reason)
        }
    }
}
