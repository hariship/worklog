import Foundation

/// Plain-file storage: `<root>/<yyyy>/<yyyy-MM-dd>.md`. Files are the only source of truth.
public struct Store {
    public let root: URL
    private let calendar: Calendar

    public init(root: URL, calendar: Calendar = .current) {
        self.root = root
        self.calendar = calendar
    }

    /// `~/Worklog`, or `$WORKLOG_ROOT` when set (handy for trying the app against a scratch folder).
    public static var defaultRoot: URL {
        if let path = ProcessInfo.processInfo.environment["WORKLOG_ROOT"], !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Worklog", isDirectory: true)
    }

    private var dayFormatter: DateFormatter {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    public func url(for date: Date) -> URL {
        let name = dayFormatter.string(from: date)
        return root
            .appendingPathComponent(String(name.prefix(4)), isDirectory: true)
            .appendingPathComponent("\(name).md")
    }

    public func read(_ date: Date) -> String? {
        try? String(contentsOf: url(for: date), encoding: .utf8)
    }

    public func write(_ text: String, for date: Date) throws {
        let url = url(for: date)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    public func modified(_ date: Date) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url(for: date).path))?[.modificationDate] as? Date
    }

    /// Read, transform, write. Always re-reads the file so edits made elsewhere are kept.
    @discardableResult
    public func update(_ date: Date, _ transform: (String) -> String?) throws -> Bool {
        let current = read(date) ?? DayFile.template(for: date)
        guard let next = transform(current), next != read(date) else { return false }
        try write(next, for: date)
        return true
    }

    /// All days that have a file, newest first.
    public func days() -> [Date] {
        let fm = FileManager.default
        guard let years = try? fm.contentsOfDirectory(atPath: root.path) else { return [] }
        let f = dayFormatter
        return years
            .filter { $0.count == 4 && Int($0) != nil }
            .flatMap { year in
                ((try? fm.contentsOfDirectory(atPath: root.appendingPathComponent(year).path)) ?? [])
                    .filter { $0.hasSuffix(".md") }
                    .compactMap { f.date(from: String($0.dropLast(3))) }
            }
            .sorted(by: >)
    }

    // MARK: Pages

    public var pagesDir: URL { root.appendingPathComponent("pages", isDirectory: true) }

    /// `Quilt Ops` -> `pages/Quilt Ops.md`. Only `/` and `:` are replaced; the file name is the title.
    public func pageURL(_ name: String) -> URL {
        let safe = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return pagesDir.appendingPathComponent("\(safe).md")
    }

    public func readPage(_ name: String) -> String? {
        try? String(contentsOf: pageURL(name), encoding: .utf8)
    }

    public func writePage(_ text: String, name: String) throws {
        try FileManager.default.createDirectory(at: pagesDir, withIntermediateDirectories: true)
        try text.write(to: pageURL(name), atomically: true, encoding: .utf8)
    }

    public static func pageTemplate(_ name: String) -> String { "# \(name)\n\n" }

    /// Page names, alphabetical.
    public func pages() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: pagesDir.path)) ?? [])
            .filter { $0.hasSuffix(".md") }
            .map { String($0.dropLast(3)) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    public func read(_ doc: Doc) -> String? {
        switch doc {
        case let .day(date): return read(date)
        case let .page(name): return readPage(name)
        }
    }

    public func template(_ doc: Doc) -> String {
        switch doc {
        case let .day(date): return DayFile.template(for: date)
        case let .page(name): return Self.pageTemplate(name)
        }
    }

    // MARK: Search and backlinks

    public struct Hit: Identifiable {
        public let id = UUID()
        public let doc: Doc
        public let line: String
    }

    /// Every document, newest days first, then pages.
    private func allDocs() -> [(Doc, String)] {
        days().compactMap { d in read(d).map { (.day(d), $0) } }
            + pages().compactMap { p in readPage(p).map { (.page(p), $0) } }
    }

    /// Case-insensitive line search across every day and page.
    public func search(_ query: String, limit: Int = 200) -> [Hit] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return lines(limit: limit) { $0.localizedCaseInsensitiveContains(q) }
    }

    /// Lines anywhere else that link to page `name` with `[[name]]` or its `#tag`.
    public func backlinks(to name: String, limit: Int = 300) -> [Hit] {
        lines(limit: limit, skipping: .page(name)) { Links.line($0, mentions: name) }
    }

    private func lines(limit: Int, skipping: Doc? = nil, where match: (String) -> Bool) -> [Hit] {
        var hits: [Hit] = []
        for (doc, text) in allDocs() where doc != skipping {
            for line in text.components(separatedBy: "\n") where match(line) {
                hits.append(Hit(doc: doc, line: line.trimmingCharacters(in: .whitespaces)))
                if hits.count >= limit { return hits }
            }
        }
        return hits
    }
}
