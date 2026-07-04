import SwiftUI

/// Person detail page for a Jellyseerr cast member: photo, biography, and a
/// "Known For" shelf. Some Jellyseerr servers can't resolve the TMDB person
/// endpoints (they 500), so both the bio and the filmography fall back to the
/// data carried in search results.
struct SeerPersonView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var ambience: Ambience
    @Environment(\.detailPush) private var push

    let member: SeerCastMember

    @State private var person: SeerPerson?
    @State private var credits: [SeerResult] = []
    @State private var loading = true

    private var name: String { person?.name ?? member.name ?? "Unknown" }
    private var photoURL: URL? { person?.imageURL ?? member.imageURL }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                header
                if loading {
                    HStack {
                        Spacer()
                        ProgressView().tint(.white).scaleEffect(1.4)
                        Spacer()
                    }
                    .padding(.vertical, 80)
                } else {
                    SeerShelf(title: "Known For", items: credits) { push(.seer($0)) }
                }
            }
            .padding(.bottom, 80)
        }
        .ignoresSafeArea(edges: .top)
        .detailBackButton()
        .task { await load() }
    }

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Theme.background.opacity(0.2), Theme.background],
                startPoint: .top, endPoint: .bottom)
                .frame(height: 620)

            HStack(alignment: .bottom, spacing: 48) {
                PersonHeadshot(url: photoURL, diameter: 300)
                    .overlay {
                        Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.5), radius: 24, y: 12)

                VStack(alignment: .leading, spacing: 16) {
                    Text(name)
                        .font(.system(size: 56, weight: .heavy))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)

                    if let character = member.character, !character.isEmpty {
                        Text("as \(character)")
                            .font(.title3.italic())
                            .foregroundStyle(Theme.textSecondary)
                    }

                    if let lifeLine = person?.lifeLine {
                        Text(lifeLine)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(Theme.textTertiary)
                    }

                    if let bio = person?.biography, !bio.isEmpty {
                        Text(bio)
                            .font(.body)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(8)
                            .frame(maxWidth: 1050, alignment: .leading)
                    }
                }
            }
            .padding(.horizontal, 64)
            .padding(.bottom, 20)
        }
        .focusSection()
    }

    private func load() async {
        ambience.set(member.imageURL)
        guard let seer = appState.jellyseerr else { loading = false; return }

        person = try? await seer.person(id: member.id)

        if let resolved = try? await seer.personCredits(id: member.id), !resolved.isEmpty {
            credits = dedupe(resolved)
        } else {
            let searchName = person?.name ?? member.name ?? ""
            let fallback = (try? await seer.personFromSearch(id: member.id, name: searchName)) ?? []
            credits = dedupe(fallback)
        }
        loading = false
    }

    /// Collapses duplicate titles (a person can be credited twice) and caps the
    /// shelf length.
    private func dedupe(_ items: [SeerResult]) -> [SeerResult] {
        var seen = Set<String>()
        var out: [SeerResult] = []
        for item in items {
            let key = "\(item.mediaType)-\(item.id)"
            if seen.insert(key).inserted { out.append(item) }
            if out.count >= 30 { break }
        }
        return out
    }
}
