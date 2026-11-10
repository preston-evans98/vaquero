import SwiftUI
import VaqueroKit

/// Opens a lead under the chief of staff, or a project session under a lead.
struct NewSessionSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let parent: Agent

    @State private var name = ""
    @State private var brief = ""
    @State private var modelName = "opus"
    @State private var fork = false
    @State private var working = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name, prompt: Text(parent.spec.role == .chiefOfStaff ? "real-estate" : "export-prices"))
                Picker("Model", selection: $modelName) {
                    ForEach(AgentSpec.models, id: \.self) { Text($0.capitalized).tag($0) }
                }
                Toggle("Start as a copy of \(parent.id)", isOn: $fork)
                Section("Brief") {
                    TextEditor(text: $brief)
                        .frame(minHeight: 120)
                }
                if let error {
                    Text(error).foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(parent.spec.role == .chiefOfStaff ? "New lead" : "New project session")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Open", action: open)
                        .disabled(working || name.isEmpty || brief.isEmpty)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 360)
    }

    private func open() {
        working = true
        let session = NewSession(name: name.lowercased(), parent: parent.id, model: modelName, brief: brief, fork: fork)
        Task {
            do {
                _ = try await model.open(session)
                dismiss()
            } catch {
                self.error = error.localizedDescription
                working = false
            }
        }
    }
}
