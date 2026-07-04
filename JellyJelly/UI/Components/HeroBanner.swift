import SwiftUI

/// Full-width rotating hero: backdrop, gradient scrim, title, metadata and actions.
struct HeroBanner: View {
    @EnvironmentObject private var appState: AppState
    let items: [BaseItem]
    let onPlay: (BaseItem) -> Void
    let onDetails: (BaseItem) -> Void

    @State private var index = 0
    @FocusState private var heroFocused: Bool
    private let rotation = Timer.publish(every: 8, on: .main, in: .common).autoconnect()

    private var current: BaseItem? {
        items.isEmpty ? nil : items[index % items.count]
    }

    var body: some View {
        if let item = current {
            VStack(alignment: .leading, spacing: 22) {
                Text(item.name ?? "")
                    .font(.system(size: 64, weight: .heavy))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.6), radius: 12, y: 4)

                Text(item.metadataLine)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)

                if let overview = item.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.body)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(3)
                        .frame(maxWidth: 820, alignment: .leading)
                }

                HStack(spacing: 24) {
                    Button {
                        onPlay(item)
                    } label: {
                        Label(item.resumePositionSeconds > 0 ? "Resume" : "Play",
                              systemImage: "play.fill")
                    }
                    .buttonStyle(PillButtonStyle(prominent: true))
                    .focused($heroFocused)

                    Button {
                        onDetails(item)
                    } label: {
                        Label("More Info", systemImage: "info.circle")
                    }
                    .buttonStyle(PillButtonStyle())
                    .focused($heroFocused)

                    if items.count > 1 {
                        HStack(spacing: 8) {
                            ForEach(0..<items.count, id: \.self) { dot in
                                Circle()
                                    .fill(dot == index % items.count
                                          ? AnyShapeStyle(Theme.accentGradient)
                                          : AnyShapeStyle(Color.white.opacity(0.25)))
                                    .frame(width: 8, height: 8)
                            }
                        }
                        .padding(.leading, 12)
                    }
                }
            }
            // Text and buttons stay in the container, aligned with the shelves below.
            .padding(.horizontal, 64)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity, minHeight: 680, maxHeight: 680, alignment: .bottomLeading)
            // The backdrop is a full-bleed background so only the image reaches
            // the screen edges; the content above keeps the shelf margins.
            .background(alignment: .bottom) {
                ZStack {
                    RemoteImage(url: appState.jellyfin?.backdropURL(for: item, maxWidth: 1920))
                        .frame(maxWidth: .infinity)
                        .frame(height: 680)
                        .clipped()
                        .id(item.id)

                    // Scrims: bottom fade into the page, left fade for text legibility.
                    LinearGradient(
                        colors: [Theme.background, Theme.background.opacity(0.35), .clear],
                        startPoint: .bottom, endPoint: .top)
                    LinearGradient(
                        colors: [Theme.background.opacity(0.9), .clear],
                        startPoint: .leading, endPoint: UnitPoint(x: 0.65, y: 0.5))
                }
                .frame(height: 680)
                .ignoresSafeArea(edges: [.top, .horizontal])
            }
            .focusSection()
            .onReceive(rotation) { _ in
                // Don't rotate under the user's cursor — a press right at the
                // switch would act on the wrong title.
                guard !heroFocused else { return }
                withAnimation(.easeInOut(duration: 0.6)) {
                    index = (index + 1) % max(items.count, 1)
                }
            }
        }
    }
}
