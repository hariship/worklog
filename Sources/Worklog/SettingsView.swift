import SwiftUI
import WorklogCore

struct SettingsView: View {
    @ObservedObject var tick: TickTickModel
    @ObservedObject var notes: NotesSync
    let root: URL

    @State private var clientId = ""
    @State private var clientSecret = ""
    @State private var note: String?

    var body: some View {
        Form {
            Section("Notes folder") {
                Text(root.path).textSelection(.enabled).foregroundStyle(.secondary)
            }

            Section("Apple Notes") {
                TextField("Note name", text: $notes.noteName)
                Text("Lines tagged #weekly are added to this note as numbered items. A summary of the week is added on Sunday evening, or from the ⋯ menu.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("TickTick") {
                statusRow
                TextField("Client ID", text: $clientId)
                SecureField(tick.hasSecret ? "Client secret (saved, leave blank to keep)" : "Client secret", text: $clientSecret)
                HStack {
                    Button("Save") {
                        tick.saveCredentials(clientId: clientId, clientSecret: clientSecret)
                        clientSecret = ""
                        note = "Saved."
                    }
                    .disabled(clientId.isEmpty)
                    if FileManager.default.fileExists(atPath: TickTickModel.mcpEnv.path) {
                        Button("Import from ticktick-mcp") {
                            note = tick.importFromMCP() ? "Imported client ID and secret." : "No credentials found in ticktick-mcp/.env."
                            clientId = tick.clientId
                        }
                    }
                }
                if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
                Text("App credentials come from developer.ticktick.com/manage. The redirect URI there must be \(TickTick.redirectURI).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 500)
        .onAppear { clientId = tick.clientId }
    }

    @ViewBuilder private var statusRow: some View {
        HStack {
            switch tick.status {
            case .notConfigured:
                Label("Add app credentials below", systemImage: "key").foregroundStyle(.secondary)
                Spacer()
            case .disconnected:
                Label("Not connected", systemImage: "circle").foregroundStyle(.secondary)
                Spacer()
                Button("Connect") { tick.connect() }
            case .connecting:
                ProgressView().controlSize(.small)
                Text("Finish signing in in your browser")
                Spacer()
                Button("Cancel") { tick.cancelConnect() }
            case .ready:
                Label("Connected, \(tick.tasks.count) open tasks", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Spacer()
                Button("Sync now") { tick.refresh() }.disabled(tick.syncing)
                Button("Disconnect") { tick.disconnect() }
            case let .failed(message):
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).lineLimit(3)
                Spacer()
                Button("Reconnect") { tick.connect() }
            }
        }
    }
}
