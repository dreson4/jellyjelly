import SwiftUI

/// Settings root: the server list. Selecting a server opens the full editor;
/// more sections can slot in below later.
struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    enum Route: Hashable {
        case addServer
        case editServer(UUID)
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 36) {
                    Text("Settings")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Servers")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary.opacity(0.9))
                        Text("Select a server to edit its connections or make it active.")
                            .font(.callout)
                            .foregroundStyle(Theme.textTertiary)

                        ForEach(appState.profiles) { profile in
                            NavigationLink(value: Route.editServer(profile.id)) {
                                serverRow(profile)
                            }
                            .buttonStyle(ServerRowStyle())
                        }

                        NavigationLink(value: Route.addServer) {
                            Label("Add Server", systemImage: "plus")
                        }
                        .buttonStyle(PillButtonStyle(prominent: true))
                        .padding(.top, 8)
                    }
                }
                .frame(maxWidth: 1100, alignment: .leading)
                .padding(64)
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .addServer:
                    ServerEditView(profileID: nil)
                case .editServer(let id):
                    ServerEditView(profileID: id)
                }
            }
        }
    }

    private func serverRow(_ profile: ServerProfile) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "server.rack")
                .font(.title3)
                .foregroundStyle(profile.id == appState.activeProfileID
                                 ? AnyShapeStyle(Theme.accentGradient)
                                 : AnyShapeStyle(Theme.textTertiary))
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name)
                    .font(.headline)
                Text("\(profile.username) · \(profile.jellyfinURL.absoluteString)")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            Spacer()
            if profile.hasJellyseerr {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            if profile.id == appState.activeProfileID {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.white, Color(hex: 0x2AA860))
            }
        }
    }
}

/// Wide list-row button for the server list.
struct ServerRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RowBody(configuration: configuration)
    }

    private struct RowBody: View {
        @Environment(\.isFocused) private var isFocused
        let configuration: ButtonStyle.Configuration

        var body: some View {
            configuration.label
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(isFocused ? 0.16 : 0.05))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(isFocused ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.white.opacity(0.1)),
                                      lineWidth: isFocused ? 2 : 1)
                }
                .scaleEffect(isFocused ? 1.02 : 1)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isFocused)
        }
    }
}
