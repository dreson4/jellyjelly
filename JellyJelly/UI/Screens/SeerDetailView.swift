import SwiftUI

/// Full detail page for a Jellyseerr discovery title: backdrop hero with
/// poster, ratings and request action, then (for series) a season/episode
/// browser, cast, recommendations and similar titles. Selecting a related
/// title pushes another detail page; selecting a cast member pushes a person
/// page.
struct SeerDetailView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var ambience: Ambience

    let media: SeerResult
    let onSelect: (SeerResult) -> Void
    let onSelectPerson: (SeerCastMember) -> Void
    let onRequested: (SeerResult) -> Void

    @State private var details: SeerDetails?
    @State private var ratings: SeerRatings?
    @State private var recommendations: [SeerResult] = []
    @State private var similar: [SeerResult] = []

    @State private var selectedSeason: Int?
    @State private var episodes: [SeerEpisode] = []
    @State private var loadingEpisodes = false

    @State private var showRequestSheet = false
    @State private var isRequesting = false
    @State private var requestDone = false
    @State private var requestError: String?
    /// Seasons we've requested this session, so their badges flip immediately.
    @State private var pendingSeasons: Set<Int> = []

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
                SeerShelf(title: "Recommendations", items: recommendations, onSelect: onSelect)
                SeerShelf(title: "Similar Titles", items: similar, onSelect: onSelect)
            }
            .padding(.bottom, 80)
        }
        .ignoresSafeArea(edges: .top)
        .task { await load() }
        .task(id: selectedSeason) { await loadEpisodesForSelection() }
        .sheet(isPresented: $showRequestSheet) {
            SeerRequestSheet(media: media, seasons: regularSeasons, statusFor: seasonStatus) { seasons in
                guard let seer = appState.jellyseerr else { return "Not connected to Jellyseerr." }
                do {
                    try await seer.request(media, seasons: seasons)
                    pendingSeasons.formUnion(seasons)
                    onRequested(media)
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

            if let critics = ratings?.criticsScore {
                ratingBadge(icon: "rosette", text: "\(critics)%")
            }
            if let audience = ratings?.audienceScore {
                ratingBadge(icon: "popcorn.fill", text: "\(audience)%")
            }
            if let vote = details?.voteAverage ?? media.voteAverage, vote > 0 {
                ratingBadge(icon: "star.fill", text: String(format: "%.1f", vote))
            }
        }
    }

    private func ratingBadge(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(Theme.accentGradient)
            Text(text)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
        }
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

                if status != .unknown {
                    StatusBadge(status: status)
                }
            } else {
                switch status {
                case .unknown:
                    Button {
                        Task { await requestMovie() }
                    } label: {
                        if isRequesting {
                            ProgressView().tint(.white)
                        } else {
                            Label("Request", systemImage: "plus.circle.fill")
                        }
                    }
                    .buttonStyle(PillButtonStyle(prominent: true))
                    .disabled(isRequesting)
                default:
                    if requestDone {
                        Badge(text: "✓ Requested — it's on its way",
                              tint: Color(hex: 0x2AA860).opacity(0.25),
                              textColor: Color(hex: 0x5BE49B))
                    } else {
                        StatusBadge(status: status)
                    }
                }
            }
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
                                onSelectPerson(member)
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
        details = try? await detailsTask
        ratings = try? await ratingsTask
        recommendations = (try? await recsTask) ?? []
        similar = (try? await similarTask) ?? []

        if media.isTV, selectedSeason == nil {
            selectedSeason = regularSeasons.first?.seasonNumber
        }
    }

    private func loadEpisodesForSelection() async {
        guard media.isTV, let n = selectedSeason, let seer = appState.jellyseerr else { return }
        loadingEpisodes = true
        episodes = []
        let loaded = (try? await seer.seasonDetails(tvId: media.id, season: n))?.episodes ?? []
        if !Task.isCancelled {
            episodes = loaded
            loadingEpisodes = false
        }
    }

    private func requestMovie() async {
        guard let seer = appState.jellyseerr else { return }
        isRequesting = true
        requestError = nil
        do {
            try await seer.request(media)
            requestDone = true
            onRequested(media)
        } catch {
            requestError = "Request failed. \(error.localizedDescription)"
        }
        isRequesting = false
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
    let statusFor: (Int) -> SeerMediaStatus
    /// Returns an error message, or nil on success.
    let onSubmit: ([Int]) async -> String?

    @Environment(\.dismiss) private var dismiss

    @State private var selected: Set<Int>
    @State private var submitting = false
    @State private var error: String?

    init(media: SeerResult, seasons: [SeerSeason],
         statusFor: @escaping (Int) -> SeerMediaStatus,
         onSubmit: @escaping ([Int]) async -> String?) {
        self.media = media
        self.seasons = seasons
        self.statusFor = statusFor
        self.onSubmit = onSubmit
        _selected = State(initialValue: Set(
            seasons.filter { statusFor($0.seasonNumber) == .unknown }.map(\.seasonNumber)))
    }

    private var requestableCount: Int {
        seasons.filter { statusFor($0.seasonNumber) == .unknown }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Request Series")
                    .font(.largeTitle.weight(.heavy))
                    .foregroundStyle(Theme.textPrimary)
                Text(media.displayTitle)
                    .font(.title3)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.bottom, 8)

            HStack {
                Text("Season")
                Spacer()
                Text("Status")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 28)
            .padding(.top, 20)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    allRow
                    ForEach(seasons, id: \.seasonNumber) { season in
                        seasonRow(season)
                    }
                }
                .padding(.vertical, 12)
            }
            .frame(maxHeight: 620)

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
                        Text(selected.count == 1 ? "Request 1 Season" : "Request \(selected.count) Seasons")
                    }
                }
                .buttonStyle(PillButtonStyle(prominent: true))
                .disabled(selected.isEmpty || submitting)
            }
            .padding(.top, 24)
        }
        .padding(60)
        .frame(maxWidth: 1080)
        .background(Theme.background)
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
            let result = await onSubmit(Array(selected).sorted())
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
