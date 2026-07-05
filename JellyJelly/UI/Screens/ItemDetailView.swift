import SwiftUI

/// Detail page for a movie or series: full-bleed backdrop, actions,
/// seasons + episodes for series, and a similar-titles shelf.
struct ItemDetailView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var ambience: Ambience
    @Environment(\.detailPush) private var push
    let itemId: String

    @State private var item: BaseItem?
    @State private var seasons: [BaseItem] = []
    @State private var selectedSeasonId: String?
    @State private var episodes: [BaseItem] = []
    @State private var similar: [BaseItem] = []
    @State private var loadError: String?
    @State private var playback: PlaybackRequest?
    /// Give the Play button initial focus instead of the back button.
    @FocusState private var playFocused: Bool

    var body: some View {
        Group {
            if let item {
                content(for: item)
            } else if let loadError {
                ErrorView(message: loadError) { await load() }
            } else {
                LoadingView()
            }
        }
        .detailBackButton()
        .defaultFocus($playFocused, true)
        .task { await load() }
        .fullScreenCover(item: $playback) { request in
            PlayerScreen(request: request)
        }
        .onChange(of: playback) { previous, current in
            // Refresh watch state when returning from playback.
            if previous != nil && current == nil {
                Task { await load() }
            }
        }
    }

    private func content(for item: BaseItem) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                header(for: item)

                if item.isSeries {
                    seasonPicker
                    episodeShelf
                }

                castShelf(for: item)

                NavigationShelf(title: "More Like This", items: similar) { push(.item($0.id)) }
            }
            .padding(.bottom, 80)
        }
        .ignoresSafeArea()
    }

    // MARK: - Header

    private func header(for item: BaseItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: appState.jellyfin?.backdropURL(for: item, maxWidth: 1920))
                .frame(maxWidth: .infinity)
                .frame(height: 640)
                .clipped()

            LinearGradient(
                colors: [Theme.background, Theme.background.opacity(0.4), .clear],
                startPoint: .bottom, endPoint: .top)
            LinearGradient(
                colors: [Theme.background.opacity(0.9), .clear],
                startPoint: .leading, endPoint: UnitPoint(x: 0.7, y: 0.5))

            VStack(alignment: .leading, spacing: 20) {
                Text(item.name ?? "")
                    .font(.system(size: 56, weight: .heavy))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.6), radius: 12, y: 4)

                HStack(spacing: 16) {
                    Text(item.metadataLine)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                    if let genres = item.genres, !genres.isEmpty {
                        Text(genres.prefix(3).joined(separator: " · "))
                            .font(.callout)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }

                if let overview = item.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.body)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(4)
                        .frame(maxWidth: 900, alignment: .leading)
                }

                actions(for: item)
            }
            .padding(.horizontal, 64)
            .padding(.bottom, 44)
        }
        .focusSection()
    }

    private func actions(for item: BaseItem) -> some View {
        HStack(spacing: 20) {
            Button {
                Task { await play(item) }
            } label: {
                Label(playLabel(for: item), systemImage: "play.fill")
            }
            .buttonStyle(PillButtonStyle(prominent: true))
            .focused($playFocused)

            if item.resumePositionSeconds > 60 {
                Button {
                    playback = PlaybackRequest(item: item, fromBeginning: true)
                } label: {
                    Label("From Beginning", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(PillButtonStyle())
            }

            Button {
                Task { await toggleWatched(item) }
            } label: {
                Image(systemName: item.userData?.played == true
                      ? "checkmark.circle.fill" : "checkmark.circle")
            }
            .buttonStyle(IconButtonStyle())

            Button {
                Task { await toggleFavorite(item) }
            } label: {
                Image(systemName: item.userData?.isFavorite == true ? "heart.fill" : "heart")
            }
            .buttonStyle(IconButtonStyle())
        }
    }

    private func playLabel(for item: BaseItem) -> String {
        if item.isSeries { return "Play" }
        if let label = remainingLabel(totalTicks: item.runTimeTicks,
                                      positionTicks: item.userData?.playbackPositionTicks) {
            return "Resume · \(label)"
        }
        return "Play"
    }

    // MARK: - Seasons & episodes

    private var seasonPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                ForEach(seasons) { season in
                    Button(season.name ?? "Season") {
                        selectedSeasonId = season.id
                        Task { await loadEpisodes() }
                    }
                    .buttonStyle(ChipButtonStyle(isSelected: season.id == selectedSeasonId))
                }
            }
            .padding(.horizontal, 64)
            .padding(.vertical, 16)
        }
        .scrollClipDisabled()
        .focusSection()
    }

    private var episodeShelf: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: Theme.shelfSpacing) {
                ForEach(episodes) { episode in
                    EpisodeCard(episode: episode) {
                        playback = PlaybackRequest(item: episode)
                    }
                }
            }
            .padding(.horizontal, 64)
            .padding(.vertical, 24)
        }
        .scrollClipDisabled()
        .focusSection()
    }

    // MARK: - Cast

    @ViewBuilder
    private func castShelf(for item: BaseItem) -> some View {
        let cast = (item.people ?? []).filter { $0.isActor }.prefix(20)
        if !cast.isEmpty {
            VStack(alignment: .leading, spacing: 20) {
                Text("Cast")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.9))
                    .padding(.horizontal, 64)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: Theme.shelfSpacing) {
                        ForEach(Array(cast)) { person in
                            VStack(spacing: 12) {
                                Button {
                                    push(.person(person))
                                } label: {
                                    PersonHeadshot(url: appState.jellyfin?.personImageURL(person))
                                }
                                .buttonStyle(CircleButtonStyle())

                                VStack(spacing: 2) {
                                    Text(person.name ?? "")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Theme.textPrimary.opacity(0.9))
                                        .lineLimit(1)
                                    if let role = person.role, !role.isEmpty {
                                        Text(role)
                                            .font(.caption2)
                                            .foregroundStyle(Theme.textTertiary)
                                            .lineLimit(1)
                                    }
                                }
                                .frame(width: 168)
                                .multilineTextAlignment(.center)
                            }
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

    // MARK: - Data

    private func load() async {
        guard let jellyfin = appState.jellyfin else { return }
        do {
            var resolved = try await jellyfin.item(id: itemId)
            // Detail pages are for movies and series; an episode opens its show.
            if resolved.isEpisode, let seriesId = resolved.seriesId {
                resolved = try await jellyfin.item(id: seriesId)
            }
            let loaded = resolved
            item = loaded
            ambience.set(jellyfin.ambientImageURL(for: loaded))
            async let similarTask = jellyfin.similar(to: loaded.id)

            if loaded.isSeries {
                let loadedSeasons = try await jellyfin.seasons(seriesId: loaded.id)
                seasons = loadedSeasons
                if selectedSeasonId == nil {
                    selectedSeasonId = loadedSeasons.first(where: { ($0.indexNumber ?? 0) > 0 })?.id
                        ?? loadedSeasons.first?.id
                }
                await loadEpisodes()
            }
            similar = (try? await similarTask) ?? []
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func loadEpisodes() async {
        guard let jellyfin = appState.jellyfin,
              let seriesId = item?.id, let seasonId = selectedSeasonId else { return }
        episodes = (try? await jellyfin.episodes(seriesId: seriesId, seasonId: seasonId)) ?? []
    }

    /// Movies play directly; series play their next-up (or first) episode.
    private func play(_ item: BaseItem) async {
        guard let jellyfin = appState.jellyfin else { return }
        if item.isSeries {
            let next = (try? await jellyfin.nextUp(seriesId: item.id, limit: 1))?.first
                ?? episodes.first
            if let next { playback = PlaybackRequest(item: next) }
        } else {
            playback = PlaybackRequest(item: item)
        }
    }

    private func toggleWatched(_ item: BaseItem) async {
        guard let jellyfin = appState.jellyfin else { return }
        let target = !(item.userData?.played ?? false)
        try? await jellyfin.setPlayed(target, itemId: item.id)
        await load()
    }

    private func toggleFavorite(_ item: BaseItem) async {
        guard let jellyfin = appState.jellyfin else { return }
        let target = !(item.userData?.isFavorite ?? false)
        try? await jellyfin.setFavorite(target, itemId: item.id)
        await load()
    }
}

// MARK: - Episode card

struct EpisodeCard: View {
    @EnvironmentObject private var appState: AppState
    let episode: BaseItem
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: action) {
                ZStack(alignment: .bottom) {
                    RemoteImage(url: appState.jellyfin?.wideImageURL(for: episode))
                        .frame(width: Theme.wideCardWidth, height: Theme.wideCardHeight)
                    if let fraction = episode.playedFraction {
                        ProgressStripe(fraction: fraction)
                    }
                    if episode.userData?.played == true {
                        WatchedCheck()
                    }
                }
                .frame(width: Theme.wideCardWidth, height: Theme.wideCardHeight)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.card)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(episode.indexNumber.map { "\($0). " } ?? "")\(episode.name ?? "")")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.85))
                    .lineLimit(1)
                if let overview = episode.overview {
                    Text(overview)
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(2)
                }
            }
            .frame(width: Theme.wideCardWidth, alignment: .leading)
        }
    }
}
