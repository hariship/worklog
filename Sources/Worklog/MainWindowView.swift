import SwiftUI
import WorklogCore

/// Zim-like window: days, pages and search on the left, a plain markdown editor on the right.
struct MainWindowView: View {
    @ObservedObject var model: WorklogModel
    @ObservedObject var nav: Navigation
    @ObservedObject var notes: NotesSync

    @State private var days: [Date] = []
    @State private var pages: [String] = []
    @State private var newPageName = ""
    @State private var askingForPage = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                TextField("Search", text: $nav.query)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .padding(8)
                if nav.query.isEmpty { sidebar } else { results }
                Divider()
                weekTotals
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 240)
        } detail: {
            DocEditor(model: model, nav: nav, notes: notes)
        }
        .onAppear {
            refresh()
            notes.refreshNoteNames()
        }
        .onChange(of: model.revision) { refresh() }
        .onChange(of: nav.focusSearch) { searchFocused = true }
        .onChange(of: nav.newPageRequest) { askingForPage = true }
        .alert("New page", isPresented: $askingForPage) {
            TextField("Page name", text: $newPageName)
            Button("Create") { createPage() }
            Button("Cancel", role: .cancel) { newPageName = "" }
        }
    }

    private var sidebar: some View {
        List(selection: Binding(get: { nav.doc }, set: { if let d = $0 { nav.doc = d } })) {
            Section {
                ForEach(pages, id: \.self) { name in
                    Label(name, systemImage: "doc.text").tag(Doc.page(name))
                }
            } header: {
                HStack {
                    Text("Pages")
                    Spacer()
                    Button { askingForPage = true } label: { Image(systemName: "plus") }
                        .buttonStyle(.borderless).help("New page")
                }
            }
            Section("Apple Notes") {
                // Opens in Notes rather than here; `[[notes:Name]]` links do the same.
                Button { notes.open(notes.noteName) } label: {
                    Label(notes.noteName, systemImage: "note.text")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open in Apple Notes")
            }
            Section("Days") {
                ForEach(days, id: \.self) { day in
                    HStack {
                        Text(day, format: .dateTime.day().month(.abbreviated).weekday(.abbreviated))
                        Spacer()
                        let m = model.minutes(on: day)
                        Text(m > 0 ? DayFile.duration(m) : "-").monospacedDigit().foregroundStyle(.secondary)
                    }
                    .tag(Doc.day(day))
                }
            }
        }
    }

    private var results: some View {
        List(model.store.search(nav.query)) { hit in
            HitRow(hit: hit) { nav.doc = hit.doc }
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

    private func createPage() {
        let name = newPageName.trimmingCharacters(in: .whitespaces)
        newPageName = ""
        guard !name.isEmpty else { return }
        if model.store.readPage(name) == nil { model.save(Store.pageTemplate(name), for: .page(name), force: true) }
        nav.doc = .page(name)
    }

    private func refresh() {
        let calendar = Calendar.current
        var list = model.store.days().map { calendar.startOfDay(for: $0) }
        let today = calendar.startOfDay(for: Date())
        if !list.contains(today) { list.insert(today, at: 0) }
        days = list
        pages = model.store.pages()
    }
}

/// One search result or backlink: where it is, and the line.
struct HitRow: View {
    let hit: Store.Hit
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 2) {
                switch hit.doc {
                case let .day(date):
                    Text(date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
                        .font(.caption).foregroundStyle(.secondary)
                case let .page(name):
                    Label(name, systemImage: "doc.text").font(.caption).foregroundStyle(.secondary)
                }
                Text(hit.line).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Editor for one day or page. Saves on every change; reloads when the file changes elsewhere.
struct DocEditor: View {
    @ObservedObject var model: WorklogModel
    @ObservedObject var nav: Navigation
    @ObservedObject var notes: NotesSync
    @State private var text = ""
    @State private var loaded: Doc?
    @State private var backlinks: [Store.Hit] = []
    @AppStorage("backlinksOpen") private var backlinksOpen = true

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            MarkdownEditor(text: $text, openLink: follow) { partial in
                Links.completions(for: partial, pages: model.store.pages(), notes: notes.noteNames)
            }
                .onChange(of: text) { _, new in
                    // Only user edits: skip the programmatic load.
                    if loaded == nav.doc { model.save(new, for: nav.doc) }
                }
            if case .page = nav.doc { backlinkPanel }
        }
        .onAppear(perform: load)
        .onChange(of: nav.doc) { load() }
        .onChange(of: model.revision) {
            let onDisk = model.store.read(nav.doc) ?? model.store.template(nav.doc)
            if onDisk != text { load() } else { loadBacklinks() }
        }
    }

    @ViewBuilder private var header: some View {
        HStack {
            switch nav.doc {
            case let .day(day):
                Text(day, format: .dateTime.weekday(.wide).day().month(.wide).year()).font(.headline)
                Spacer()
                Group {
                    Button { shift(day, -1) } label: { Image(systemName: "chevron.left") }
                    Button("Today") { nav.doc = .day(Calendar.current.startOfDay(for: Date())) }
                    Button { shift(day, 1) } label: { Image(systemName: "chevron.right") }
                }
                .buttonStyle(.borderless)
            case let .page(name):
                Label(name, systemImage: "doc.text").font(.headline)
                Spacer()
                Text("Link here with [[\(name)]]").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .padding(10)
    }

    /// Every line elsewhere that links here with [[Name]] or uses the matching #tag.
    private var backlinkPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            Button { backlinksOpen.toggle() } label: {
                HStack {
                    Image(systemName: backlinksOpen ? "chevron.down" : "chevron.right").frame(width: 10)
                    Text("Linked from (\(backlinks.count))")
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12).padding(.vertical, 8)
            if backlinksOpen {
                if backlinks.isEmpty {
                    Text("Nothing links here yet. Use [[name]] or the matching #tag in a log line.")
                        .font(.callout).foregroundStyle(.secondary)
                        .padding(.horizontal, 12).padding(.bottom, 10)
                } else {
                    List(backlinks) { hit in HitRow(hit: hit) { nav.doc = hit.doc } }
                        .frame(height: 180)
                }
            }
        }
    }

    /// `[[notes:Name]]` opens Apple Notes; anything else is a day or page here.
    private func follow(_ target: String) {
        if let note = Links.noteName(target) { notes.open(note) } else { nav.doc = Links.doc(for: target) }
    }

    private func load() {
        loaded = nil
        text = model.store.read(nav.doc) ?? model.store.template(nav.doc)
        loadBacklinks()
        let doc = nav.doc
        DispatchQueue.main.async { loaded = doc }
    }

    private func loadBacklinks() {
        if case let .page(name) = nav.doc { backlinks = model.store.backlinks(to: name) } else { backlinks = [] }
    }

    private func shift(_ day: Date, _ n: Int) {
        nav.doc = .day(Calendar.current.date(byAdding: .day, value: n, to: day)!)
    }
}

/// Shared between the popover (which opens the window) and the window itself.
@MainActor
final class Navigation: ObservableObject {
    @Published var doc: Doc = .day(Calendar.current.startOfDay(for: Date()))
    @Published var query = ""
    @Published var focusSearch = 0
    /// Bumped by File > New Page.
    @Published var newPageRequest = 0
}
