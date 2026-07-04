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
    @State private var upcomingTV: [SeerResult] = []
    @State private var movieGenres: [SeerGenre] = []
    @State private var tvGenres: [SeerGenre] = []
    @State private var isLoading = true
    @State private var loadError: String?

    // Curated networks and studios, by TMDB id.
    private static let networks: [SeerCategory] = [
        .init(title: "Netflix", kind: .network(213)),
        .init(title: "Disney+", kind: .network(2739)),
        .init(title: "Prime Video", kind: .network(1024)),
        .init(title: "Apple TV+", kind: .network(2552)),
        .init(title: "HBO", kind: .network(49)),
        .init(title: "Hulu", kind: .network(453)),
        .init(title: "Max", kind: .network(3186)),
        .init(title: "Paramount+", kind: .network(4330)),
        .init(title: "Peacock", kind: .network(3353)),
        .init(title: "AMC", kind: .network(174)),
        .init(title: "FX", kind: .network(88)),
        .init(title: "Showtime", kind: .network(67)),
    ]
    private static let studios: [SeerCategory] = [
        .init(title: "Walt Disney", kind: .studio(2)),
        .init(title: "Pixar", kind: .studio(3)),
        .init(title: "Warner Bros.", kind: .studio(174)),
        .init(title: "Universal", kind: .studio(33)),
        .init(title: "Columbia", kind: .studio(5)),
        .init(title: "Paramount", kind: .studio(4)),
        .init(title: "Marvel Studios", kind: .studio(420)),
        .init(title: "20th Century", kind: .studio(25)),
        .init(title: "Lionsgate", kind: .studio(1632)),
        .init(title: "A24", kind: .studio(41077)),
    ]

    private func genreCategories(_ genres: [SeerGenre], tv: Bool) -> [SeerCategory] {
        genres.compactMap { genre in
            guard let id = genre.id, let name = genre.name else { return nil }
            return SeerCategory(title: name, kind: tv ? .tvGenre(id) : .movieGenre(id))
        }
    }

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
                header

                SeerShelf(title: "Trending Now", items: trending) { router.open(.seer($0)) }
                SeerShelf(title: "Popular Movies", items: popularMovies) { router.open(.seer($0)) }
                CategoryShelf(title: "Movie Genres", categories: genreCategories(movieGenres, tv: false)) {
                    router.open(.discoverCategory($0))
                }
                SeerShelf(title: "Coming Soon", items: upcoming) { router.open(.seer($0)) }
                CategoryShelf(title: "Studios", categories: Self.studios) { router.open(.discoverCategory($0)) }
                SeerShelf(title: "Popular Series", items: popularTV) { router.open(.seer($0)) }
                CategoryShelf(title: "Series Genres", categories: genreCategories(tvGenres, tv: true)) {
                    router.open(.discoverCategory($0))
                }
                SeerShelf(title: "Upcoming Series", items: upcomingTV) { router.open(.seer($0)) }
                CategoryShelf(title: "Networks", categories: Self.networks) { router.open(.discoverCategory($0)) }
            }
            .padding(.bottom, 80)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Discover")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(Theme.textPrimary)

            HStack(spacing: 14) {
                Button {
                    router.open(.requests)
                } label: {
                    Label("Requests", systemImage: "clock.arrow.circlepath")
                }
                .buttonStyle(ChipButtonStyle(isSelected: false))
            }
            .focusSection()
        }
        .padding(.horizontal, 64)
        .padding(.top, 24)
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
        async let upcomingTVTask = seer.upcomingTV()
        async let movieGenresTask = seer.genres("movie")
        async let tvGenresTask = seer.genres("tv")

        var firstError: Error?
        do { trending = try await trendingTask } catch { firstError = error }
        do { popularMovies = try await moviesTask } catch { firstError = firstError ?? error }
        do { popularTV = try await tvTask } catch { firstError = firstError ?? error }
        upcoming = (try? await upcomingTask) ?? []
        upcomingTV = (try? await upcomingTVTask) ?? []
        movieGenres = (try? await movieGenresTask) ?? []
        tvGenres = (try? await tvGenresTask) ?? []

        if trending.isEmpty, popularMovies.isEmpty, popularTV.isEmpty, upcoming.isEmpty,
           let firstError {
            loadError = firstError.localizedDescription
        }
        isLoading = false
    }
}
