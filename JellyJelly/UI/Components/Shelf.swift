import SwiftUI

enum ShelfStyle {
    case poster
    case wide
}

/// Netflix-style horizontal shelf: section title + scrolling row of cards.
struct Shelf: View {
    @EnvironmentObject private var appState: AppState

    let title: String
    let items: [BaseItem]
    let style: ShelfStyle
    let onSelect: (BaseItem) -> Void

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 20) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.9))
                    .padding(.horizontal, 64)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: Theme.shelfSpacing) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            switch style {
                            case .poster:
                                PosterCard(item: item,
                                           action: { onSelect(item) },
                                           onPrefetch: { prefetchAround(index) })
                            case .wide:
                                WideCard(item: item,
                                         action: { onSelect(item) },
                                         onPrefetch: { prefetchAround(index) })
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

    private func prefetchAround(_ focusedIndex: Int) {
        guard let jellyfin = appState.jellyfin, items.indices.contains(focusedIndex) else { return }

        let start = max(items.startIndex, focusedIndex - 1)
        let end = min(items.endIndex, focusedIndex + 6)
        var urls: [URL?] = []

        for index in start..<end {
            let item = items[index]
            switch style {
            case .poster:
                urls.append(jellyfin.posterURL(for: item))
            case .wide:
                urls.append(jellyfin.wideImageURL(for: item))
            }
        }

        urls.append(jellyfin.backdropURL(for: items[focusedIndex], maxWidth: 1280))
        RemoteImagePrefetcher.shared.prefetch(urls)
    }
}

/// Horizontal row of tappable category tiles (genres, networks, studios).
struct CategoryShelf: View {
    let title: String
    let categories: [SeerCategory]
    let onSelect: (SeerCategory) -> Void

    var body: some View {
        if !categories.isEmpty {
            VStack(alignment: .leading, spacing: 20) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.9))
                    .padding(.horizontal, 64)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 22) {
                        ForEach(categories, id: \.self) { category in
                            CategoryTile(title: category.title) { onSelect(category) }
                        }
                    }
                    .padding(.horizontal, 64)
                    .padding(.vertical, 12)
                }
                .scrollClipDisabled()
                .focusSection()
            }
        }
    }
}

/// A colored, focusable tile naming a category. The gradient is derived from
/// the title so each category keeps a stable color.
struct CategoryTile: View {
    let title: String
    let action: () -> Void

    private static let palettes: [[UInt32]] = [
        [0x7C3AED, 0xDB2777], [0x2563EB, 0x06B6D4], [0xD97706, 0xDC2626],
        [0x059669, 0x10B981], [0xDB2777, 0xF59E0B], [0x4F46E5, 0x7C3AED],
        [0x0EA5E9, 0x2563EB], [0xE11D48, 0x7C3AED], [0x16A34A, 0x84CC16],
        [0x9333EA, 0x2563EB],
    ]

    private var gradient: LinearGradient {
        let hash = abs(title.hashValue) % Self.palettes.count
        let pair = Self.palettes[hash]
        return LinearGradient(colors: [Color(hex: pair[0]), Color(hex: pair[1])],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(gradient)
                Text(title)
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 18)
                    .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
            }
            .frame(width: 300, height: 150)
        }
        .buttonStyle(CategoryTileStyle())
    }
}

private struct CategoryTileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { TileBody(configuration: configuration) }

    private struct TileBody: View {
        @Environment(\.isFocused) private var isFocused
        let configuration: ButtonStyle.Configuration
        var body: some View {
            configuration.label
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(isFocused ? 0.9 : 0), lineWidth: 4)
                }
                .shadow(color: isFocused ? .black.opacity(0.5) : .clear, radius: 18, y: 10)
                .scaleEffect(isFocused ? 1.08 : 1)
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isFocused)
        }
    }
}

/// Shelf of Jellyseerr discovery results.
struct SeerShelf: View {
    let title: String
    let items: [SeerResult]
    let onSelect: (SeerResult) -> Void
    var onPrefetch: ((SeerResult) -> Void)?

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 20) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.9))
                    .padding(.horizontal, 64)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: Theme.shelfSpacing) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, media in
                            SeerPosterCard(media: media,
                                           action: { onSelect(media) },
                                           onPrefetch: {
                                               prefetchAround(index)
                                               onPrefetch?(media)
                                           })
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

    private func prefetchAround(_ focusedIndex: Int) {
        guard items.indices.contains(focusedIndex) else { return }

        let start = max(items.startIndex, focusedIndex - 1)
        let end = min(items.endIndex, focusedIndex + 6)
        var urls = (start..<end).map { items[$0].posterURL }
        urls.append(items[focusedIndex].backdropURL)

        RemoteImagePrefetcher.shared.prefetch(urls)
    }
}
