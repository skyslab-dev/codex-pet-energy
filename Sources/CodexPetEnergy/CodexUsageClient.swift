import Foundation

// All mutable state is confined to `queue`; public entry points marshal onto
// that queue, and `stop()` synchronizes before process teardown.
final class CodexUsageClient: @unchecked Sendable {
    enum Event {
        case connected
        case windows(UsageWindow?, UsageWindow?, replacingMissing: Bool)
        case tokenUsage(TokenUsageProfile?)
        case unavailable(String)
    }

    private let onEvent: (Event) -> Void
    private let queue = DispatchQueue(label: "com.codexpetenergy.usage-client")
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var outputBuffer = Data()
    private var reconnectAttempt = 0
    private var reconnectWorkItem: DispatchWorkItem?
    private var pollingTimer: DispatchSourceTimer?
    private var nextRequestID = 2
    private var pendingRateLimitRequestIDs = Set<Int>()
    private var pendingTokenUsageRequestIDs = Set<Int>()
    private var stopped = false

    init(onEvent: @escaping (Event) -> Void) {
        self.onEvent = onEvent
    }

    func start() {
        queue.async { [weak self] in self?.launch() }
    }

    func stop() {
        queue.sync {
            stopped = true
            reconnectWorkItem?.cancel()
            reconnectWorkItem = nil
            pollingTimer?.cancel()
            pollingTimer = nil
            tearDownActiveProcess(terminate: true)
        }
    }

    func refresh() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.process?.isRunning == true {
                self.requestRateLimits()
                self.requestTokenUsage()
            } else {
                self.launch()
            }
        }
    }

    private func launch() {
        guard !stopped, process?.isRunning != true else { return }
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil

        guard let executable = Self.findCodexExecutable() else {
            onEvent(.unavailable("Codex CLI was not found"))
            scheduleReconnect()
            return
        }

        let launchedProcess = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        launchedProcess.executableURL = executable
        launchedProcess.arguments = ["app-server", "--stdio"]
        launchedProcess.standardInput = stdinPipe
        launchedProcess.standardOutput = stdoutPipe
        // The app-server can emit diagnostics indefinitely. Sending stderr to
        // /dev/null prevents an unread Pipe from eventually blocking it.
        launchedProcess.standardError = FileHandle.nullDevice

        let outputHandle = stdoutPipe.fileHandleForReading
        outputHandle.readabilityHandler = { [weak self, weak launchedProcess] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self, let launchedProcess else { return }
            self.queue.async { [self, launchedProcess, data] in
                guard self.process === launchedProcess else { return }
                self.consume(data)
            }
        }
        launchedProcess.terminationHandler = { [weak self, weak launchedProcess] _ in
            guard let self, let launchedProcess else { return }
            self.queue.async { [self, launchedProcess] in
                self.handleTermination(of: launchedProcess)
            }
        }

        do {
            try launchedProcess.run()
            process = launchedProcess
            input = stdinPipe.fileHandleForWriting
            output = outputHandle
            outputBuffer.removeAll(keepingCapacity: true)
            pendingRateLimitRequestIDs.removeAll(keepingCapacity: true)
            send([
                "id": 1,
                "method": "initialize",
                "params": [
                    "clientInfo": [
                        "name": "codex-pet-energy",
                        "title": "Codex Pet Energy",
                        "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0",
                    ],
                    "capabilities": ["experimentalApi": true],
                ],
            ])
        } catch {
            outputHandle.readabilityHandler = nil
            stdinPipe.fileHandleForWriting.closeFile()
            outputHandle.closeFile()
            onEvent(.unavailable("Could not start Codex usage service"))
            scheduleReconnect()
        }
    }

    private func consume(_ data: Data) {
        outputBuffer.append(data)
        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            let line = outputBuffer[..<newline]
            outputBuffer.removeSubrange(...newline)
            guard !line.isEmpty,
                  let json = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else {
                continue
            }
            handle(json)
        }
    }

    private func handle(_ message: [String: Any]) {
        if (message["id"] as? NSNumber)?.intValue == 1 {
            if message["result"] != nil {
                reconnectAttempt = 0
                send(["method": "initialized"])
                onEvent(.connected)
                requestRateLimits()
                requestTokenUsage()
                startPolling()
            } else if message["error"] != nil {
                failActiveProcess(reason: "Codex usage service rejected initialization")
            }
            return
        }

        if let id = (message["id"] as? NSNumber)?.intValue,
           pendingRateLimitRequestIDs.remove(id) != nil {
            if let result = message["result"] as? [String: Any] {
                let windows = UsagePayloadParser.windows(from: result)
                onEvent(.windows(windows.primary, windows.secondary, replacingMissing: true))
            } else if message["error"] != nil {
                onEvent(.unavailable("Codex usage is temporarily unavailable"))
            }
            return
        }

        if let id = (message["id"] as? NSNumber)?.intValue,
           pendingTokenUsageRequestIDs.remove(id) != nil {
            if let result = message["result"] as? [String: Any] {
                onEvent(.tokenUsage(TokenUsagePayloadParser.profile(from: result)))
            } else if message["error"] != nil {
                // Token activity is supplemental. Keep live rate-limit data
                // visible when an older app-server does not expose it.
                onEvent(.tokenUsage(nil))
            }
            return
        }

        if message["method"] as? String == "account/rateLimits/updated",
           let params = message["params"] as? [String: Any],
           let snapshot = params["rateLimits"] as? [String: Any] {
            let windows = UsagePayloadParser.windows(fromSnapshot: snapshot)
            onEvent(.windows(windows.primary, windows.secondary, replacingMissing: false))
        }
    }

    private func requestRateLimits() {
        guard process?.isRunning == true else { return }
        let id = nextRequestID
        nextRequestID = nextRequestID == Int.max ? 2 : nextRequestID + 1
        pendingRateLimitRequestIDs.insert(id)
        if !send(["id": id, "method": "account/rateLimits/read", "params": NSNull()]) {
            pendingRateLimitRequestIDs.remove(id)
        }
    }

    private func requestTokenUsage() {
        guard process?.isRunning == true else { return }
        let id = nextRequestID
        nextRequestID = nextRequestID == Int.max ? 2 : nextRequestID + 1
        pendingTokenUsageRequestIDs.insert(id)
        if !send(["id": id, "method": "account/usage/read", "params": NSNull()]) {
            pendingTokenUsageRequestIDs.remove(id)
        }
    }

    @discardableResult
    private func send(_ object: [String: Any]) -> Bool {
        guard let input,
              let data = try? JSONSerialization.data(withJSONObject: object) else { return false }
        var line = data
        line.append(0x0A)
        do {
            try input.write(contentsOf: line)
            return true
        } catch {
            failActiveProcess()
            return false
        }
    }

    private func startPolling() {
        pollingTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 60, repeating: 60, leeway: .seconds(2))
        timer.setEventHandler { [weak self] in
            self?.requestRateLimits()
            self?.requestTokenUsage()
        }
        timer.resume()
        pollingTimer = timer
    }

    private func failActiveProcess(reason: String = "Reconnecting to Codex…") {
        guard process != nil else { return }
        tearDownActiveProcess(terminate: true)
        onEvent(.unavailable(reason))
        scheduleReconnect()
    }

    private func handleTermination(of terminatedProcess: Process) {
        guard !stopped, process === terminatedProcess else { return }
        tearDownActiveProcess(terminate: false)
        onEvent(.unavailable("Reconnecting to Codex…"))
        scheduleReconnect()
    }

    private func tearDownActiveProcess(terminate: Bool) {
        let activeProcess = process
        activeProcess?.terminationHandler = nil
        output?.readabilityHandler = nil
        input?.closeFile()
        output?.closeFile()
        input = nil
        output = nil
        process = nil
        outputBuffer.removeAll(keepingCapacity: false)
        pendingRateLimitRequestIDs.removeAll(keepingCapacity: false)
        pendingTokenUsageRequestIDs.removeAll(keepingCapacity: false)
        pollingTimer?.cancel()
        pollingTimer = nil
        if terminate, activeProcess?.isRunning == true {
            activeProcess?.terminate()
        }
    }

    private func scheduleReconnect() {
        guard !stopped else { return }
        reconnectWorkItem?.cancel()
        let delay = min(60.0, pow(2.0, Double(reconnectAttempt)))
        reconnectAttempt += 1
        let item = DispatchWorkItem { [weak self] in
            self?.reconnectWorkItem = nil
            self?.launch()
        }
        reconnectWorkItem = item
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    static func findCodexExecutable() -> URL? {
        let candidates = [
            ProcessInfo.processInfo.environment["CODEX_BIN"],
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            NSHomeDirectory() + "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/usr/local/bin/codex",
            "/opt/homebrew/bin/codex",
        ].compactMap { $0 }
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map(URL.init(fileURLWithPath:))
    }
}
