import Foundation

/// A document in the wiki: a day file or a free page.
public enum Doc: Hashable {
    case day(Date)
    case page(String)
}

/// `[[Page name]]` and `[[2026-09-29]]` links.
public enum Links {
    private static let regex = try! NSRegularExpression(pattern: #"\[\[([^\[\]\n]+)\]\]"#)

    public struct Match {
        public let range: NSRange   // the whole `[[...]]`
        public let target: String   // the text inside, trimmed
    }

    public static func matches(in text: String) -> [Match] {
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap {
            let target = ns.substring(with: $0.range(at: 1)).trimmingCharacters(in: .whitespaces)
            return target.isEmpty ? nil : Match(range: $0.range, target: target)
        }
    }

    /// `[[notes:Weekly Notes]]` points at an Apple Notes note instead of a page.
    public static let notesPrefix = "notes:"

    public static func noteName(_ target: String) -> String? {
        guard target.lowercased().hasPrefix(notesPrefix) else { return nil }
        let name = target.dropFirst(notesPrefix.count).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    /// When the text just before the cursor is an unclosed `[[partial`, returns `partial` (maybe empty).
    public static func openLinkPrefix(before text: String) -> String? {
        guard let open = text.range(of: "[[", options: .backwards) else { return nil }
        let partial = text[open.upperBound...]
        if partial.contains("]") || partial.contains("[") || partial.contains("\n") { return nil }
        return String(partial)
    }

    /// Link targets that complete `partial`: pages first, then `notes:` names. Case-insensitive.
    public static func completions(for partial: String, pages: [String], notes: [String], limit: Int = 8) -> [String] {
        let p = partial.trimmingCharacters(in: .whitespaces)
        func hit(_ s: String) -> Bool { p.isEmpty || s.localizedCaseInsensitiveContains(p) }
        var out = pages.filter(hit)
        let noteQuery = p.lowercased().hasPrefix(notesPrefix) ? String(p.dropFirst(notesPrefix.count)) : p
        out += notes.filter { noteQuery.isEmpty || $0.localizedCaseInsensitiveContains(noteQuery) }.map { notesPrefix + $0 }
        return Array(out.prefix(limit))
    }

    /// `2026-09-29` opens that day; anything else is a page name.
    public static func doc(for target: String, calendar: Calendar = .current) -> Doc {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        if target.count == 10, let date = f.date(from: target) { return .day(calendar.startOfDay(for: date)) }
        return .page(target)
    }

    /// Does `line` point at page `name`? Either `[[name]]` or the matching `#tag`
    /// (page "Quilt Ops" collects lines tagged #quilt-ops), both case-insensitive.
    public static func line(_ line: String, mentions name: String) -> Bool {
        if matches(in: line).contains(where: { $0.target.caseInsensitiveCompare(name) == .orderedSame }) { return true }
        let tag = TickTick.tag(for: name)
        return !tag.isEmpty && DayFile.tags(in: line).contains(tag)
    }
}
