import SwiftUI

/// Full detail page for a Jellyseerr discovery title: backdrop hero with
/// poster, ratings and request action, then (for series) a season/episode
/// browser, cast, recommendations and similar titles. Selecting a related
/// title pushes another detail page; selecting a cast member pushes a person
/// page.
struct SeerDetailView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var ambience: Ambience
    @Environment(\.detailPush) private var push
    @StateObject private var prefetcher = SeerPrefetchCoordinator()

    let media: SeerResult

    @State private var details: SeerDetails?
    @State private var ratings: SeerRatings?
    @State private var recommendations: [SeerResult] = []
    @State private var similar: [SeerResult] = []

    @State private var selectedSeason: Int?
    @State private var episodes: [SeerEpisode] = []
    @State private var loadingEpisodes = false
    @State private var episodeError = false
    /// Episodes already fetched this session, keyed by season, so revisiting a
    /// season is instant and never re-hits the flaky endpoint.
    @State private var episodesBySeason: [Int: [SeerEpisode]] = [:]
    @State private var prefetchingSeasons: Set<Int> = []
    /// Focusing a season chip loads it (hover-to-load), no click needed.
    @FocusState private var focusedSeason: Int?

    @State private var showRequestSheet = false
    @State private var requestDone = false
    @State private var canceling = false
    @State private var requestError: String?
    @State private var requestOptions: [SeerRequestOption] = []
    @State private var loadingRequestOptions = false
    /// Seasons we've requested this session, so their badges flip immediately.
    @State private var pendingSeasons: Set<Int> = []
    /// Give the request button initial focus instead of the back button.
    @FocusState private var requestFocused: Bool

    private var status: SeerMediaStatus {
        if requestDone { return .pending }
        return details?.mediaInfo?.status ?? media.status
    }

    private var regularSeasons: [SeerSeason] {
        (details?.seasons ?? [])
            .filter { $0.seasonNumber > 0 }
            .sorted { $0.seasonNumber < $1.seasonNumber }
    }

    private func seasonStatus(_ n: Int) -> SeerMediaStatus {
        if pendingSeasons.contains(n) { return .pending }
        return details?.mediaInfo?.seasons?.first { $0.seasonNumber == n }?.status ?? .unknown
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                header
                seasonsSection
                castShelf
                SeerShelf(title: "Recommendations", items: recommendations,
                          onSelect: { push(.seer($0)) },
                          onPrefetch: prefetchRelated)
                SeerShelf(title: "Similar Titles", items: similar,
                          onSelect: { push(.seer($0)) },
                          onPrefetch: prefetchRelated)
            }
            .padding(.bottom, 80)
        }
        .ignoresSafeArea()
        .detailBackButton()
        .defaultFocus($requestFocused, true)
        .task { await load() }
        .task(id: selectedSeason) { await loadEpisodesForSelection() }
        .sheet(isPresented: $showRequestSheet) {
            SeerRequestSheet(media: media,
                             seasons: regularSeasons,
                             requestOptions: requestOptions,
                             loadingRequestOptions: loadingRequestOptions,
                             statusFor: seasonStatus) { seasons, option in
                guard let seer = appState.jellyseerr else { return "Not connected to Jellyseerr." }
                do {
                    try await seer.request(media, seasons: seasons, option: option)
                    if media.isMovie {
                        requestDone = true
                    } else {
                        pendingSeasons.formUnion(seasons)
                    }
                    await refreshDetails()
                    return nil
                } catch {
                    return "Request failed. \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: media.backdropURL ?? media.posterURL)
                .frame(maxWidth: .infinity)
                .frame(height: 700)
                .clipped()

            LinearGradient(
                colors: [Theme.background, Theme.background.opacity(0.4), .clear],
                startPoint: .bottom, endPoint: .top)
            LinearGradient(
                colors: [Theme.background.opacity(0.9), .clear],
                startPoint: .leading, endPoint: UnitPoint(x: 0.7, y: 0.5))

            HStack(alignment: .bottom, spacing: 44) {
                RemoteImage(url: media.posterURL)
                    .frame(width: 240, height: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.5), radius: 24, y: 10)

                VStack(alignment: .leading, spacing: 18) {
                    Text(media.displayTitle)
                        .font(.system(size: 56, weight: .heavy))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.6), radius: 12, y: 4)

                    if let tagline = details?.tagline, !tagline.isEmpty {
                        Text(tagline)
                            .font(.title3.italic())
                            .foregroundStyle(Theme.textSecondary)
                    }

                    metadataRow

                    ratingsRow

                    if let overview = details?.overview ?? media.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.body)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(4)
                            .frame(maxWidth: 1050, alignment: .leading)
                    }

                    if let requestError {
                        Text(requestError)
                            .font(.callout)
                            .foregroundStyle(Color(hex: 0xFF6B6B))
                    }

                    actions
                }
            }
            .padding(.horizontal, 64)
            .padding(.bottom, 44)
        }
        .focusSection()
    }

    private var metadataRow: some View {
        HStack(spacing: 18) {
            let parts = [
                details?.year ?? media.year,
                details?.lengthLabel,
                media.isMovie ? "Movie" : "Series",
            ].compactMap(\.self)
            Text(parts.joined(separator: "  ·  "))
                .font(.callout.weight(.medium))
                .foregroundStyle(Theme.textSecondary)

            if let genreLine = details?.genreLine {
                Text(genreLine)
                    .font(.callout)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    /// A dedicated line for ratings from every source Jellyseerr resolves:
    /// Rotten Tomatoes critics & audience, IMDb, and TMDB.
    @ViewBuilder
    private var ratingsRow: some View {
        let tmdb = details?.voteAverage ?? media.voteAverage
        let hasAny = ratings?.rt?.criticsScore != nil
            || ratings?.rt?.audienceScore != nil
            || ratings?.imdb?.criticsScore != nil
            || (tmdb ?? 0) > 0
        if hasAny {
            HStack(spacing: 10) {
                if let critics = ratings?.rt?.criticsScore {
                    let rotten = ratings?.rt?.criticsRating?.localizedCaseInsensitiveContains("rotten") == true
                    ratingPill(glyph: .emoji(rotten ? "🤢" : "🍅"),
                               value: "\(critics)%", caption: "Tomatometer")
                }
                if let audience = ratings?.rt?.audienceScore {
                    ratingPill(glyph: .emoji("🍿"), value: "\(audience)%", caption: "Audience")
                }
                if let imdb = ratings?.imdb?.criticsScore, imdb > 0 {
                    ratingPill(glyph: .imdb, value: String(format: "%.1f", imdb), caption: "IMDb")
                }
                if let tmdb, tmdb > 0 {
                    ratingPill(glyph: .symbol("star.fill"), value: String(format: "%.1f", tmdb), caption: "TMDB")
                }
            }
            .padding(.top, 2)
        }
    }

    private enum RatingGlyph {
        case emoji(String)
        case symbol(String)
        case imdb
    }

    private func ratingPill(glyph: RatingGlyph, value: String, caption: String) -> some View {
        HStack(spacing: 8) {
            switch glyph {
            case .emoji(let text):
                Text(text).font(.body)
            case .symbol(let name):
                Image(systemName: name)
                    .font(.subheadline)
                    .foregroundStyle(Color(hex: 0x01B4E4))   // TMDB cyan
            case .imdb:
                Text("IMDb")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color(hex: 0xF5C518)))
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color.white.opacity(0.07)))
    }

    /// Requests attached to this title that the user can still cancel.
    private var cancelableRequestIds: [Int] {
        details?.mediaInfo?.requests?.map(\.id) ?? []
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 20) {
            if status == .available {
                Badge(text: "Already in your library",
                      tint: Color(hex: 0x2AA860).opacity(0.25),
                      textColor: Color(hex: 0x5BE49B))
            } else if media.isTV {
                Button {
                    showRequestSheet = true
                } label: {
                    Label("Request Seasons", systemImage: "plus.circle.fill")
                }
                .buttonStyle(PillButtonStyle(prominent: true))
                .focused($requestFocused)

                if status != .unknown {
                    StatusBadge(status: status)
                }
                cancelButton
            } else {
                switch status {
                case .unknown:
                    Button {
                        showRequestSheet = true
                    } label: {
                        Label("Request", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(PillButtonStyle(prominent: true))
                    .focused($requestFocused)
                default:
                    StatusBadge(status: status)
                    cancelButton
                }
            }
        }
    }

    @ViewBuilder
    private var cancelButton: some View {
        if !cancelableRequestIds.isEmpty {
            Button {
                Task { await cancelRequests() }
            } label: {
                if canceling {
                    ProgressView().tint(.white)
                } else {
                    Label("Cancel Request", systemImage: "xmark.circle")
                }
            }
            .buttonStyle(PillButtonStyle())
            .disabled(canceling)
        }
    }

    // MARK: - Seasons & episodes

    @ViewBuilder
    private var seasonsSection: some View {
        if media.isTV, !regularSeasons.isEmpty {
            VStack(alignment: .leading, spacing: 18) {
                Text("Seasons")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.9))
                    .padding(.horizontal, 64)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(regularSeasons, id: \.seasonNumber) { season in
                            seasonChip(season)
                        }
                    }
                    .padding(.horizontal, 64)
                    .padding(.vertical, 8)
                }
                .scrollClipDisabled()
                .focusSection()
                // Load whichever season the remote is resting on, without a click.
                .onChange(of: focusedSeason) { _, focused in
                    if let focused { selectedSeason = focused }
                }

                episodeStrip
            }
            .padding(.top, 12)
        }
    }

    private func seasonChip(_ season: SeerSeason) -> some View {
        let n = season.seasonNumber
        let st = seasonStatus(n)
        return Button {
            selectedSeason = n
        } label: {
            VStack(spacing: 5) {
                Text(season.displayName)
                if st != .unknown {
                    Text(st.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(statusTint(st))
                }
            }
        }
        .buttonStyle(ChipButtonStyle(isSelected: selectedSeason == n))
        .focused($focusedSeason, equals: n)
    }

    private func statusTint(_ status: SeerMediaStatus) -> Color {
        switch status {
        case .available, .partiallyAvailable: return Color(hex: 0x5BE49B)
        case .processing: return Color(hex: 0x7FB4FF)
        case .pending: return Color(hex: 0xF0B860)
        case .unknown: return Theme.textTertiary
        }
    }

    @ViewBuilder
    private var episodeStrip: some View {
        if loadingEpisodes {
            HStack(spacing: 14) {
                ProgressView().tint(.white)
                Text("Loading episodes…")
                    .font(.callout)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 64)
            .padding(.vertical, 30)
        } else if episodeError {
            HStack(spacing: 20) {
                Text("Couldn't load episodes.")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
                Button {
                    retryEpisodes()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(ChipButtonStyle(isSelected: false))
            }
            .padding(.horizontal, 64)
            .padding(.vertical, 24)
            .focusSection()
        } else if !episodes.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 28) {
                    ForEach(episodes) { episode in
                        SeerEpisodeCard(episode: episode)
                    }
                }
                .padding(.horizontal, 64)
                .padding(.vertical, 20)
            }
            .scrollClipDisabled()
            .focusSection()
        }
    }

    // MARK: - Cast

    @ViewBuilder
    private var castShelf: some View {
        let cast = details?.cast ?? []
        if !cast.isEmpty {
            VStack(alignment: .leading, spacing: 20) {
                Text("Cast")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.9))
                    .padding(.horizontal, 64)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: Theme.shelfSpacing) {
                        ForEach(cast.prefix(20)) { member in
                            CastCard(imageURL: member.imageURL,
                                     name: member.name ?? "",
                                     subtitle: member.character) {
                                push(.seerPerson(member))
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

    // MARK: - Loading & requesting

    private func load() async {
        ambience.set(media.ambientURL)
        guard let seer = appState.jellyseerr else { return }
        async let detailsTask = seer.details(for: media)
        async let ratingsTask = seer.ratings(for: media)
        async let recsTask = seer.recommendations(for: media)
        async let similarTask = seer.similar(to: media)
        async let requestOptionsTask = seer.requestOptions(for: media)
        loadingRequestOptions = true
        details = try? await detailsTask
        ratings = try? await ratingsTask
        recommendations = (try? await recsTask) ?? []
        similar = (try? await similarTask) ?? []
        requestOptions = (try? await requestOptionsTask) ?? []
        loadingRequestOptions = false

        if media.isTV, selectedSeason == nil {
            selectedSeason = regularSeasons.first?.seasonNumber
        }
        if let selectedSeason {
            prefetchEpisodes(around: selectedSeason)
        }
    }

    private func loadEpisodesForSelection() async {
        guard media.isTV, let n = selectedSeason, let seer = appState.jellyseerr else { return }

        // Already fetched this season → show instantly, no network round-trip.
        if let cached = episodesBySeason[n] {
            episodes = cached
            loadingEpisodes = false
            episodeError = false
            prefetchEpisodes(around: n)
            return
        }

        loadingEpisodes = true
        episodeError = false
        episodes = []
        do {
            // The client retries transient failures; if it still throws we
            // surface a Retry button rather than a silent blank.
            let loaded = try await seer.seasonDetails(tvId: media.id, season: n).episodes
            guard !Task.isCancelled else { return }
            episodesBySeason[n] = loaded
            if selectedSeason == n {
                episodes = loaded
                loadingEpisodes = false
                prefetchEpisodes(around: n)
            }
        } catch {
            guard !Task.isCancelled, selectedSeason == n else { return }
            episodes = []
            loadingEpisodes = false
            episodeError = true
        }
    }

    private func prefetchEpisodes(around season: Int) {
        guard media.isTV, let seer = appState.jellyseerr else { return }
        let numbers = regularSeasons.map(\.seasonNumber)
        guard let index = numbers.firstIndex(of: season) else { return }

        let nearby = [index - 1, index + 1, index + 2]
            .filter { numbers.indices.contains($0) }
            .map { numbers[$0] }
            .filter { episodesBySeason[$0] == nil && !prefetchingSeasons.contains($0) }
        guard !nearby.isEmpty else { return }

        prefetchingSeasons.formUnion(nearby)
        Task {
            for number in nearby {
                if let loaded = try? await seer.seasonDetails(tvId: media.id, season: number).episodes {
                    episodesBySeason[number] = loaded
                }
                prefetchingSeasons.remove(number)
            }
        }
    }

    private func retryEpisodes() {
        guard let n = selectedSeason else { return }
        episodesBySeason[n] = nil
        Task { await loadEpisodesForSelection() }
    }

    private func prefetchRelated(_ media: SeerResult) {
        prefetcher.schedule(media, using: appState.jellyseerr)
    }

    /// Re-fetch details so status and cancelable request ids reflect the server.
    private func refreshDetails() async {
        guard let seer = appState.jellyseerr else { return }
        details = try? await seer.refreshDetails(for: media)
    }

    private func cancelRequests() async {
        guard let seer = appState.jellyseerr else { return }
        let ids = cancelableRequestIds
        guard !ids.isEmpty else { return }
        canceling = true
        requestError = nil
        for id in ids {
            do { try await seer.deleteRequest(id: id) }
            catch { requestError = "Couldn't cancel. \(error.localizedDescription)" }
        }
        requestDone = false
        pendingSeasons.removeAll()
        await refreshDetails()
        canceling = false
    }
}

// MARK: - Episode card

/// Wide still + episode number, title, air date and synopsis. Focusable so the
/// row scrolls with the remote.
private struct SeerEpisodeCard: View {
    let episode: SeerEpisode

    private var heading: String {
        if let n = episode.episodeNumber {
            return "\(n). \(episode.name ?? "Episode \(n)")"
        }
        return episode.name ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {} label: {
                RemoteImage(url: episode.stillURL)
                    .frame(width: 380, height: 214)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.card)

            VStack(alignment: .leading, spacing: 5) {
                Text(heading)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.9))
                    .lineLimit(1)
                if let date = episode.airDateLabel {
                    Text(date)
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                }
                if let overview = episode.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(3)
                }
            }
            .frame(width: 380, alignment: .leading)
        }
    }
}

// MARK: - Season request sheet

/// Per-season request picker mirroring Jellyseerr's "Request Series" modal:
/// each season shows its episode count and current availability, and only
/// not-yet-requested seasons can be toggled.
struct SeerRequestSheet: View {
    let media: SeerResult
    let seasons: [SeerSeason]
    let requestOptions: [SeerRequestOption]
    let loadingRequestOptions: Bool
    let statusFor: (Int) -> SeerMediaStatus
    /// Returns an error message, or nil on success.
    let onSubmit: ([Int], SeerRequestOption?) async -> String?

    @Environment(\.dismiss) private var dismiss

    @State private var selected: Set<Int>
    @State private var selectedOptionID: SeerRequestOption.ID?
    @State private var submitting = false
    @State private var error: String?

    init(media: SeerResult, seasons: [SeerSeason],
         requestOptions: [SeerRequestOption],
         loadingRequestOptions: Bool,
         statusFor: @escaping (Int) -> SeerMediaStatus,
         onSubmit: @escaping ([Int], SeerRequestOption?) async -> String?) {
        self.media = media
        self.seasons = seasons
        self.requestOptions = requestOptions
        self.loadingRequestOptions = loadingRequestOptions
        self.statusFor = statusFor
        self.onSubmit = onSubmit
        _selected = State(initialValue: Set(
            seasons.filter { statusFor($0.seasonNumber) == .unknown }.map(\.seasonNumber)))
        _selectedOptionID = State(initialValue: requestOptions.first?.id)
    }

    private var requestableCount: Int {
        seasons.filter { statusFor($0.seasonNumber) == .unknown }.count
    }

    private var selectedOption: SeerRequestOption? {
        requestOptions.first { $0.id == selectedOptionID } ?? requestOptions.first
    }

    private var canSubmit: Bool {
        !submitting && !loadingRequestOptions && (media.isMovie || !selected.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(media.isMovie ? "Request Movie" : "Request Series")
                    .font(.largeTitle.weight(.heavy))
                    .foregroundStyle(Theme.textPrimary)
                Text(media.displayTitle)
                    .font(.title3)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.bottom, 8)

            qualitySection

            if media.isTV {
                HStack {
                    Text("Season")
                    Spacer()
                    Text("Status")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 28)
                .padding(.top, 26)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 12) {
                        allRow
                        ForEach(seasons, id: \.seasonNumber) { season in
                            seasonRow(season)
                        }
                    }
                    .padding(.vertical, 12)
                }
                .frame(maxHeight: 520)
            }

            if let error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(Color(hex: 0xFF6B6B))
                    .padding(.top, 8)
            }

            HStack(spacing: 20) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(PillButtonStyle())
                Button {
                    submit()
                } label: {
                    if submitting {
                        ProgressView().tint(.white)
                    } else {
                        Text(submitTitle)
                    }
                }
                .buttonStyle(PillButtonStyle(prominent: true))
                .disabled(!canSubmit)
            }
            .padding(.top, 24)
        }
        .padding(60)
        .frame(maxWidth: 1080)
        .background(Theme.background)
        .onChange(of: requestOptions) { _, options in
            if selectedOptionID == nil || !options.contains(where: { $0.id == selectedOptionID }) {
                selectedOptionID = options.first?.id
            }
        }
    }

    @ViewBuilder
    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quality Profile")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 28)
                .padding(.top, 22)

            if loadingRequestOptions {
                HStack(spacing: 12) {
                    ProgressView().tint(.white)
                    Text("Loading request settings...")
                        .font(.callout)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.05)))
            } else if requestOptions.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "gearshape")
                        .font(.title3)
                    Text("Default Jellyseerr settings")
                        .font(.callout.weight(.semibold))
                }
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.05)))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(requestOptions) { option in
                            qualityOption(option)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .scrollClipDisabled()
                .focusSection()
            }
        }
    }

    private func qualityOption(_ option: SeerRequestOption) -> some View {
        let isSelected = option.id == selectedOption?.id
        return Button {
            selectedOptionID = option.id
        } label: {
            HStack(spacing: 16) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.textTertiary))

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(option.title)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        if option.isDefault {
                            Badge(text: "Default", tint: Color.white.opacity(0.12), textColor: Theme.textSecondary)
                        }
                    }

                    if !option.subtitle.isEmpty {
                        Text(option.subtitle)
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(width: 420, height: 92, alignment: .leading)
        }
        .buttonStyle(SelectRowStyle())
    }

    private var submitTitle: String {
        if media.isMovie { return "Request Movie" }
        return selected.count == 1 ? "Request 1 Season" : "Request \(selected.count) Seasons"
    }

    private var allRow: some View {
        let allSelected = requestableCount > 0 && selected.count == requestableCount
        return Button {
            if allSelected {
                selected.removeAll()
            } else {
                selected = Set(seasons.filter { statusFor($0.seasonNumber) == .unknown }.map(\.seasonNumber))
            }
        } label: {
            HStack(spacing: 24) {
                Image(systemName: allSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(allSelected ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.textTertiary))
                Text("All Seasons")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }
        }
        .buttonStyle(SelectRowStyle())
        .disabled(requestableCount == 0)
    }

    private func seasonRow(_ season: SeerSeason) -> some View {
        let n = season.seasonNumber
        let st = statusFor(n)
        let requestable = st == .unknown
        let isSelected = selected.contains(n)
        return Button {
            toggle(n)
        } label: {
            HStack(spacing: 24) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.textTertiary))

                VStack(alignment: .leading, spacing: 3) {
                    Text(season.displayName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if let count = season.episodeCount, count > 0 {
                        Text(count == 1 ? "1 Episode" : "\(count) Episodes")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }

                Spacer()

                if st != .unknown {
                    StatusBadge(status: st)
                } else {
                    Text("Not Requested")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .buttonStyle(SelectRowStyle())
        .disabled(!requestable)
    }

    private func toggle(_ n: Int) {
        if selected.contains(n) { selected.remove(n) } else { selected.insert(n) }
    }

    private func submit() {
        submitting = true
        error = nil
        Task {
            let result = await onSubmit(Array(selected).sorted(), selectedOption)
            if let result {
                error = result
                submitting = false
            } else {
                dismiss()
            }
        }
    }
}

/// Full-width selectable row that lights up on focus; dims when disabled.
private struct SelectRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration)
    }

    private struct Row: View {
        @Environment(\.isFocused) private var isFocused
        @Environment(\.isEnabled) private var isEnabled
        let configuration: ButtonStyle.Configuration

        var body: some View {
            configuration.label
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(isFocused ? 0.16 : 0.05))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(isFocused ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.clear),
                                      lineWidth: 3)
                }
                .opacity(isEnabled ? 1 : 0.45)
                .scaleEffect(isFocused ? 1.015 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isFocused)
        }
    }
}
