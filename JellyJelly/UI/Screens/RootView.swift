import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var ambience: Ambience
    @StateObject private var router = Router()

    private enum Tab: Hashable {
        case home, movies, shows, search, discover, settings
    }

    // Explicit selection so structural re-evaluation (sheets, server edits
    // bumping `generation`) can never silently reset the TabView to Home.
    @State private var selection: Tab = .home

    var body: some View {
        // Each tab is keyed to the connection generation so switching or
        // editing servers reloads content without yanking the user out of
        // their current tab.
        TabView(selection: $selection) {
            HomeView()
                .id(appState.generation)
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(Tab.home)

            LibraryView(kind: .movies)
                .id(appState.generation)
                .tabItem { Label("Movies", systemImage: "film.fill") }
                .tag(Tab.movies)

            LibraryView(kind: .shows)
                .id(appState.generation)
                .tabItem { Label("Shows", systemImage: "tv.fill") }
                .tag(Tab.shows)

            SearchView()
                .id(appState.generation)
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(Tab.search)

            if appState.jellyseerr != nil {
                DiscoverView()
                    .id(appState.generation)
                    .tabItem { Label("Discover", systemImage: "sparkles") }
                    .tag(Tab.discover)
            }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(Tab.settings)
        }
        .environmentObject(router)
        .onChange(of: appState.jellyseerr == nil) { _, seerGone in
            // If the selected Discover tab just disappeared, land somewhere real.
            if seerGone && selection == .discover { selection = .home }
        }
        // Detail pages present here, above the whole TabView, so opening a title
        // hides the tabs entirely and Menu/Back returns to the tab you were on.
        .fullScreenCover(item: $router.route) { route in
            DetailFlow(root: route)
                .environmentObject(appState)
                .environmentObject(ambience)
                .environmentObject(router)
        }
    }
}
