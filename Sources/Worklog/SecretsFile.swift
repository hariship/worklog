import Foundation

/// TickTick credentials in `~/Library/Application Support/Worklog/ticktick.json`, readable only by you
/// (file 0600, folder 0700). Used instead of the Keychain, which prompts again after every rebuild
/// of an ad-hoc signed app.
enum SecretsFile {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Worklog/ticktick.json")

    static func load() -> [String: String] {
        guard let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return dict
    }

    static func save(_ values: [String: String]) {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard let data = try? JSONEncoder().encode(values) else { return }
        // Create with 0600 before writing so the secret is never world-readable, even briefly.
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        try? data.write(to: url)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
