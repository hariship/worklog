import Foundation
import WorklogCore

/// App state on top of the day files. Every write re-reads the file first, so edits made in the
/// main window or another editor are never clobbered.
@MainActor
final class WorklogModel: ObservableObject {
    let store: Store
    private let calendar = Calendar.current

    @Published private(set) var today = Date()
    @Published private(set) var entries: [Entry] = []
    /// Running timers, oldest first, with the day file each lives in (yesterday's if it ran past midnight).
    @Published private(set) var running: [Timer] = []
    @Published private(set) var now = Date()
    /// Bumped on every write so open editors know to reload.
    @Published private(set) var revision = 0
    @Published var lastError: String?

    struct Timer: Identifiable {
        var id: String { "\(day.timeIntervalSince1970)-\(entry.start)-\(entry.text)" }
        let day: Date
        let entry: Entry
    }

    private var ticker: Foundation.Timer?
    private var seenModified: Date?

    init(store: Store = Store(root: Store.defaultRoot)) {
        self.store = store
        reload()
        ticker = Foundation.Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(ticker!, forMode: .common)
    }

    // MARK: Actions

    func log(_ raw: String, startTimer: Bool) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let at = Date()
        let minute = DayFile.minutesSinceMidnight(at)
        let line = startTimer ? DayFile.runningLine(at: minute, text) : DayFile.pointLine(at: minute, text)
        write(at) { DayFile.appending(line, to: $0) }
    }

    func stop(_ timer: Timer, at: Date = Date()) {
        let end = DayFile.minutesSinceMidnight(at)
        write(timer.day) { DayFile.stopping(start: timer.entry.start, text: timer.entry.text, in: $0, at: end) }
    }

    /// Saves text from the main window editor. Does not create a file for an untouched template.
    func save(_ text: String, for day: Date) {
        if store.read(day) == nil, text == DayFile.template(for: day) { return }
        write(day) { _ in text }
    }

    // MARK: Derived

    func elapsed(_ timer: Timer) -> Int {
        let start = calendar.startOfDay(for: timer.day).addingTimeInterval(TimeInterval(timer.entry.start * 60))
        return max(0, Int(now.timeIntervalSince(start) / 60))
    }

    /// Finished timers today plus the running ones. Overlapping timers each count in full.
    var todayMinutes: Int {
        let done = entries.compactMap(\.minutes).reduce(0, +)
        let live = running.filter { calendar.isDate($0.day, inSameDayAs: today) }.map(elapsed).reduce(0, +)
        return done + live
    }

    func minutes(on day: Date) -> Int {
        DayFile.entries(in: store.read(day) ?? "").compactMap(\.minutes).reduce(0, +)
    }

    /// Minutes per tag for Monday..today of the current week. An entry with two tags counts for both.
    func weekTotals() -> [(tag: String, minutes: Int)] {
        var monday = calendar.startOfDay(for: now)
        while calendar.component(.weekday, from: monday) != 2 {
            monday = calendar.date(byAdding: .day, value: -1, to: monday)!
        }
        var totals: [String: Int] = [:]
        var day = monday
        while day <= now {
            for e in DayFile.entries(in: store.read(day) ?? "") {
                guard let m = e.minutes else { continue }
                for tag in e.tags.isEmpty ? ["untagged"] : e.tags { totals[tag, default: 0] += m }
            }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return totals.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    // MARK: Plumbing

    private func write(_ day: Date, _ transform: (String) -> String?) {
        do {
            try store.update(day, transform)
            lastError = nil
        } catch {
            lastError = "Could not save: \(error.localizedDescription)"
        }
        revision += 1
        reload()
    }

    func reload() {
        today = Date()
        let text = store.read(today) ?? ""
        entries = DayFile.entries(in: text)
        seenModified = store.modified(today)

        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        running = DayFile.entries(in: store.read(yesterday) ?? "").filter(\.isRunning).map { Timer(day: yesterday, entry: $0) }
            + entries.filter(\.isRunning).map { Timer(day: today, entry: $0) }
    }

    private func tick() {
        now = Date()
        // Pick up a new day or an edit made outside the app.
        if !calendar.isDate(today, inSameDayAs: now) || store.modified(today) != seenModified {
            reload()
            revision += 1
        }
    }
}
