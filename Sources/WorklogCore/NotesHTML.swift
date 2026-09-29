import Foundation

/// Edits to an Apple Notes body (HTML). Pure functions: the app reads the body fresh, applies one of
/// these, and writes it back, so text added in Notes is never lost. Worklog only ever adds.
public enum NotesHTML {
    public static let weeklyTag = "weekly"

    /// Adds `text` as the next item of the note's last numbered list, or starts a list at the end.
    public static func appendingListItem(_ text: String, to html: String) -> String {
        let item = "<li>\(escape(text))</li>\n"
        if let close = html.range(of: "</ol>", options: .backwards) {
            var out = html
            out.insert(contentsOf: item, at: close.lowerBound)
            return out
        }
        return html + "\n<ol>\n\(item)</ol>"
    }

    /// Log text for the note: tags stay, except `#weekly` which only means "send this here".
    public static func noteText(from logText: String) -> String {
        logText.replacingOccurrences(of: #"(?<![\w#])#weekly\b"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: Week summary

    public struct Day {
        public let date: Date
        public let entries: [Entry]
        public init(date: Date, entries: [Entry]) { self.date = date; self.entries = entries }
    }

    public static func weekHeading(_ monday: Date) -> String {
        "Week of \(format(monday, "d MMM yyyy"))"
    }

    public static func hasWeek(_ monday: Date, in html: String) -> Bool {
        html.contains(escape(weekHeading(monday)))
    }

    /// Returns nil when the week has no finished timers. `#weekly` lines are left out: they are
    /// already in the note as list items.
    public static func weekSummary(monday: Date, days: [Day]) -> String? {
        var totals: [String: Int] = [:]
        var lines: [String] = []
        for day in days {
            let done = day.entries.filter { $0.minutes != nil && !$0.tags.contains(weeklyTag) }
            guard !done.isEmpty else { continue }
            for e in done {
                for tag in e.tags.isEmpty ? ["untagged"] : e.tags { totals[tag, default: 0] += e.minutes! }
            }
            var seen = Set<String>()
            let texts = done.map { stripTags($0.text) }.filter { !$0.isEmpty && seen.insert($0).inserted }
            lines.append("<li><b>\(format(day.date, "EEE"))</b>: \(escape(texts.joined(separator: "; ")))</li>")
        }
        guard !lines.isEmpty else { return nil }
        let total = days.flatMap(\.entries).filter { !$0.tags.contains(weeklyTag) }.compactMap(\.minutes).reduce(0, +)
        let byTag = totals.sorted { $0.value > $1.value }
            .map { "\($0.key) \(DayFile.duration($0.value))" }
            .joined(separator: " · ")
        return """
        <div><br></div>
        <div><b>\(escape(weekHeading(monday)))</b> - \(DayFile.duration(total)) tracked</div>
        <div>\(escape(byTag))</div>
        <ul>
        \(lines.joined(separator: "\n"))
        </ul>
        """
    }

    // MARK: Helpers

    static func stripTags(_ text: String) -> String {
        text.replacingOccurrences(of: #"(?<![\w#])#[A-Za-z0-9][\w-]*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    static func format(_ date: Date, _ pattern: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = pattern
        return f.string(from: date)
    }
}
