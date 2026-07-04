import SwiftUI

/// A paged poster grid for one Jellyseerr discovery category — a genre, TV
/// network or studio. Reached from the Discover home's category rows.
struct DiscoverCategoryView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.detailPush) private var push

    let category: SeerCategory

    @State private var items: [SeerResult] = []
    @State private var page = 1
    @State private var loading = true
    @State private var loadingMore = false
    @State private var reachedEnd = false
    @State private var loadFailed = false

    private let columns = [GridItem(.adaptive(minimum: Theme.posterWidth), spacing: Theme.shelfSpacing)]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                Text(category.title)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 64)
                    .padding(.top, 120)

                if loading && items.isEmpty {
                    ProgressView().tint(Theme.accentB).scaleEffect(1.4)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 100)
                } else if items.isEmpty {
                    emptyState
                } else {
                    grid
                }
            }
            .padding(.bottom, 80)
        }
        .scrollClipDisabled()
        .detailBackButton()
        .task { await loadFirst() }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 20) {
            Text(loadFailed ? "Couldn't load these titles." : "Nothing here right now.")
                .font(.title3)
                .foregroundStyle(Theme.textSecondary)
            if loadFailed {
                Button {
                    Task { await loadFirst(force: true) }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(PillButtonStyle(prominent: true))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 90)
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 48) {
            ForEach(items) { media in
                SeerPosterCard(media: media) { push(.seer(media)) }
                    .onAppear {
                        if media.id == items.last?.id { Task { await loadMore() } }
                    }
            }
        }
        .padding(.horizontal, 64)
        .padding(.vertical, 12)
        .focusSection()
    }

    private func loadFirst(force: Bool = false) async {
        guard force || items.isEmpty, let seer = appState.jellyseerr else { return }
        loading = true
        loadFailed = false
        do {
            items = try await seer.discover(category, page: 1)
        } catch {
            loadFailed = true
        }
        page = 1
        loading = false
    }

    private func loadMore() async {
        guard !loadingMore, !reachedEnd, !loading, let seer = appState.jellyseerr else { return }
        loadingMore = true
        let next = (try? await seer.discover(category, page: page + 1)) ?? []
        if next.isEmpty {
            reachedEnd = true
        } else {
            let existing = Set(items.map { "\($0.mediaType)-\($0.id)" })
            items += next.filter { !existing.contains("\($0.mediaType)-\($0.id)") }
            page += 1
        }
        loadingMore = false
    }
}
