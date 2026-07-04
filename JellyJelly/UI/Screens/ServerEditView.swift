import SwiftUI

/// Add or edit a server in one top-to-bottom form: Jellyfin connection,
/// optional Jellyseerr pairing — each with its own connect check — then Save.
/// Opening an existing server auto-verifies what's stored, so healthy
/// connections show their green checks right away.
struct ServerEditView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let profileID: UUID?

    private enum SectionState: Equatable {
        case idle
        case testing
        case verified(String)
        case failed(String)
    }

    private struct JellyfinSnapshot: Equatable {
        var address: String
        var username: String
        var password: String
    }

    private struct JellyseerrSnapshot: Equatable {
        var address: String
        var method: JellyseerrConnectMethod
        var email: String
        var password: String
        var key: String
    }

    // Jellyfin form
    @State private var jfAddress = ""
    @State private var jfUsername = ""
    @State private var jfPassword = ""
    @State private var jfState: SectionState = .idle
    @State private var jfSnapshot: JellyfinSnapshot?
    @State private var jfAuth: AuthenticationResult?
    @State private var jfServerName: String?

    // Jellyseerr form
    @State private var seerAddress = ""
    @State private var seerMethod: JellyseerrConnectMethod = .jellyfinAccount
    @State private var seerEmail = ""
    @State private var seerPassword = ""
    @State private var seerKey = ""
    @State private var seerState: SectionState = .idle
    @State private var seerSnapshot: JellyseerrSnapshot?
    @State private var seerCookie: String?

    @State private var didLoad = false

    private var existingProfile: ServerProfile? {
        guard let profileID else { return nil }
        return appState.profiles.first { $0.id == profileID }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 44) {
                Text(existingProfile?.name ?? "Add Server")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)

                jellyfinSection
                jellyseerrSection
                actions
            }
            .frame(maxWidth: 1000, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(64)
        }
        .task { await initialLoad() }
    }

    // MARK: - Jellyfin section

    private var jellyfinSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader("Jellyfin", subtitle: "Your media server.")

            TextField("Address (e.g. 192.168.1.20:8096)", text: $jfAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("Username", text: $jfUsername)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField(existingProfile != nil ? "Password (only needed to re-connect)" : "Password",
                        text: $jfPassword)

            statusRow(state: jfState, stillValid: jellyfinVerified)

            Button {
                Task { await connectJellyfin() }
            } label: {
                if jfState == .testing { ProgressView().tint(.white) }
                else { Label("Connect", systemImage: "bolt.fill") }
            }
            .buttonStyle(PillButtonStyle(prominent: !jellyfinVerified))
            .disabled(jfState == .testing || jfAddress.isEmpty || jfUsername.isEmpty)
        }
    }

    // MARK: - Jellyseerr section

    private var jellyseerrSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader("Jellyseerr",
                          subtitle: "Optional — adds a Discover tab for browsing and requesting. Leave the address empty to go without it.")

            TextField("Address (e.g. requests.example.com)", text: $seerAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            HStack(spacing: 14) {
                ForEach(JellyseerrConnectMethod.allCases, id: \.self) { method in
                    Button(method.rawValue) { seerMethod = method }
                        .buttonStyle(ChipButtonStyle(isSelected: seerMethod == method))
                }
            }
            .focusSection()

            switch seerMethod {
            case .jellyfinAccount:
                Text("Uses the Jellyfin username and password from the section above.")
                    .font(.callout)
                    .foregroundStyle(Theme.textTertiary)
            case .localAccount:
                TextField("Email", text: $seerEmail)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Jellyseerr password", text: $seerPassword)
            case .apiKey:
                SecureField("API key (Jellyseerr → Settings → General)", text: $seerKey)
            }

            statusRow(state: seerState, stillValid: jellyseerrVerified)

            Button {
                Task { await connectJellyseerr() }
            } label: {
                if seerState == .testing { ProgressView().tint(.white) }
                else { Label("Connect", systemImage: "sparkles") }
            }
            .buttonStyle(PillButtonStyle(prominent: !seerAddress.isEmpty && !jellyseerrVerified))
            .disabled(seerState == .testing || seerConnectDisabled)
        }
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 20) {
                Button {
                    save()
                } label: {
                    Label("Save", systemImage: "checkmark")
                }
                .buttonStyle(PillButtonStyle(prominent: true))
                .disabled(saveDisabled)

                if let existing = existingProfile, existing.id != appState.activeProfileID {
                    Button {
                        appState.activate(existing.id)
                    } label: {
                        Label("Use This Server", systemImage: "play.tv")
                    }
                    .buttonStyle(PillButtonStyle())
                }

                if let existing = existingProfile {
                    Button {
                        appState.removeProfile(existing.id)
                        dismiss()
                    } label: {
                        Label("Remove Server", systemImage: "trash")
                    }
                    .buttonStyle(PillButtonStyle())
                }
            }

            if saveDisabled {
                Text("Connect to Jellyfin (and Jellyseerr, if set) to enable Save.")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    // MARK: - Verification state

    private var currentJellyfinSnapshot: JellyfinSnapshot {
        JellyfinSnapshot(address: jfAddress, username: jfUsername, password: jfPassword)
    }

    private var currentSeerSnapshot: JellyseerrSnapshot {
        JellyseerrSnapshot(address: seerAddress, method: seerMethod,
                           email: seerEmail, password: seerPassword, key: seerKey)
    }

    /// Verified and untouched since — editing any field drops the check.
    private var jellyfinVerified: Bool {
        guard case .verified = jfState else { return false }
        return jfSnapshot == currentJellyfinSnapshot
    }

    private var jellyseerrVerified: Bool {
        guard case .verified = seerState else { return false }
        return seerSnapshot == currentSeerSnapshot
    }

    private var seerConnectDisabled: Bool {
        if seerAddress.isEmpty { return true }
        switch seerMethod {
        case .jellyfinAccount: return jfUsername.isEmpty
        case .localAccount: return seerEmail.isEmpty || seerPassword.isEmpty
        case .apiKey: return seerKey.isEmpty
        }
    }

    private var saveDisabled: Bool {
        !jellyfinVerified || (!seerAddress.isEmpty && !jellyseerrVerified)
    }

    // MARK: - Connecting

    private func initialLoad() async {
        guard !didLoad else { return }
        didLoad = true
        guard let profile = existingProfile else { return }

        jfAddress = profile.jellyfinURL.absoluteString
        jfUsername = profile.username
        seerAddress = profile.jellyseerrURL?.absoluteString ?? ""
        seerKey = profile.jellyseerrAPIKey ?? ""
        seerCookie = profile.jellyseerrCookie
        seerMethod = profile.jellyseerrAPIKey?.isEmpty == false ? .apiKey : .jellyfinAccount

        // Auto-verify what's stored so working connections show their checks.
        await verifyStoredJellyfin(profile)
        if profile.hasJellyseerr {
            await verifyStoredJellyseerr(profile)
        }
    }

    private func verifyStoredJellyfin(_ profile: ServerProfile) async {
        jfState = .testing
        do {
            let info = try await JellyfinClient.probe(url: profile.jellyfinURL)
            let client = JellyfinClient(profile: profile, deviceId: appState.deviceId)
            let user = try await client.currentUser()
            jfServerName = info.serverName
            jfState = .verified("Connected to \(info.serverName ?? "Jellyfin") as \(user.name)")
            jfSnapshot = currentJellyfinSnapshot
        } catch {
            jfState = .failed("Stored sign-in didn't work — enter the password and connect again.")
        }
    }

    private func verifyStoredJellyseerr(_ profile: ServerProfile) async {
        guard let client = JellyseerrClient(profile: profile) else { return }
        seerState = .testing
        do {
            let user = try await client.me()
            seerState = .verified("Connected as \(user.displayName ?? profile.username)")
            seerSnapshot = currentSeerSnapshot
        } catch {
            seerState = .failed("Stored Jellyseerr session didn't work — sign in again below.")
        }
    }

    private func connectJellyfin() async {
        guard let url = normalizeServerURL(jfAddress) else {
            jfState = .failed("That address doesn't look valid.")
            return
        }
        jfState = .testing
        do {
            let info = try await JellyfinClient.probe(url: url)
            if jfPassword.isEmpty, let existing = existingProfile,
               url == existing.jellyfinURL, jfUsername == existing.username {
                // Unchanged account: re-validate the stored token instead.
                let client = JellyfinClient(profile: existing, deviceId: appState.deviceId)
                let user = try await client.currentUser()
                jfAuth = nil
                jfState = .verified("Connected to \(info.serverName ?? "Jellyfin") as \(user.name)")
            } else {
                let auth = try await JellyfinClient.authenticate(
                    url: url, username: jfUsername, password: jfPassword,
                    deviceId: appState.deviceId)
                jfAuth = auth
                jfState = .verified("Connected to \(info.serverName ?? "Jellyfin") as \(auth.user.name)")
            }
            jfServerName = info.serverName
            jfSnapshot = currentJellyfinSnapshot
        } catch {
            jfState = .failed(error.localizedDescription)
        }
    }

    private func connectJellyseerr() async {
        guard let url = normalizeServerURL(seerAddress) else {
            seerState = .failed("That address doesn't look valid.")
            return
        }
        seerState = .testing
        do {
            switch seerMethod {
            case .jellyfinAccount:
                guard !jfPassword.isEmpty else {
                    seerState = .failed("Enter your Jellyfin password in the section above, then connect.")
                    return
                }
                seerCookie = try await JellyseerrClient.loginWithJellyfin(
                    baseURL: url, username: jfUsername, password: jfPassword)
                seerState = .verified("Connected with your Jellyfin account")
            case .localAccount:
                seerCookie = try await JellyseerrClient.loginLocal(
                    baseURL: url, email: seerEmail, password: seerPassword)
                seerState = .verified("Connected with your Jellyseerr account")
            case .apiKey:
                let client = JellyseerrClient(baseURL: url, auth: .apiKey(seerKey))
                _ = try await client.me()
                seerCookie = nil
                seerState = .verified("Connected with API key")
            }
            seerSnapshot = currentSeerSnapshot
        } catch {
            seerState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Saving

    private func save() {
        guard jellyfinVerified, let url = normalizeServerURL(jfAddress) else { return }

        var profile = existingProfile ?? ServerProfile(
            id: UUID(), name: "", jellyfinURL: url,
            accessToken: "", userId: "", username: "")
        profile.jellyfinURL = url
        if let name = jfServerName, !name.isEmpty { profile.name = name }
        if profile.name.isEmpty { profile.name = "Jellyfin" }
        if let auth = jfAuth {
            profile.accessToken = auth.accessToken
            profile.userId = auth.user.id
            profile.username = auth.user.name
        }

        if seerAddress.isEmpty {
            profile.jellyseerrURL = nil
            profile.jellyseerrAPIKey = nil
            profile.jellyseerrCookie = nil
        } else if jellyseerrVerified, let seerURL = normalizeServerURL(seerAddress) {
            profile.jellyseerrURL = seerURL
            profile.jellyseerrAPIKey = seerMethod == .apiKey ? seerKey : nil
            profile.jellyseerrCookie = seerMethod == .apiKey ? nil : seerCookie
        }

        if existingProfile == nil {
            appState.addProfile(profile)
        } else {
            appState.updateProfile(profile)
        }
        dismiss()
    }

    // MARK: - Small pieces

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.textPrimary.opacity(0.9))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    @ViewBuilder
    private func statusRow(state: SectionState, stillValid: Bool) -> some View {
        switch state {
        case .idle:
            EmptyView()
        case .testing:
            HStack(spacing: 12) {
                ProgressView().scaleEffect(0.7)
                Text("Connecting…")
                    .font(.callout)
                    .foregroundStyle(Theme.textTertiary)
            }
        case .verified(let message):
            if stillValid {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white, Color(hex: 0x2AA860))
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(Color(hex: 0x5BE49B))
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(Color(hex: 0xE0A030))
                    Text("Details changed — connect again to verify.")
                        .font(.callout)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        case .failed(let message):
            HStack(spacing: 10) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white, Color(hex: 0xD64545))
                Text(message)
                    .font(.callout)
                    .foregroundStyle(Color(hex: 0xFF6B6B))
            }
        }
    }
}
