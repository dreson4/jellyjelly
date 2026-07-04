import SwiftUI

/// Jellyfin person page: headshot and name, then a grid of everything in the
/// library that this actor/director appears in. Pushed from a detail page's
/// cast row.
struct PersonItemsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var ambience: Ambience

    let person: BaseItemPerson

    @State private var items: [BaseItem] = []
    @State private var loading = true

    private let columns = [GridItem(.adaptive(minimum: Theme.posterWidth), spacing: Theme.shelfSpacing)]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                header

                if loading {
                    HStack {
                        Spacer()
                        ProgressView().tint(Theme.accentB).scaleEffect(1.4)
                        Spacer()
                    }
                    .padding(.vertical, 80)
                } else if items.isEmpty {
                    Text("Nothing in your library features \(person.name ?? "this person") yet.")
                        .font(.callout)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 64)
                        .padding(.vertical, 60)
                } else {
                    grid
                }
            }
            .padding(.bottom, 80)
        }
        .scrollClipDisabled()
        .task { await load() }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 40) {
            PersonHeadshot(url: appState.jellyfin?.personImageURL(person, maxWidth: 400), diameter: 220)
                .overlay {
                    Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.45), radius: 20, y: 10)

            VStack(alignment: .leading, spacing: 10) {
                Text(person.name ?? "Unknown")
                    .font(.system(size: 52, weight: .heavy))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                if let role = person.role, !role.isEmpty {
                    Text(role)
                        .font(.title3)
                        .foregroundStyle(Theme.textSecondary)
                } else if let type = person.type, !type.isEmpty {
                    Text(type)
                        .font(.title3)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(.horizontal, 64)
        .padding(.top, 80)
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 48) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 12) {
                    NavigationLink(value: item) {
                        PosterCardLabel(item: item)
                    }
                    .buttonStyle(.card)
                    .ambientSource(appState.jellyfin?.ambientImageURL(for: item))
                    Text(item.name ?? "")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .frame(width: Theme.posterWidth, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 64)
        .padding(.vertical, 12)
        .focusSection()
    }

    private func load() async {
        guard let jellyfin = appState.jellyfin else { loading = false; return }
        ambience.set(jellyfin.personImageURL(person, maxWidth: 480))
        items = (try? await jellyfin.items(personId: person.id)) ?? []
        loading = false
    }
}
