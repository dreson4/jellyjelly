import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appState: AppState

    @State private var heroItems: [BaseItem] = []
    @State private var resumeItems: [BaseItem] = []
    @State private var nextUp: [BaseItem] = []
    @State private var latestByLibrary: [(library: BaseItem, items: [BaseItem])] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var playback: PlaybackRequest?
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isLoading {
                    LoadingView()
                } else if let loadError {
                    ErrorView(message: loadError) { await load() }
                } else {
                    content
                }
            }
            .navigationDestination(for: BaseItem.self) { item in
                ItemDetailView(itemId: item.id)
            }
            .navigationDestination(for: BaseItemPerson.self) { person in
                PersonItemsView(person: person)
            }
        }
        .task { await load() }
        .fullScreenCover(item: $playback) { request in
            PlayerScreen(request: request)
        }
        .onChange(of: playback) { previous, current in
            // Refresh shelves (Continue Watching, watched state) after playback.
            if previous != nil && current == nil {
                Task { await load() }
            }
        }
    }

    private var content: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                HeroBanner(
                    items: heroItems,
                    onPlay: { playback = PlaybackRequest(item: $0) },
                    onDetails: { path.append($0) })

                Shelf(title: "Continue Watching", items: resumeItems, style: .wide) { item in
                    playback = PlaybackRequest(item: item)
                }
                Shelf(title: "Next Up", items: nextUp, style: .wide) { item in
                    playback = PlaybackRequest(item: item)
                }
                ForEach(latestByLibrary, id: \.library.id) { entry in
                    NavigationShelf(title: "New in \(entry.library.name ?? "Library")",
                                    items: entry.items)
                }
            }
            .padding(.bottom, 80)
        }
        .ignoresSafeArea(edges: .top)
    }

    private func load() async {
        isLoading = heroItems.isEmpty
        loadError = nil
        guard let jellyfin = appState.jellyfin else { return }
        do {
            async let viewsTask = jellyfin.userViews()
            async let resumeTask = jellyfin.resumeItems()
            async let nextUpTask = jellyfin.nextUp()

            let views = try await viewsTask
            resumeItems = try await resumeTask
            nextUp = try await nextUpTask

            let mediaLibraries = views.filter {
                $0.collectionType == "movies" || $0.collectionType == "tvshows"
            }
            var shelves: [(BaseItem, [BaseItem])] = []
            for library in mediaLibraries {
                let latest = try await jellyfin.latest(parentId: library.id)
                shelves.append((library, latest))
            }
            latestByLibrary = shelves

            // Latest-in-shows returns episodes; the hero should feature whole
            // titles, so episodes are swapped for their series.
            var heroCandidates: [BaseItem] = []
            var seenIds = Set<String>()
            for candidate in shelves.flatMap(\.1) {
                let resolved: BaseItem?
                if candidate.isEpisode, let seriesId = candidate.seriesId {
                    resolved = try? await jellyfin.item(id: seriesId)
                } else {
                    resolved = candidate
                }
                guard let resolved,
                      resolved.backdropImageTags?.isEmpty == false || resolved.parentBackdropItemId != nil,
                      resolved.overview != nil,
                      seenIds.insert(resolved.id).inserted else { continue }
                heroCandidates.append(resolved)
            }
            heroItems = Array(heroCandidates.shuffled().prefix(5))
            isLoading = false
        } catch {
            loadError = error.localizedDescription
            isLoading = false
        }
    }
}

/// Shelf whose cards push a detail screen.
struct NavigationShelf: View {
    @EnvironmentObject private var appState: AppState
    let title: String
    let items: [BaseItem]

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 20) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.9))
                    .padding(.horizontal, 64)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: Theme.shelfSpacing) {
                        ForEach(items) { item in
                            NavigationLink(value: item) {
                                PosterCardLabel(item: item)
                            }
                            .buttonStyle(.card)
                            .ambientSource(appState.jellyfin?.ambientImageURL(for: item))
                        }
                    }
                    .padding(.horizontal, 64)
                    .padding(.vertical, 24)
                }
                .scrollClipDisabled()
            }
            .focusSection()
        }
    }
}

/// Poster artwork used as a NavigationLink label.
struct PosterCardLabel: View {
    @EnvironmentObject private var appState: AppState
    let item: BaseItem

    var body: some View {
        ZStack(alignment: .bottom) {
            RemoteImage(url: appState.jellyfin?.posterURL(for: item))
                .frame(width: Theme.posterWidth, height: Theme.posterHeight)
            if let fraction = item.playedFraction {
                ProgressStripe(fraction: fraction)
            }
        }
        .frame(width: Theme.posterWidth, height: Theme.posterHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 24) {
            ProgressView()
                .tint(Theme.accentB)
                .scaleEffect(1.4)
            Text("Loading…")
                .font(.callout)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorView: View {
    let message: String
    let retry: () async -> Void

    var body: some View {
        VStack(spacing: 28) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 56))
                .foregroundStyle(Theme.textTertiary)
            Text(message)
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 800)
            Button("Try Again") {
                Task { await retry() }
            }
            .buttonStyle(PillButtonStyle(prominent: true))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
