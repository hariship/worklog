import Foundation
import WorklogCore

/// Sends `#weekly` lines and a weekly summary to one Apple Notes note via AppleScript.
/// Every write reads the note fresh, saves a backup of it to `<root>/.backup/`, and only appends.
@MainActor
final class NotesSync: ObservableObject {
    @Published var message: (text: String, isError: Bool, at: Date)?
    @Published var noteName: String {
        didSet { UserDefaults.standard.set(noteName, forKey: "notesTarget") }
    }

    private let store: Store
    private let queue = DispatchQueue(label: "worklog.notes")
    private var checker: Timer?
    private var sendingWeek = false

    init(store: Store) {
        self.store = store
        noteName = ProcessInfo.processInfo.environment["WORKLOG_NOTE"]
            ?? UserDefaults.standard.string(forKey: "notesTarget") ?? "Weekly Notes"
        checker = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sendDueWeek() }
        }
    }

    // MARK: Live #weekly lines

    func appendItem(_ logText: String) {
        let text = NotesHTML.noteText(from: logText)
        guard !text.isEmpty else { return }
        edit(success: "Added to \(noteName)") { NotesHTML.appendingListItem(text, to: $0) }
    }

    // MARK: Week summary

    enum WeekResult { case sent, alreadySent, empty }

    func sendWeek(monday: Date, auto: Bool = false) {
        guard !sendingWeek else { return }
        let calendar = Calendar.current
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
            .map { NotesHTML.Day(date: $0, entries: DayFile.entries(in: store.read($0) ?? "")) }
        guard let summary = NotesHTML.weekSummary(monday: monday, days: days) else {
            markSent(monday)
            if !auto { say("Nothing timed that week yet") }
            return
        }
        sendingWeek = true
        edit(success: "Week sent to \(noteName)", done: { [weak self] ok in
            self?.sendingWeek = false
            if ok { self?.markSent(monday) }
        }) { html in
            NotesHTML.hasWeek(monday, in: html) ? nil : html + "\n" + summary
        }
    }

    /// Sends the week that most recently ended: this week from Sunday 20:00, otherwise last week.
    func sendDueWeek(now: Date = Date()) {
        let calendar = Calendar.current
        let thisMonday = Self.monday(of: now)
        let isSundayEvening = calendar.component(.weekday, from: now) == 1 && calendar.component(.hour, from: now) >= 20
        let due = isSundayEvening ? thisMonday : calendar.date(byAdding: .day, value: -7, to: thisMonday)!
        if let last = UserDefaults.standard.object(forKey: "lastSentWeek") as? Date, last >= due { return }
        sendWeek(monday: due, auto: true)
    }

    static func monday(of date: Date) -> Date {
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: date)
        while calendar.component(.weekday, from: day) != 2 {
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return day
    }

    private func markSent(_ monday: Date) {
        UserDefaults.standard.set(monday, forKey: "lastSentWeek")
    }

    // MARK: AppleScript

    /// Read, back up, transform, write. A nil transform result means nothing to do.
    private func edit(success: String, done: ((Bool) -> Void)? = nil, _ transform: @escaping (String) -> String?) {
        let name = noteName
        let backupDir = store.root.appendingPathComponent(".backup", isDirectory: true)
        queue.async {
            let result: Result<Bool, Error> = Result {
                let html = try Self.run("""
                tell application "Notes" to get body of first note whose name is "\(Self.quote(name))"
                """)
                guard let next = transform(html) else { return false }
                try Self.backup(html, name: name, to: backupDir)
                _ = try Self.run("""
                tell application "Notes" to set body of first note whose name is "\(Self.quote(name))" to "\(Self.quote(next))"
                """)
                return true
            }
            DispatchQueue.main.async {
                switch result {
                case .success(true):
                    self.say(success)
                    done?(true)
                case .success(false):
                    self.say("Already in \(name)")
                    done?(true)
                case let .failure(error):
                    self.say(error.localizedDescription, isError: true)
                    done?(false)
                }
            }
        }
    }

    private func say(_ text: String, isError: Bool = false) {
        message = (text, isError, Date())
    }

    struct ScriptError: LocalizedError {
        let errorDescription: String?
    }

    nonisolated private static func run(_ script: String) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-"]
        let input = Pipe(), output = Pipe(), errors = Pipe()
        p.standardInput = input
        p.standardOutput = output
        p.standardError = errors
        try p.run()
        input.fileHandleForWriting.write(Data(script.utf8))
        try input.fileHandleForWriting.close()
        let out = output.fileHandleForReading.readDataToEndOfFile()
        let err = errors.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            let raw = String(decoding: err, as: UTF8.self)
            let message = raw.contains("-1743")
                ? "Allow Worklog to control Notes in System Settings, Privacy & Security, Automation."
                : raw.contains("-1728") ? "No note named that in Apple Notes." : "Apple Notes: \(raw.suffix(160))"
            throw ScriptError(errorDescription: message)
        }
        var text = String(decoding: out, as: UTF8.self)
        if text.hasSuffix("\n") { text.removeLast() }
        return text
    }

    nonisolated private static func quote(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    nonisolated private static func backup(_ html: String, name: String, to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmmss.SSS" // two writes in one second must not share a file
        let safe = name.replacingOccurrences(of: "/", with: "-")
        var url = dir.appendingPathComponent("\(safe) \(f.string(from: Date())).html")
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(safe) \(f.string(from: Date())) \(UUID().uuidString.prefix(4)).html")
        }
        try html.write(to: url, atomically: true, encoding: .utf8)
    }
}
