import SwiftUI
import WorklogCore

/// The menu bar popover, kept to what matters right now: one input, TickTick suggestions under it,
/// and the running timers. The full day lives in the main window.
struct PopoverView: View {
    @ObservedObject var model: WorklogModel
    @ObservedObject var tick: TickTickModel
    @ObservedObject var notes: NotesSync
    var openDay: () -> Void
    var openSearch: () -> Void
    var revealFolder: () -> Void
    var openSettings: () -> Void

    @State private var draft = ""
    /// Sends the line to the Apple Notes note too. On by default, remembers the last choice.
    @AppStorage("weeklyChip") private var weekly = true
    @State private var flash: (text: String, isError: Bool)?
    @FocusState private var inputFocused: Bool
    /// The line being edited in place, as `HH:mm[-HH:mm] text`.
    @State private var editing: (entry: Entry, day: Date)?
    @State private var editText = ""
    @FocusState private var editFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            input
            suggestions
            if !model.running.isEmpty {
                Divider()
                timers
            }
            if let last = model.lastEntry {
                Divider()
                lastRow(last)
            }
            if let error = model.lastError {
                Text(error).font(.caption).foregroundStyle(.red).padding(8)
            }
            Divider()
            footer
        }
        .frame(width: 360)
        .onChange(of: notes.message?.at) {
            if let m = notes.message { show(m.text, isError: m.isError) }
        }
        .onAppear {
            if let notice = model.notice {
                model.notice = nil
                DispatchQueue.main.async { show(notice) }
            }
            inputFocused = true
            tick.refresh(minAge: 60)
            notes.refreshNoteNames()
        }
    }

    // MARK: Input

    private var input: some View {
        HStack(spacing: 8) {
            TextField("What are you working on?", text: $draft)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($inputFocused)
                .onSubmit { submit(startTimer: false) }
            Button { weekly.toggle() } label: {
                Text("#weekly")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(weekly ? Color.accentColor : Color.secondary.opacity(0.15)))
                    .foregroundStyle(weekly ? Color.white : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(weekly ? "Lines you log (Return) are also added to \(notes.noteName). Timers are not. Click to turn off."
                      : "Click to also add logged lines to \(notes.noteName).")
            Button { submit(startTimer: true) } label: { Image(systemName: "play.fill") }
                .buttonStyle(.borderless)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Log and start a timer (Command Return). Return alone just logs.")
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    /// Empty input: TickTick tasks due today. Typing: open tasks that match.
    @ViewBuilder private var suggestions: some View {
        if let partial = Links.openLinkPrefix(before: draft) {
            linkSuggestions(partial)
        } else {
            taskSuggestions
        }
    }

    /// After `[[`: pages and Apple Notes to link. Clicking one closes the link.
    @ViewBuilder private func linkSuggestions(_ partial: String) -> some View {
        let targets = Links.completions(for: partial, pages: model.store.pages(), notes: notes.noteNames)
        VStack(alignment: .leading, spacing: 0) {
            if targets.isEmpty && !partial.isEmpty {
                Text("New page \"\(partial)\" when you close with ]]").font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 14).padding(.vertical, 3)
            }
            ForEach(targets, id: \.self) { target in
                Button {
                    draft = String(draft.dropLast(partial.count)) + target + "]] "
                    inputFocused = true
                } label: {
                    Label(target, systemImage: Links.noteName(target) == nil ? "doc.text" : "note.text")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14).padding(.vertical, 3)
            }
        }
        .font(.callout)
        .padding(.bottom, 8)
    }

    @ViewBuilder private var taskSuggestions: some View {
        let typing = !draft.trimmingCharacters(in: .whitespaces).isEmpty
        let tasks = typing ? tick.matches(draft) : Array(tick.today.prefix(4))
        if !tasks.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(tasks) { suggestion($0) }
            }
            .padding(.bottom, 8)
        } else if !typing, tick.status != .ready, tick.status != .connecting {
            Button("Connect TickTick to see today's tasks", action: openSettings)
                .buttonStyle(.link).font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.bottom, 10)
        }
    }

    private func suggestion(_ task: TickTick.Task) -> some View {
        let overdue = (task.due ?? .distantFuture) < Calendar.current.startOfDay(for: Date())
        return HStack(spacing: 8) {
            Image(systemName: "circle").font(.caption2).foregroundStyle(.tertiary)
            // Clicking the title fills the input so it can be edited first.
            Button { draft = task.logText; inputFocused = true } label: {
                Text(task.title).lineLimit(1).foregroundStyle(overdue ? Color.red : Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text(task.projectName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Button { start(task.logText) } label: { Image(systemName: "play.fill").font(.caption) }
                .buttonStyle(.borderless).foregroundStyle(.secondary).help("Start a timer on this task")
        }
        .font(.callout)
        .padding(.horizontal, 14).padding(.vertical, 3)
    }

    // MARK: Timers

    private var timers: some View {
        VStack(spacing: 0) {
            ForEach(model.running) { timer in
                if editing?.entry == timer.entry {
                    editField
                } else {
                    HStack(spacing: 8) {
                        Circle().fill(Color.green).frame(width: 7, height: 7)
                        Text(timer.entry.text).lineLimit(1)
                        Spacer(minLength: 6)
                        Text(DayFile.duration(model.elapsed(timer))).monospacedDigit().foregroundStyle(.secondary)
                        Button { model.stop(timer) } label: { Image(systemName: "stop.fill") }
                            .buttonStyle(.borderless).help("Stop this timer")
                    }
                    .font(.callout)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .contextMenu { entryMenu(timer.entry, day: timer.day) }
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: Last line, edit and delete

    @ViewBuilder private func lastRow(_ e: Entry) -> some View {
        if editing?.entry == e {
            editField
        } else {
            HStack(spacing: 8) {
                Text("last").font(.caption).foregroundStyle(.tertiary)
                Text(DayFile.clock(e.start)).monospacedDigit().foregroundStyle(.secondary)
                Text(e.text).lineLimit(1).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if let m = e.minutes { Text(DayFile.duration(m)).monospacedDigit().foregroundStyle(.tertiary) }
                Button { beginEdit(e, day: model.today) } label: { Image(systemName: "pencil") }
                    .buttonStyle(.borderless).help("Edit")
                Button { delete(e, day: model.today) } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).help("Delete")
            }
            .font(.callout)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .contentShape(Rectangle())
            .contextMenu { entryMenu(e, day: model.today) }
        }
    }

    @ViewBuilder private func entryMenu(_ e: Entry, day: Date) -> some View {
        Button("Edit") { beginEdit(e, day: day) }
        Button("Delete", role: .destructive) { delete(e, day: day) }
    }

    /// The line as you'd type it: `10:05-11:20 text`. The duration is recomputed on save.
    private func rawLine(_ e: Entry) -> String {
        let time = e.isRunning ? "\(DayFile.clock(e.start))-"
            : e.end.map { "\(DayFile.clock(e.start))-\(DayFile.clock($0))" } ?? DayFile.clock(e.start)
        return "\(time) \(e.text)"
    }

    private var editField: some View {
        HStack(spacing: 8) {
            TextField("10:05-11:20 what you did #tag", text: $editText)
                .textFieldStyle(.roundedBorder)
                .focused($editFocused)
                .onSubmit(saveEdit)
                .onExitCommand { editing = nil }
            Button("Save", action: saveEdit).keyboardShortcut(.defaultAction)
        }
        .font(.callout)
        .padding(.horizontal, 14).padding(.vertical, 6)
    }

    private func beginEdit(_ e: Entry, day: Date) {
        editText = rawLine(e)
        editing = (e, day)
        DispatchQueue.main.async { editFocused = true }
    }

    private func saveEdit() {
        guard let editing else { return }
        if model.edit(editing.entry, on: editing.day, to: editText) {
            self.editing = nil
            show("Saved")
        } else {
            show("Start with a time, like 10:05 or 10:05-11:20", isError: true)
        }
    }

    private func delete(_ e: Entry, day: Date) {
        editing = nil
        model.delete(e, on: day)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            if let undo = model.undo, flash == nil {
                Text("Deleted").foregroundStyle(.secondary)
                Button("Undo") { model.undoDelete() }.buttonStyle(.link)
                    .help("Put back \"\(undo.label)\"")
            } else {
                Text(flash?.text ?? "\(DayFile.duration(model.todayMinutes)) today")
                    .foregroundStyle(flash == nil ? Color.secondary : flash!.isError ? Color.red : Color.green)
                    .lineLimit(2)
                    .monospacedDigit()
            }
            Spacer()
            Button("Open log", systemImage: "arrow.up.right.square", action: openDay)
                .buttonStyle(.borderless)
            Menu {
                Button("Search", action: openSearch)
                Button("Open folder", action: revealFolder)
                Button("Open \(notes.noteName)") { notes.open(notes.noteName) }
                Button("Send this week to \(notes.noteName)") { notes.sendWeek(monday: NotesSync.monday(of: Date())) }
                Button("Settings...", action: openSettings)
                Divider()
                Button("Quit Worklog") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .font(.callout)
        .padding(.horizontal, 14).padding(.vertical, 9)
    }

    // MARK: Actions

    private func submit(startTimer: Bool) {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        // Only lines you log go to the note; timers are work tracking, not notes.
        model.log(startTimer ? text : tagged(text), startTimer: startTimer)
        draft = ""
        if !startTimer { show("Logged at \(DayFile.clock(DayFile.minutesSinceMidnight(Date())))") }
    }

    private func start(_ text: String) {
        model.log(text, startTimer: true)
        draft = ""
    }

    private func tagged(_ text: String) -> String {
        weekly && !DayFile.tags(in: text).contains(NotesHTML.weeklyTag) ? "\(text) #weekly" : text
    }

    /// Point entries don't show in the popover any more, so confirm them briefly in the footer.
    private func show(_ message: String, isError: Bool = false) {
        flash = (message, isError)
        DispatchQueue.main.asyncAfter(deadline: .now() + (isError || message.count > 30 ? 6 : 2)) { if flash?.text == message { flash = nil } }
    }
}
