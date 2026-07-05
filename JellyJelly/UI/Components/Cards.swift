import SwiftUI

/// Vertical 2:3 poster card used in shelves and grids.
struct PosterCard: View {
    @EnvironmentObject private var appState: AppState
    let item: BaseItem
    let action: () -> Void
    var showTitle = true
    var onPrefetch: (() -> Void)?

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: action) {
                ZStack(alignment: .bottom) {
                    RemoteImage(url: appState.jellyfin?.posterURL(for: item))
                        .frame(width: Theme.posterWidth, height: Theme.posterHeight)
                    if let fraction = item.playedFraction {
                        ProgressStripe(fraction: fraction)
                    }
                    if item.userData?.played == true {
                        WatchedCheck()
                    }
                }
                .frame(width: Theme.posterWidth, height: Theme.posterHeight)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.card)
            .focused($isFocused)
            .onChange(of: isFocused) { _, focused in
                if focused { onPrefetch?() }
            }

            if showTitle {
                Text(item.name ?? "")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .frame(width: Theme.posterWidth, alignment: .leading)
            }
        }
    }
}

/// Wide 16:9 card for Continue Watching / Next Up / episodes.
struct WideCard: View {
    @EnvironmentObject private var appState: AppState
    let item: BaseItem
    let action: () -> Void
    var onPrefetch: (() -> Void)?

    @FocusState private var isFocused: Bool

    private var title: String {
        item.isEpisode ? (item.seriesName ?? item.name ?? "") : (item.name ?? "")
    }

    private var subtitle: String {
        if item.isEpisode {
            let label = [item.episodeLabel, item.name].compactMap { $0 }.joined(separator: " · ")
            return label
        }
        return remainingLabel(totalTicks: item.runTimeTicks,
                              positionTicks: item.userData?.playbackPositionTicks) ?? item.metadataLine
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: action) {
                ZStack(alignment: .bottom) {
                    RemoteImage(url: appState.jellyfin?.wideImageURL(for: item))
                        .frame(width: Theme.wideCardWidth, height: Theme.wideCardHeight)
                    if let fraction = item.playedFraction {
                        ProgressStripe(fraction: fraction)
                    }
                }
                .frame(width: Theme.wideCardWidth, height: Theme.wideCardHeight)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.card)
            .focused($isFocused)
            .onChange(of: isFocused) { _, focused in
                if focused { onPrefetch?() }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.85))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            .frame(width: Theme.wideCardWidth, alignment: .leading)
        }
    }
}

/// Poster card for Jellyseerr discovery results, with availability badge.
struct SeerPosterCard: View {
    let media: SeerResult
    let action: () -> Void
    var onPrefetch: (() -> Void)?

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: action) {
                ZStack(alignment: .topLeading) {
                    RemoteImage(url: media.posterURL)
                        .frame(width: Theme.posterWidth, height: Theme.posterHeight)
                    if media.status != .unknown {
                        StatusBadge(status: media.status)
                            .padding(10)
                    }
                }
                .frame(width: Theme.posterWidth, height: Theme.posterHeight)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.card)
            .focused($isFocused)
            .onChange(of: isFocused) { _, focused in
                if focused { onPrefetch?() }
            }

            Text(media.displayTitle)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .frame(width: Theme.posterWidth, alignment: .leading)
        }
    }
}

struct StatusBadge: View {
    let status: SeerMediaStatus

    var body: some View {
        Badge(text: status.label, tint: tint.opacity(0.9), textColor: .white)
    }

    private var tint: Color {
        switch status {
        case .available, .partiallyAvailable: return Color(hex: 0x2AA860)
        case .processing: return Color(hex: 0x2D7FF9)
        case .pending: return Color(hex: 0xC77D1A)
        case .unknown: return .gray
        }
    }
}

/// Circular cast/crew headshot, falling back to a silhouette when there's no
/// photo. The plain visual — wrap it in a Button/NavigationLink with
/// `CircleButtonStyle` to make it focusable.
struct PersonHeadshot: View {
    let url: URL?
    var diameter: CGFloat = 150

    var body: some View {
        RemoteImage(url: url)
            .frame(width: diameter, height: diameter)
            .overlay {
                if url == nil {
                    Image(systemName: "person.fill")
                        .font(.system(size: diameter * 0.42))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .clipShape(Circle())
    }
}

/// A focusable circular cast member with name + character caption, shared by the
/// Jellyseerr and Jellyfin detail pages.
struct CastCard: View {
    let imageURL: URL?
    let name: String
    let subtitle: String?
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Button(action: action) {
                PersonHeadshot(url: imageURL)
            }
            .buttonStyle(CircleButtonStyle())

            VStack(spacing: 2) {
                Text(name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.9))
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
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

/// Thin gradient progress bar pinned to a card's bottom edge.
struct ProgressStripe: View {
    let fraction: Double

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.black.opacity(0.55))
                GeometryReader { geo in
                    Rectangle()
                        .fill(Theme.accentGradient)
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 6)
        }
    }
}

/// Checkmark shown on fully watched items.
struct WatchedCheck: View {
    var body: some View {
        VStack {
            HStack {
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white, Color(hex: 0x2AA860))
                    .padding(10)
            }
            Spacer()
        }
    }
}
