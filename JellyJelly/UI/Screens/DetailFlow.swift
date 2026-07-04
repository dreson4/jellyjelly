import SwiftUI

/// The full-screen detail flow presented above the TabView. It owns its own
/// navigation stack so cast → person → title chains push and pop cleanly, and
/// its own ambient background so the focus-driven wash follows you in. Because
/// it sits above the tabs, the tab bar is hidden and Menu/Back is reliable.
struct DetailFlow: View {
    let root: AppRoute
    @State private var path: [AppRoute] = []

    var body: some View {
        ZStack {
            Theme.backgroundGradient
            AmbientBackground()

            NavigationStack(path: $path) {
                view(for: root)
                    .navigationDestination(for: AppRoute.self) { view(for: $0) }
            }
            .environment(\.detailPush, DetailPush { path.append($0) })
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func view(for route: AppRoute) -> some View {
        switch route {
        case .item(let id): ItemDetailView(itemId: id)
        case .person(let person): PersonItemsView(person: person)
        case .seer(let media): SeerDetailView(media: media)
        case .seerPerson(let member): SeerPersonView(member: member)
        case .requests: RequestsView()
        case .discoverCategory(let category): DiscoverCategoryView(category: category)
        }
    }
}
