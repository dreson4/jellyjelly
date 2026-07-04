import SwiftUI

/// Jellyseerr-powered discovery: trending/popular shelves, search, and full
/// detail pages with requesting.
struct DiscoverView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: Router

    @State private var trending: [SeerResult] = []
    @State private var popularMovies: [SeerResult] = []
    @State private var popularTV: [SeerResult] = []
    @State private var upcoming: [SeerResult] = []
    @State private var isLoading = true
    @State private var loadError: String?

    @State private var searchQuery = ""
    @State private var searchResults: [SeerResult] = []
    @State private var isSearching = false
    @State private var searchError: String?

    var body: some View {
        NavigationStack {
            Group {
                // Search first: a failed shelf load must never block searching.
                if !searchQuery.isEmpty {
                    searchContent
                } else if isLoading {
                    LoadingView()
                } else if let loadError, trending.isEmpty {
                    ErrorView(message: loadError) { await load() }
                } else {
                    shelves
                }
            }
            .searchable(text: $searchQuery, placement: .automatic, prompt: "Find something new…")
        }
        .task { await load() }
        .task(id: searchQuery) { await runSearch() }
    }

    // MARK: - Shelves

    private var shelves: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Discover")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 64)
                    .padding(.top, 24)

                SeerShelf(title: "Trending Now", items: trending) { router.open(.seer($0)) }
                SeerShelf(title: "Popular Movies", items: popularMovies) { router.open(.seer($0)) }
                SeerShelf(title: "Popular Series", items: popularTV) { router.open(.seer($0)) }
                SeerShelf(title: "Coming Soon", items: upcoming) { router.open(.seer($0)) }
            }
            .padding(.bottom, 80)
        }
    }

    // MARK: - Search

    @ViewBuilder
    private var searchContent: some View {
        if !searchResults.isEmpty {
            searchGrid
        } else if isSearching {
            LoadingView()
        } else if let searchError {
            searchPrompt(icon: "exclamationmark.triangle",
                         text: "Search failed. \(searchError)")
        } else {
            searchPrompt(icon: "questionmark.circle",
                         text: "No matches for “\(searchQuery)”")
        }
    }

    private var searchGrid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Theme.posterWidth), spacing: Theme.shelfSpacing)],
                      spacing: 48) {
                ForEach(searchResults) { media in
                    SeerPosterCard(media: media) { router.open(.seer(media)) }
                }
            }
            .padding(.horizontal, 64)
            .padding(.vertical, 40)
        }
        .scrollClipDisabled()
    }

    private func searchPrompt(icon: String, text: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 52))
                .foregroundStyle(Theme.textTertiary)
            Text(text)
                .font(.title3)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 1000)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func runSearch() async {
        guard !searchQuery.isEmpty else {
            searchResults = []
            searchError = nil
            isSearching = false
            return
        }
        isSearching = true
        searchError = nil
        // Debounce so we don't query per keystroke.
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled, let seer = appState.jellyseerr else { return }
        do {
            let results = try await seer.search(query: searchQuery)
            guard !Task.isCancelled else { return }
            searchResults = results
            isSearching = false
        } catch {
            guard !Task.isCancelled else { return }
            searchResults = []
            searchError = error.localizedDescription
            isSearching = false
        }
    }

    // MARK: - Loading

    private func load() async {
        guard let seer = appState.jellyseerr else { return }
        isLoading = trending.isEmpty && popularMovies.isEmpty && popularTV.isEmpty
        loadError = nil

        // Jellyseerr's TMDB-backed endpoints fail transiently now and then;
        // load each shelf independently so one hiccup can't blank the tab.
        async let trendingTask = seer.trending()
        async let moviesTask = seer.popularMovies()
        async let tvTask = seer.popularTV()
        async let upcomingTask = seer.upcomingMovies()

        var firstError: Error?
        do { trending = try await trendingTask } catch { firstError = error }
        do { popularMovies = try await moviesTask } catch { firstError = firstError ?? error }
        do { popularTV = try await tvTask } catch { firstError = firstError ?? error }
        upcoming = (try? await upcomingTask) ?? []

        if trending.isEmpty, popularMovies.isEmpty, popularTV.isEmpty, upcoming.isEmpty,
           let firstError {
            loadError = firstError.localizedDescription
        }
        isLoading = false
    }
}
