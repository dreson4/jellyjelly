import SwiftUI

/// Everything that can open as a full-screen detail page, across both the
/// Jellyfin and Jellyseerr domains. One type so a single app-level cover can
/// present any of them and chain between them.
/// A filterable Jellyseerr discovery category (a genre, TV network or studio).
struct SeerCategory: Hashable {
    enum Kind: Hashable {
        case movieGenre(Int)
        case tvGenre(Int)
        case network(Int)
        case studio(Int)
    }
    let title: String
    let kind: Kind
}

enum AppRoute: Hashable, Identifiable {
    case item(String)                 // Jellyfin item id    → ItemDetailView
    case person(BaseItemPerson)       // Jellyfin cast/crew  → PersonItemsView
    case seer(SeerResult)             // Jellyseerr title    → SeerDetailView
    case seerPerson(SeerCastMember)   // Jellyseerr cast     → SeerPersonView
    case requests                     // Jellyseerr requests → RequestsView
    case discoverCategory(SeerCategory) // filtered grid     → DiscoverCategoryView

    var id: String {
        switch self {
        case .item(let id): return "item:\(id)"
        case .person(let person): return "person:\(person.id)"
        case .seer(let media): return "seer:\(media.mediaType):\(media.id)"
        case .seerPerson(let member): return "seerPerson:\(member.id)"
        case .requests: return "requests"
        case .discoverCategory(let category): return "category:\(category.hashValue)"
        }
    }
}

/// Drives the app-level detail cover. Opening a title from any tab presents a
/// full-screen flow *above* the TabView, so the tab bar is hidden and the
/// Menu/Back button reliably returns to exactly where the user was.
@MainActor
final class Router: ObservableObject {
    @Published var route: AppRoute?

    func open(_ route: AppRoute) { self.route = route }
}

/// Pushes a further destination onto the detail flow's own navigation stack
/// (cast → person, "Known For" → title, …) without dismissing the cover.
/// Injected into the environment by `DetailFlow`.
struct DetailPush {
    let action: (AppRoute) -> Void
    func callAsFunction(_ route: AppRoute) { action(route) }
}

private struct DetailPushKey: EnvironmentKey {
    static let defaultValue = DetailPush { _ in }
}

extension EnvironmentValues {
    var detailPush: DetailPush {
        get { self[DetailPushKey.self] }
        set { self[DetailPushKey.self] = newValue }
    }
}
