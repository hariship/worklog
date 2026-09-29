import CryptoKit
import Foundation

/// Read-only TickTick Open API client, ported from ticktick-mcp/src/client.ts and src/auth.ts.
public enum TickTick {
    public static let apiBase = URL(string: "https://api.ticktick.com/open/v1")!
    static let authorizeURL = URL(string: "https://ticktick.com/oauth/authorize")!
    static let tokenURL = URL(string: "https://ticktick.com/oauth/token")!
    /// Must match the redirect URI registered at developer.ticktick.com.
    public static let redirectURI = "http://localhost:8080/callback"
    public static let callbackPort: UInt16 = 8080

    public struct Project: Decodable, Equatable {
        public let id: String
        public let name: String
        public let closed: Bool?
    }

    public struct Task: Decodable, Identifiable, Equatable {
        public let id: String
        public let projectId: String
        public let title: String
        public let dueDate: String?
        public let status: Int?
        public let priority: Int?
        /// Filled in after decoding from the project the task came from.
        public var projectName: String = ""

        enum CodingKeys: String, CodingKey { case id, projectId, title, dueDate, status, priority }

        public var due: Date? { dueDate.flatMap(TickTick.parseDate) }
        public var isOpen: Bool { (status ?? 0) == 0 }

        /// Text for a Worklog line: the title plus the project as a tag.
        public var logText: String {
            let tag = TickTick.tag(for: projectName)
            return tag.isEmpty ? title : "\(title) #\(tag)"
        }
    }

    struct ProjectData: Decodable {
        let project: Project?
        let tasks: [Task]?
    }

    public enum APIError: Error, LocalizedError {
        case unauthorized
        case http(Int, String)

        public var errorDescription: String? {
            switch self {
            case .unauthorized: return "TickTick sign-in expired. Reconnect in Settings."
            case let .http(code, body): return "TickTick error \(code): \(body.prefix(120))"
            }
        }
    }

    // MARK: Tasks

    /// Every open task across all projects, plus the inbox.
    public static func openTasks(token: String, session: URLSession = .shared) async throws -> [Task] {
        let projects: [Project] = try await get("project", token: token, session: session)
        let ids = [("inbox", "Inbox")] + projects.filter { $0.closed != true }.map { ($0.id, $0.name) }
        return try await withThrowingTaskGroup(of: [Task].self) { group in
            for (id, name) in ids {
                group.addTask {
                    let data: ProjectData
                    do {
                        data = try await get("project/\(id)/data", token: token, session: session)
                    } catch APIError.http(404, _) where id == "inbox" {
                        return []
                    }
                    return (data.tasks ?? []).filter(\.isOpen).map { var t = $0; t.projectName = name; return t }
                }
            }
            return try await group.reduce(into: []) { $0 += $1 }
        }
    }

    /// Open tasks due today or overdue, earliest first.
    public static func dueToday(_ tasks: [Task], now: Date = Date(), calendar: Calendar = .current) -> [Task] {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        return tasks
            .filter { ($0.due ?? .distantFuture) < tomorrow }
            .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
    }

    static func get<T: Decodable>(_ path: String, token: String, session: URLSession) async throws -> T {
        var req = URLRequest(url: apiBase.appendingPathComponent(path))
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(code) else { throw APIError.http(code, String(decoding: data, as: UTF8.self)) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: OAuth (authorization code + PKCE, as in ticktick-mcp)

    public struct AuthRequest {
        public let url: URL
        public let state: String
        public let verifier: String
    }

    public static func authRequest(clientId: String) -> AuthRequest {
        let verifier = base64URL(Data((0..<32).map { _ in UInt8.random(in: 0...255) }))
        let challenge = base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = UUID().uuidString
        var c = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        c.queryItems = [
            .init(name: "client_id", value: clientId),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "scope", value: "tasks:read tasks:write"),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
        ]
        return AuthRequest(url: c.url!, state: state, verifier: verifier)
    }

    public struct Token: Decodable {
        public let access_token: String
        public let expires_in: Int?
    }

    public static func exchange(code: String, verifier: String, clientId: String, clientSecret: String,
                                session: URLSession = .shared) async throws -> Token {
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("Basic \(Data("\(clientId):\(clientSecret)".utf8).base64EncodedString())",
                     forHTTPHeaderField: "Authorization")
        var form = URLComponents()
        form.queryItems = [
            .init(name: "grant_type", value: "authorization_code"),
            .init(name: "code", value: code),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "code_verifier", value: verifier),
        ]
        req.httpBody = Data((form.percentEncodedQuery ?? "").utf8)
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw APIError.http(status, String(decoding: data, as: UTF8.self)) }
        return try JSONDecoder().decode(Token.self, from: data)
    }

    // MARK: Helpers

    /// TickTick dates look like `2026-09-29T07:00:00.000+0000`.
    static func parseDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        return f.date(from: s)
    }

    /// `📥 Quilt Ops` -> `quilt-ops`.
    public static func tag(for projectName: String) -> String {
        let words = projectName.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        return words.joined(separator: "-")
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
