import Foundation
import SwiftUI

/// Session + configuration store. Keeps any number of server profiles,
/// owns the API clients for the active one.
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var profiles: [ServerProfile] = []
    @Published private(set) var activeProfileID: UUID?
    @Published private(set) var jellyfin: JellyfinClient?
    @Published private(set) var jellyseerr: JellyseerrClient?
    /// Bumped whenever the active connection changes (switch or edit) so
    /// content tabs know to reload.
    @Published private(set) var generation = 0

    let deviceId: String

    private static let profilesKey = "jellyjelly.profiles"
    private static let activeKey = "jellyjelly.activeProfile"
    private static let legacyConfigKey = "jellyjelly.serverConfig"
    private static let deviceIdKey = "jellyjelly.deviceId"

    init() {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: Self.deviceIdKey) {
            deviceId = existing
        } else {
            let fresh = UUID().uuidString
            defaults.set(fresh, forKey: Self.deviceIdKey)
            deviceId = fresh
        }

        if let data = defaults.data(forKey: Self.profilesKey),
           let stored = try? JSONDecoder().decode([ServerProfile].self, from: data) {
            profiles = stored
        } else if let migrated = Self.migrateLegacyConfig() {
            profiles = [migrated]
            persistProfiles()
        }

        let storedActive = defaults.string(forKey: Self.activeKey).flatMap(UUID.init)
        let initial = profiles.first(where: { $0.id == storedActive })?.id ?? profiles.first?.id
        if let initial { activate(initial) }
    }

    var activeProfile: ServerProfile? {
        profiles.first { $0.id == activeProfileID }
    }

    var isSignedIn: Bool { activeProfile != nil }

    // MARK: - Profile management

    func addProfile(_ profile: ServerProfile) {
        profiles.append(profile)
        persistProfiles()
        activate(profile.id)
    }

    func activate(_ id: UUID) {
        guard let profile = profiles.first(where: { $0.id == id }) else { return }
        activeProfileID = id
        UserDefaults.standard.set(id.uuidString, forKey: Self.activeKey)
        jellyfin = JellyfinClient(profile: profile, deviceId: deviceId)
        jellyseerr = JellyseerrClient(profile: profile)
        generation += 1
    }

    func updateProfile(_ profile: ServerProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index] = profile
        persistProfiles()
        if activeProfileID == profile.id {
            activate(profile.id)
        }
    }

    func removeProfile(_ id: UUID) {
        profiles.removeAll { $0.id == id }
        persistProfiles()
        if activeProfileID == id {
            if let next = profiles.first {
                activate(next.id)
            } else {
                activeProfileID = nil
                jellyfin = nil
                jellyseerr = nil
                UserDefaults.standard.removeObject(forKey: Self.activeKey)
            }
        }
    }

    private func persistProfiles() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        UserDefaults.standard.set(data, forKey: Self.profilesKey)
    }

    // MARK: - Migration from the single-server format

    private struct LegacyServerConfig: Codable {
        var jellyfinURL: URL
        var serverName: String
        var accessToken: String
        var userId: String
        var username: String
        var jellyseerrURL: URL?
        var jellyseerrAPIKey: String?
    }

    private static func migrateLegacyConfig() -> ServerProfile? {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: legacyConfigKey),
              let legacy = try? JSONDecoder().decode(LegacyServerConfig.self, from: data) else { return nil }
        defaults.removeObject(forKey: legacyConfigKey)
        return ServerProfile(
            id: UUID(),
            name: legacy.serverName,
            jellyfinURL: legacy.jellyfinURL,
            accessToken: legacy.accessToken,
            userId: legacy.userId,
            username: legacy.username,
            jellyseerrURL: legacy.jellyseerrURL,
            jellyseerrAPIKey: legacy.jellyseerrAPIKey)
    }
}

/// Normalizes what the user typed into a usable base URL.
/// Adds http:// when no scheme is given (self-hosted servers are often plain HTTP).
func normalizeServerURL(_ text: String) -> URL? {
    var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if !trimmed.lowercased().hasPrefix("http://") && !trimmed.lowercased().hasPrefix("https://") {
        trimmed = "http://" + trimmed
    }
    while trimmed.hasSuffix("/") { trimmed.removeLast() }
    guard let url = URL(string: trimmed), url.host() != nil else { return nil }
    return url
}
