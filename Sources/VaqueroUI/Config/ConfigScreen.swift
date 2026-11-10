import SwiftUI
import VaqueroKit

/// Loads one config file, lets the content edit it, and saves it with the version it started from.
/// When the file changes on the server, the screen reloads unless the owner has unsaved edits.
struct ConfigScreen<D: ConfigDocument, Content: View>: View {
    @Environment(AppModel.self) private var model
    @ViewBuilder let content: (Binding<D>) -> Content

    @State private var saved: Versioned<D>?
    @State private var value = D.empty
    @State private var conflict = false
    @State private var error: String?

    private var dirty: Bool { saved.map { $0.value != value } ?? false }

    var body: some View {
        Group {
            if saved != nil {
                content($value)
            } else if let error {
                Placeholder(title: "Couldn't load \(D.file.label.lowercased())", symbol: "exclamationmark.triangle", detail: error)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(D.file.label)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if dirty {
                    Button("Revert", systemImage: "arrow.uturn.backward") { value = saved?.value ?? D.empty }
                }
                Button("Save", systemImage: "checkmark") { Task { await save() } }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!dirty)
            }
        }
        .task(id: model.configRevision) {
            if !dirty { await load() }
        }
        .alert("\(D.file.label) changed on the server", isPresented: $conflict) {
            Button("Keep my version") { Task { await save(overwrite: true) } }
            Button("Load theirs", role: .destructive) { Task { await load() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Someone else saved this file after you opened it.")
        }
    }

    private func load() async {
        do {
            let loaded = try await model.readConfig(D.self)
            saved = loaded
            value = loaded.value
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func save(overwrite: Bool = false) async {
        do {
            var etag = saved?.etag ?? ""
            if overwrite { etag = try await model.readConfig(D.self).etag }
            let result = try await model.writeConfig(Versioned(etag: etag, value: value))
            saved = result
            value = result.value
        } catch ClientError.conflict {
            conflict = true
        } catch {
            model.failure = error.localizedDescription
        }
    }
}
