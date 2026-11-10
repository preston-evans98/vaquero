#if os(macOS)
import SwiftUI
import VaqueroKit

/// The Mac window: a sidebar of screens and the chosen screen.
public struct MacRoot: View {
    @Environment(AppModel.self) private var model
    @SceneStorage("destination") private var destination = Destination.queue

    public init() {}

    public var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { destination }, set: { destination = $0 ?? .queue })) {
                SwiftUI.Section {
                    ForEach(Destination.work) { row($0) }
                }
                SwiftUI.Section("Config") {
                    ForEach(Destination.config) { row($0) }
                }
                SwiftUI.Section {
                    row(.health)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
            .safeAreaInset(edge: .bottom) {
                ConnectionStatus()
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        } detail: {
            NavigationStack {
                destination.screen
            }
        }
        .failureAlert(model)
    }

    private func row(_ destination: Destination) -> some View {
        Label(destination.title, systemImage: destination.symbol)
            .badge(destination.badge(model))
            .tag(destination)
    }
}

/// The menu bar panel: the top item of the queue in full, for quick answers.
public struct MenuBarPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(model.queue.count) waiting").font(.headline)
                Spacer()
                ConnectionStatus().font(.caption)
            }
            if !model.staleHeartbeats.isEmpty {
                Label("Stale: \(model.staleHeartbeats.map(\.component).joined(separator: ", "))", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
            }
            if let item = model.queue.first {
                QueueDetail(item: item) {}
                    .id(item.id)
                    .frame(height: 480)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            Button("Open Vaquero") {
                openWindow(id: "main")
                NSApp.activate()
            }
        }
        .padding(14)
        .frame(width: 420)
    }
}
#endif
