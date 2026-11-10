#if os(iOS)
import SwiftUI
import VaqueroKit

/// The iPhone app: tabs for the daily screens, and the rest under More.
public struct PhoneRoot: View {
    @Environment(AppModel.self) private var model

    public init() {}

    public var body: some View {
        TabView {
            ForEach([Destination.queue, .agents, .log, .search]) { destination in
                Tab(destination.title, systemImage: destination.symbol) {
                    NavigationStack { destination.screen }
                }
                .badge(destination.badge(model))
            }
            Tab("More", systemImage: "ellipsis") {
                NavigationStack { more }
            }
            .badge(Destination.health.badge(model))
        }
        .failureAlert(model)
    }

    private var more: some View {
        List {
            SwiftUI.Section {
                link(.decisions)
                link(.health)
            }
            SwiftUI.Section("Config") {
                ForEach(Destination.config) { link($0) }
            }
            SwiftUI.Section {
                NavigationLink { SettingsForm() } label: { Label("Settings", systemImage: "gearshape") }
                ConnectionStatus()
            }
        }
        .navigationTitle("More")
    }

    private func link(_ destination: Destination) -> some View {
        NavigationLink { destination.screen } label: {
            Label(destination.title, systemImage: destination.symbol)
                .badge(destination.badge(model))
        }
    }
}
#endif
