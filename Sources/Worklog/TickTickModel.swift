import AppKit
import Foundation
import WorklogCore

/// TickTick connection and a cached list of open tasks. Read-only: nothing is written back.
@MainActor
final class TickTickModel: ObservableObject {
    enum Status: Equatable {
        case notConfigured      // no client id/secret yet
        case disconnected       // credentials, but no valid token
        case connecting         // waiting for the browser sign-in
        case ready
        case failed(String)
    }

    @Published private(set) var status: Status = .notConfigured
    @Published private(set) var tasks: [TickTick.Task] = []
    @Published private(set) var lastSync: Date?
    @Published private(set) var syncing = false

    private let server = OAuthCallbackServer()
    private var refresher: Timer?
    // Loaded from SecretsFile once; every change goes through `store`.
    private(set) var clientId = SecretsFile.load()["clientId"] ?? ""
    private var clientSecret = SecretsFile.load()["clientSecret"]
    private var token = SecretsFile.load()["token"]

    /// The old MCP server's credentials, offered as a one-click import in Settings.
    static let mcpEnv = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Desktop/workspace/personal/ticktick-mcp/.env")

    init() {
        updateStatus()
        refresher = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    var today: [TickTick.Task] { TickTick.dueToday(tasks) }

    var hasSecret: Bool { clientSecret != nil }

    private func store(clientId: String? = nil, clientSecret: String? = nil, token: String?? = nil) {
        if let clientId { self.clientId = clientId }
        if let clientSecret { self.clientSecret = clientSecret }
        if let token { self.token = token }
        var values = ["clientId": self.clientId]
        values["clientSecret"] = self.clientSecret
        values["token"] = self.token
        SecretsFile.save(values)
    }

    func matches(_ query: String, limit: Int = 5) -> [TickTick.Task] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return [] }
        return Array(tasks.filter { $0.title.localizedCaseInsensitiveContains(q) }.prefix(limit))
    }

    // MARK: Credentials

    func saveCredentials(clientId: String, clientSecret: String) {
        let secret = clientSecret.trimmingCharacters(in: .whitespaces)
        store(clientId: clientId.trimmingCharacters(in: .whitespaces), clientSecret: secret.isEmpty ? nil : secret)
        updateStatus()
    }

    /// Reads TICKTICK_CLIENT_ID / TICKTICK_CLIENT_SECRET from ticktick-mcp/.env. The expired token is ignored.
    func importFromMCP() -> Bool {
        guard let text = try? String(contentsOf: Self.mcpEnv, encoding: .utf8) else { return false }
        var env: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 { env[parts[0]] = parts[1] }
        }
        guard let id = env["TICKTICK_CLIENT_ID"], let secret = env["TICKTICK_CLIENT_SECRET"] else { return false }
        saveCredentials(clientId: id, clientSecret: secret)
        return true
    }

    func disconnect() {
        store(token: .some(nil))
        tasks = []
        updateStatus()
    }

    // MARK: Sign-in

    func connect() {
        guard let secret = clientSecret, !clientId.isEmpty else {
            status = .notConfigured
            return
        }
        let id = clientId
        let request = TickTick.authRequest(clientId: id)
        server.stop()
        status = .connecting
        server.start(port: TickTick.callbackPort) { [weak self] result in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch result {
                case let .failure(error):
                    self.status = .failed("Could not listen on port \(TickTick.callbackPort): \(error.localizedDescription)")
                case let .success(items):
                    let value = { (name: String) in items.first { $0.name == name }?.value }
                    guard value("state") == request.state, let code = value("code") else {
                        self.status = .failed(value("error").map { "TickTick said: \($0)" } ?? "Sign-in was cancelled or did not match.")
                        return
                    }
                    Task {
                        do {
                            let token = try await TickTick.exchange(code: code, verifier: request.verifier,
                                                                    clientId: id, clientSecret: secret)
                            self.store(token: token.access_token)
                            self.updateStatus()
                            self.refresh()
                            NSApp.activate(ignoringOtherApps: true)
                        } catch {
                            self.status = .failed(error.localizedDescription)
                        }
                    }
                }
            }
        }
        NSWorkspace.shared.open(request.url)
    }

    func cancelConnect() {
        server.stop()
        updateStatus()
    }

    // MARK: Sync

    /// Refetch unless a sync happened in the last `minAge` seconds.
    func refresh(minAge: TimeInterval = 0) {
        guard let token, !syncing else { return }
        if let lastSync, Date().timeIntervalSince(lastSync) < minAge { return }
        syncing = true
        Task {
            defer { syncing = false }
            do {
                tasks = try await TickTick.openTasks(token: token)
                lastSync = Date()
                status = .ready
            } catch TickTick.APIError.unauthorized {
                store(token: .some(nil))
                status = .failed(TickTick.APIError.unauthorized.localizedDescription)
            } catch {
                status = .failed(error.localizedDescription)
            }
        }
    }

    private func updateStatus() {
        if clientId.isEmpty || !hasSecret {
            status = .notConfigured
        } else if token == nil {
            status = .disconnected
        } else if status != .ready {
            status = .ready
        }
    }
}
