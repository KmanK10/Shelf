import SwiftUI

@main
struct ShelfApp: App {
    @State private var model = ShelfModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}
