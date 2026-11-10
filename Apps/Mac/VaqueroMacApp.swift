import SwiftUI
import VaqueroUI

@main
struct VaqueroMacApp: App {
    @State private var model: AppModel

    init() {
        let model = AppModel()
        model.connect()
        _model = State(initialValue: model)
    }

    var body: some Scene {
        Window("Vaquero", id: "main") {
            MacRoot()
                .environment(model)
                .frame(minWidth: 900, minHeight: 560)
        }
        Settings {
            SettingsForm()
                .environment(model)
                .frame(width: 440)
        }
        MenuBarExtra {
            MenuBarPanel().environment(model)
        } label: {
            Label("\(model.queue.count)", systemImage: model.queue.isEmpty ? "tray" : "tray.full")
        }
        .menuBarExtraStyle(.window)
    }
}
