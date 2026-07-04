import SwiftUI

enum ShelfStyle {
    case poster
    case wide
}

/// Netflix-style horizontal shelf: section title + scrolling row of cards.
struct Shelf: View {
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
                        ForEach(items) { item in
                            switch style {
                            case .poster:
                                PosterCard(item: item, action: { onSelect(item) })
                            case .wide:
                                WideCard(item: item, action: { onSelect(item) })
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
}

/// Shelf of Jellyseerr discovery results.
struct SeerShelf: View {
    let title: String
    let items: [SeerResult]
    let onSelect: (SeerResult) -> Void

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 20) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.9))
                    .padding(.horizontal, 64)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: Theme.shelfSpacing) {
                        ForEach(items) { media in
                            SeerPosterCard(media: media, action: { onSelect(media) })
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
