import SwiftUI

enum LibraryKind {
    case movies
    case shows

    var title: String { self == .movies ? "Movies" : "Shows" }
    var includeTypes: String { self == .movies ? "Movie" : "Series" }
}

enum LibrarySort: String, CaseIterable, Identifiable {
    case recentlyAdded = "Recently Added"
    case name = "A–Z"
    case rating = "Top Rated"

    var id: String { rawValue }
    var sortBy: String {
        switch self {
        case .recentlyAdded: return "DateCreated"
        case .name: return "SortName"
        case .rating: return "CommunityRating"
        }
    }
    var sortOrder: String { self == .name ? "Ascending" : "Descending" }
}

/// Paged poster grid over a whole library (all movies or all shows).
struct LibraryView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: Router
    let kind: LibraryKind

    @State private var items: [BaseItem] = []
    @State private var totalCount = 0
    @State private var sort: LibrarySort = .recentlyAdded
    @State private var hasLoaded = false
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var reloadTask: Task<Void, Never>?

    private let pageSize = 60
    private let columns = [GridItem(.adaptive(minimum: Theme.posterWidth), spacing: Theme.shelfSpacing)]

    var body: some View {
        Group {
            if !hasLoaded {
                LoadingView()
            } else if let loadError, items.isEmpty {
                ErrorView(message: loadError) { await reload() }
            } else {
                grid
            }
        }
        .task {
            if !hasLoaded { await reload() }
        }
    }

    private var grid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                header

                LazyVGrid(columns: columns, spacing: 48) {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 12) {
                            Button {
                                router.open(.item(item.id))
                            } label: {
                                PosterCardLabel(item: item)
                            }
                            .buttonStyle(.card)
                            .ambientSource(appState.jellyfin?.ambientImageURL(for: item))
                            Text(item.name ?? "")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                                .frame(width: Theme.posterWidth, alignment: .leading)
                        }
                        .onAppear {
                            if item.id == items.last?.id { Task { await loadMore() } }
                        }
                    }
                }
                .padding(.horizontal, 64)
                .padding(.vertical, 24)
                .opacity(isLoading ? 0.55 : 1)
                .animation(.easeInOut(duration: 0.25), value: isLoading)
                // Own focus section so "down" from the sort chips always lands
                // here, even when no card sits geometrically beneath them.
                .focusSection()
            }
            .padding(.bottom, 80)
        }
        .scrollClipDisabled()
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            Text(kind.title)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
            if totalCount > 0 {
                Text("\(totalCount)")
                    .font(.title3)
                    .foregroundStyle(Theme.textTertiary)
            }
            if isLoading {
                ProgressView()
                    .tint(Theme.accentB)
                    .scaleEffect(0.7)
            }
            Spacer()
            // Explicit chips rather than a segmented picker: tvOS segmented
            // controls switch selection as focus passes over them, which forced
            // a reload just to reach the grid below.
            HStack(spacing: 14) {
                ForEach(LibrarySort.allCases) { option in
                    Button(option.rawValue) {
                        select(option)
                    }
                    .buttonStyle(ChipButtonStyle(isSelected: option == sort))
                }
            }
            .focusSection()
        }
        .padding(.horizontal, 64)
        .padding(.top, 24)
    }

    // MARK: - Data

    private func select(_ option: LibrarySort) {
        guard option != sort else { return }
        sort = option
        reloadTask?.cancel()
        reloadTask = Task { await reload() }
    }

    /// Replaces the grid contents atomically: the old grid stays on screen
    /// while the new order loads, so re-sorting never blanks the view or
    /// throws focus away.
    private func reload() async {
        guard let jellyfin = appState.jellyfin else { return }
        isLoading = true
        loadError = nil
        do {
            let page = try await jellyfin.items(
                includeTypes: kind.includeTypes,
                sortBy: sort.sortBy, sortOrder: sort.sortOrder,
                startIndex: 0, limit: pageSize)
            guard !Task.isCancelled else { return }
            items = page.items
            totalCount = page.totalRecordCount ?? page.items.count
        } catch {
            if !Task.isCancelled { loadError = error.localizedDescription }
        }
        hasLoaded = true
        isLoading = false
    }

    private func loadMore() async {
        guard !isLoading, hasLoaded, items.count < totalCount,
              let jellyfin = appState.jellyfin else { return }
        isLoading = true
        do {
            let page = try await jellyfin.items(
                includeTypes: kind.includeTypes,
                sortBy: sort.sortBy, sortOrder: sort.sortOrder,
                startIndex: items.count, limit: pageSize)
            items += page.items
            totalCount = page.totalRecordCount ?? items.count
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
