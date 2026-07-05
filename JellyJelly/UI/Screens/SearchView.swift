import SwiftUI

/// Searches the Jellyfin library (movies + series).
struct SearchView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: Router

    @State private var query = ""
    @State private var results: [BaseItem] = []
    @State private var isSearching = false

    private let columns = [GridItem(.adaptive(minimum: Theme.posterWidth), spacing: Theme.shelfSpacing)]

    var body: some View {
        NavigationStack {
            Group {
                if query.isEmpty {
                    prompt(icon: "magnifyingglass", text: "Search your library")
                } else if results.isEmpty && !isSearching {
                    prompt(icon: "questionmark.circle", text: "No results for “\(query)”")
                } else {
                    grid
                }
            }
            .searchable(text: $query, placement: .automatic, prompt: "Movies, shows…")
        }
        .task(id: query) {
            guard !query.isEmpty else {
                results = []
                return
            }
            // Debounce so we don't query per keystroke.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let jellyfin = appState.jellyfin else { return }
            isSearching = true
            results = (try? await jellyfin.search(term: query)) ?? []
            isSearching = false
        }
    }

    private var grid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 48) {
                ForEach(results) { item in
                    VStack(alignment: .leading, spacing: 12) {
                        Button {
                            router.open(.item(item.id))
                        } label: {
                            PosterCardLabel(item: item)
                        }
                        .buttonStyle(.card)
                        Text(item.name ?? "")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .frame(width: Theme.posterWidth, alignment: .leading)
                    }
                }
            }
            .padding(.horizontal, 64)
            .padding(.vertical, 40)
        }
        .scrollClipDisabled()
    }

    private func prompt(icon: String, text: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 52))
                .foregroundStyle(Theme.textTertiary)
            Text(text)
                .font(.title3)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
