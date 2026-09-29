import Foundation
import Network

/// One-shot HTTP listener on localhost for the OAuth redirect (`/callback?code=..&state=..`).
final class OAuthCallbackServer {
    private var listener: NWListener?

    /// Calls `completion` once with the query items of the first `/callback` request, then stops.
    func start(port: UInt16, completion: @escaping (Result<[URLQueryItem], Error>) -> Void) {
        do {
            let params = NWParameters.tcp
            params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
            let listener = try NWListener(using: params)
            var finished = false
            listener.newConnectionHandler = { [weak self] conn in
                conn.start(queue: .main)
                conn.receive(minimumIncompleteLength: 1, maximumLength: 16384) { data, _, _, _ in
                    let request = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
                    // "GET /callback?code=...&state=... HTTP/1.1"
                    let target = request.split(separator: " ").dropFirst().first.map(String.init) ?? ""
                    let comps = URLComponents(string: "http://localhost\(target)")
                    let isCallback = comps?.path == "/callback"
                    let body = isCallback
                        ? "<h2>Worklog is connected to TickTick.</h2><p>You can close this tab.</p>"
                        : "Not found"
                    let response = "HTTP/1.1 \(isCallback ? 200 : 404) OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                    conn.send(content: Data(response.utf8), completion: .contentProcessed { _ in conn.cancel() })
                    guard isCallback, !finished else { return }
                    finished = true
                    self?.stop()
                    completion(.success(comps?.queryItems ?? []))
                }
            }
            listener.stateUpdateHandler = { state in
                if case let .failed(error) = state, !finished {
                    finished = true
                    completion(.failure(error))
                }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            completion(.failure(error))
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }
}
