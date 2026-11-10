import SwiftUI
import VaqueroUI

@main
struct VaqueroiOSApp: App {
    @State private var model: AppModel

    init() {
        let model = AppModel()
        model.connect()
        _model = State(initialValue: model)
    }

    var body: some Scene {
        WindowGroup {
            PhoneRoot().environment(model)
        }
    }
}
