import SwiftUI
import VaqueroKit

/// Searches the message archive by meaning.
struct SearchScreen: View {
    @Environment(AppModel.self) private var model
    @State private var text = ""
    @State private var contact = ""
    @State private var hits: [SearchHit]?
    @State private var error: String?
    @State private var searching = false

    var body: some View {
        List {
            SwiftUI.Section {
                TextField("How did we apply for the visa?", text: $text)
                    .onSubmit(search)
                TextField("Contact or chat (optional)", text: $contact)
                    .onSubmit(search)
                Button(action: search) {
                    Label(searching ? "Searching…" : "Search", systemImage: "magnifyingglass")
                }
                .disabled(text.isEmpty || searching)
            }
            if let error {
                Text(error).foregroundStyle(.red)
            }
            if let hits {
                SwiftUI.Section("\(hits.count) matches") {
                    ForEach(hits) { HitRow(hit: $0) }
                }
            }
        }
        .navigationTitle("Search")
    }

    private func search() {
        guard !text.isEmpty else { return }
        searching = true
        error = nil
        let query = SearchQuery(text: text, contact: contact.isEmpty ? nil : contact)
        Task {
            do {
                hits = try await model.search(query)
            } catch {
                self.error = error.localizedDescription
            }
            searching = false
        }
    }
}

private struct HitRow: View {
    let hit: SearchHit

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: hit.channel.symbol).foregroundStyle(.secondary)
                Text(hit.chat).font(.subheadline.weight(.medium))
                Spacer()
                Text(hit.at.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(hit.text).textSelection(.enabled)
            Text("\(hit.sender) · match \(hit.score.formatted(.percent.precision(.fractionLength(0))))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
