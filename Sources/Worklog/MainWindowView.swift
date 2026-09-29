import SwiftUI
import WorklogCore

/// Zim-like window: days and search on the left, a plain markdown editor on the right.
struct MainWindowView: View {
    @ObservedObject var model: WorklogModel
    @ObservedObject var nav: Navigation

    @State private var days: [Date] = []
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                TextField("Search", text: $nav.query)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .padding(8)
                if nav.query.isEmpty { dayList } else { results }
                Divider()
                weekTotals
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        } detail: {
            DayEditor(model: model, nav: nav)
        }
        .onAppear(perform: refreshDays)
        .onChange(of: model.revision) { refreshDays() }
        .onChange(of: nav.focusSearch) { searchFocused = true }
    }

    private var dayList: some View {
        List(selection: Binding(get: { nav.day }, set: { if let d = $0 { nav.day = d } })) {
            ForEach(days, id: \.self) { day in
                HStack {
                    Text(day, format: .dateTime.day().month(.abbreviated).weekday(.abbreviated))
                    Spacer()
                    let m = model.minutes(on: day)
                    Text(m > 0 ? DayFile.duration(m) : "-").monospacedDigit().foregroundStyle(.secondary)
                }
                .tag(day)
            }
        }
    }

    private var results: some View {
        List(model.store.search(nav.query)) { hit in
            Button {
                nav.day = hit.date
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(hit.date, format: .dateTime.day().month(.abbreviated).year())
                        .font(.caption).foregroundStyle(.secondary)
                    Text(hit.line).lineLimit(2)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var weekTotals: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("This week").font(.caption).foregroundStyle(.secondary)
            let totals = model.weekTotals()
            if totals.isEmpty { Text("No timed entries").font(.caption).foregroundStyle(.secondary) }
            ForEach(totals.prefix(6), id: \.tag) { t in
                HStack {
                    Text(t.tag == "untagged" ? t.tag : "#\(t.tag)")
                    Spacer()
                    Text(DayFile.duration(t.minutes)).monospacedDigit()
                }
                .font(.callout)
            }
        }
        .padding(10)
    }

    private func refreshDays() {
        var list = model.store.days()
        let today = Calendar.current.startOfDay(for: Date())
        if !list.contains(where: { Calendar.current.isDate($0, inSameDayAs: today) }) { list.insert(today, at: 0) }
        days = list.map { Calendar.current.startOfDay(for: $0) }
    }
}

/// Editor for one day file. Saves on every change; reloads when the file changes elsewhere.
struct DayEditor: View {
    @ObservedObject var model: WorklogModel
    @ObservedObject var nav: Navigation
    @State private var text = ""
    @State private var loadedDay: Date?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(nav.day, format: .dateTime.weekday(.wide).day().month(.wide).year()).font(.headline)
                Spacer()
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                Button("Today") { nav.day = Calendar.current.startOfDay(for: Date()) }
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
            }
            .buttonStyle(.borderless)
            .padding(10)
            Divider()
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .onChange(of: text) { _, new in
                    // Only user edits: skip the programmatic load.
                    if loadedDay == nav.day { model.save(new, for: nav.day) }
                }
        }
        .onAppear(perform: load)
        .onChange(of: nav.day) { load() }
        .onChange(of: model.revision) {
            let onDisk = model.store.read(nav.day) ?? DayFile.template(for: nav.day)
            if onDisk != text { load() }
        }
    }

    private func load() {
        loadedDay = nil
        text = model.store.read(nav.day) ?? DayFile.template(for: nav.day)
        DispatchQueue.main.async { loadedDay = nav.day }
    }

    private func shift(_ days: Int) {
        nav.day = Calendar.current.date(byAdding: .day, value: days, to: nav.day)!
    }
}

/// Shared between the popover (which opens the window) and the window itself.
@MainActor
final class Navigation: ObservableObject {
    @Published var day = Calendar.current.startOfDay(for: Date())
    @Published var query = ""
    @Published var focusSearch = 0
}
