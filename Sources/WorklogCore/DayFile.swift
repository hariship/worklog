import Foundation

/// One line in a day's `## Log` section.
///
///     - 09:12 standup #pugmarks                 point entry
///     - 10:05-11:20 (1h15) fixed edge #quilt    finished timer
///     - 11:30- reviewing PR 823 #quilt          running timer
public struct Entry: Equatable, Identifiable {
    public var id: Int { lineIndex }
    /// Index of the line in the file, used to rewrite it in place.
    public let lineIndex: Int
    /// Minutes since midnight.
    public let start: Int
    public let end: Int?
    public let isRunning: Bool
    public let text: String
    public let tags: [String]

    /// Duration of a finished timer. A timer that ran past midnight wraps.
    public var minutes: Int? {
        guard let end else { return nil }
        return DayFile.span(from: start, to: end)
    }
}

public enum DayFile {
    public static let logHeading = "## Log"

    private static let lineRegex = try! NSRegularExpression(
        pattern: #"^- (\d{1,2}):(\d{2})(-(?:(\d{1,2}):(\d{2}))?)?(?: \(\d+h\d{2}\))?(?:\s+(.*))?$"#
    )
    private static let tagRegex = try! NSRegularExpression(pattern: #"(?<![\w#])#([A-Za-z0-9][\w-]*)"#)

    // MARK: Parsing

    public static func entries(in text: String) -> [Entry] {
        let lines = text.components(separatedBy: "\n")
        guard let range = logRange(in: lines) else { return [] }
        return range.compactMap { entry(from: lines[$0], at: $0) }
    }

    static func entry(from line: String, at index: Int) -> Entry? {
        let ns = line as NSString
        guard let m = lineRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        func group(_ i: Int) -> String? {
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
        guard let h = Int(group(1)!), let mm = Int(group(2)!), h < 24, mm < 60 else { return nil }
        var end: Int?
        if let eh = group(4).flatMap(Int.init), let em = group(5).flatMap(Int.init), eh < 24, em < 60 {
            end = eh * 60 + em
        }
        let text = (group(6) ?? "").trimmingCharacters(in: .whitespaces)
        return Entry(
            lineIndex: index,
            start: h * 60 + mm,
            end: end,
            isRunning: group(3) != nil && end == nil,
            text: text,
            tags: tags(in: text)
        )
    }

    public static func tags(in text: String) -> [String] {
        let ns = text as NSString
        return tagRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range(at: 1)).lowercased() }
    }

    /// Line indices of the Log section body: after `## Log`, up to the next `#` heading.
    static func logRange(in lines: [String]) -> Range<Int>? {
        guard let head = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == logHeading }) else { return nil }
        let bodyStart = head + 1
        let next = lines[bodyStart...].firstIndex(where: { $0.hasPrefix("#") }) ?? lines.count
        return bodyStart..<next
    }

    // MARK: Editing (pure: text in, text out)

    public static func template(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEE d MMM yyyy"
        return "# \(f.string(from: date))\n\n\(logHeading)\n\n## Notes\n\n"
    }

    public static func pointLine(at start: Int, _ text: String) -> String {
        "- \(clock(start)) \(text)"
    }

    public static func runningLine(at start: Int, _ text: String) -> String {
        "- \(clock(start))- \(text)"
    }

    public static func finishedLine(start: Int, end: Int, _ text: String) -> String {
        "- \(clock(start))-\(clock(end)) (\(duration(span(from: start, to: end)))) \(text)"
    }

    /// Appends a line after the last non-blank line of the Log section, creating the section if missing.
    public static func appending(_ line: String, to text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        guard let range = logRange(in: lines) else {
            // No Log section: add one after the title line (or at the top).
            let insertAt = lines.first?.hasPrefix("# ") == true ? 1 : 0
            lines.insert(contentsOf: ["", logHeading, line, ""], at: insertAt)
            return lines.joined(separator: "\n")
        }
        let lastFilled = range.last(where: { !lines[$0].trimmingCharacters(in: .whitespaces).isEmpty })
        let insertAt = lastFilled.map { $0 + 1 } ?? range.lowerBound
        lines.insert(line, at: insertAt)
        // Keep a blank line before the next heading.
        if insertAt + 1 < lines.count, lines[insertAt + 1].hasPrefix("#") {
            lines.insert("", at: insertAt + 1)
        }
        return lines.joined(separator: "\n")
    }

    /// Closes one running timer, found by start time and text (line numbers shift when the file is
    /// edited elsewhere). Returns nil when it is no longer running.
    public static func stopping(start: Int, text entryText: String, in text: String, at end: Int) -> String? {
        guard let e = entries(in: text).first(where: { $0.isRunning && $0.start == start && $0.text == entryText })
        else { return nil }
        var lines = text.components(separatedBy: "\n")
        lines[e.lineIndex] = finishedLine(start: e.start, end: end, e.text)
        return lines.joined(separator: "\n")
    }

    // MARK: Time helpers

    public static func span(from start: Int, to end: Int) -> Int {
        end >= start ? end - start : end + 1440 - start
    }

    public static func clock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    /// `1h15`, `0h42`. Also used for totals.
    public static func duration(_ minutes: Int) -> String {
        String(format: "%dh%02d", minutes / 60, minutes % 60)
    }

    public static func minutesSinceMidnight(_ date: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}
