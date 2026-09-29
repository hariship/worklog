import SwiftUI
import WorklogCore

/// The menu bar popover, kept to what matters right now: one input, TickTick suggestions under it,
/// and the running timers. The full day lives in the main window.
struct PopoverView: View {
    @ObservedObject var model: WorklogModel
    @ObservedObject var tick: TickTickModel
    var openDay: () -> Void
    var openSearch: () -> Void
    var revealFolder: () -> Void
    var openSettings: () -> Void

    @State private var draft = ""
    @State private var flash: String?
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            input
            suggestions
            if !model.running.isEmpty {
                Divider()
                timers
            }
            if let error = model.lastError {
                Text(error).font(.caption).foregroundStyle(.red).padding(8)
            }
            Divider()
            footer
        }
        .frame(width: 360)
        .onAppear {
            inputFocused = true
            tick.refresh(minAge: 60)
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
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Text(flash ?? "\(DayFile.duration(model.todayMinutes)) today")
                .foregroundStyle(flash == nil ? Color.secondary : Color.green)
                .monospacedDigit()
            Spacer()
            Button("Open log", systemImage: "arrow.up.right.square", action: openDay)
                .buttonStyle(.borderless)
            Menu {
                Button("Search", action: openSearch)
                Button("Open folder", action: revealFolder)
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
        model.log(text, startTimer: startTimer)
        draft = ""
        if !startTimer { show("Logged at \(DayFile.clock(DayFile.minutesSinceMidnight(Date())))") }
    }

    private func start(_ text: String) {
        model.log(text, startTimer: true)
        draft = ""
    }

    /// Point entries don't show in the popover any more, so confirm them briefly in the footer.
    private func show(_ message: String) {
        flash = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if flash == message { flash = nil } }
    }
}
