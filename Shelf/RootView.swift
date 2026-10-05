import SwiftUI

struct RootView: View {
    @Environment(ShelfModel.self) private var model

    var body: some View {
        Group {
            if model.isRestoring {
                ProgressView("Opening Shelf")
                    .controlSize(.large)
            } else if model.session == nil {
                LoginView()
            } else {
                MainTabView()
            }
        }
        .task {
            await model.restoreIfNeeded()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10 * 60 * 1_000_000_000)
                await model.refreshTokensQuietly()
            }
        }
        .fullScreenCover(item: Bindable(model).activeReader) { launch in
            ReaderScreen(launch: launch)
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Library", systemImage: "books.vertical") }
            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
