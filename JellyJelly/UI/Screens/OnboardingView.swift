import SwiftUI

/// First-run flow: server address → sign in → optional Jellyseerr.
/// (Additional servers are added from Settings via the server editor.)
struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState

    private enum Step {
        case server
        case credentials
        case jellyseerr
    }

    @State private var step: Step = .server

    @State private var serverText = ""
    @State private var serverURL: URL?
    @State private var serverInfo: PublicSystemInfo?

    @State private var username = ""
    @State private var password = ""
    @State private var authResult: AuthenticationResult?

    @State private var seerURLText = ""
    @State private var seerMethod: JellyseerrConnectMethod = .jellyfinAccount
    @State private var seerEmailText = ""
    @State private var seerPasswordText = ""
    @State private var seerKeyText = ""

    @State private var isBusy = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 48) {
            VStack(spacing: 12) {
                Text("JellyJelly")
                    .font(.system(size: 76, weight: .heavy))
                    .foregroundStyle(Theme.accentGradient)
                Text("Your Jellyfin cinema, on the big screen")
                    .font(.title3)
                    .foregroundStyle(Theme.textSecondary)
            }

            VStack(spacing: 28) {
                switch step {
                case .server: serverStep
                case .credentials: credentialsStep
                case .jellyseerr: jellyseerrStep
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(Color(hex: 0xFF6B6B))
                        .frame(maxWidth: 860)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: 900)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(64)
    }

    // MARK: - Step 1: server

    private var serverStep: some View {
        VStack(spacing: 24) {
            stepHeader("Connect to your Jellyfin server",
                       subtitle: "The address you use in the browser, e.g. 192.168.1.20:8096 or jellyfin.example.com")

            TextField("Server address", text: $serverText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button {
                Task { await probeServer() }
            } label: {
                if isBusy { ProgressView().tint(.white) }
                else { Label("Connect", systemImage: "bolt.fill") }
            }
            .buttonStyle(PillButtonStyle(prominent: true))
            .disabled(isBusy || serverText.isEmpty)
        }
    }

    // MARK: - Step 2: credentials

    private var credentialsStep: some View {
        VStack(spacing: 24) {
            stepHeader("Sign in to \(serverInfo?.serverName ?? "Jellyfin")",
                       subtitle: serverURL?.absoluteString ?? "")

            TextField("Username", text: $username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Password", text: $password)

            HStack(spacing: 20) {
                Button("Back") {
                    step = .server
                    errorMessage = nil
                }
                .buttonStyle(PillButtonStyle())

                Button {
                    Task { await signIn() }
                } label: {
                    if isBusy { ProgressView().tint(.white) }
                    else { Label("Sign In", systemImage: "person.fill") }
                }
                .buttonStyle(PillButtonStyle(prominent: true))
                .disabled(isBusy || username.isEmpty)
            }
        }
    }

    // MARK: - Step 3: Jellyseerr (optional)

    private var jellyseerrStep: some View {
        VStack(spacing: 24) {
            stepHeader("Add Jellyseerr? (optional)",
                       subtitle: "Enables a Discover tab to browse trending titles and request new content. You can also set this up later in Settings.")

            TextField("Jellyseerr address", text: $seerURLText)
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
                Text("Signs in as “\(username)” — the account from the previous step. Nothing else to type.")
                    .font(.callout)
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            case .localAccount:
                TextField("Email", text: $seerEmailText)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Jellyseerr password", text: $seerPasswordText)
            case .apiKey:
                SecureField("API key (Jellyseerr → Settings → General)", text: $seerKeyText)
            }

            HStack(spacing: 20) {
                Button("Skip") {
                    finish(seerURL: nil, seerKey: nil, seerCookie: nil)
                }
                .buttonStyle(PillButtonStyle())

                Button {
                    Task { await connectJellyseerr() }
                } label: {
                    if isBusy { ProgressView().tint(.white) }
                    else { Label("Connect & Finish", systemImage: "sparkles") }
                }
                .buttonStyle(PillButtonStyle(prominent: true))
                .disabled(isBusy || seerConnectDisabled)
            }
        }
    }

    private var seerConnectDisabled: Bool {
        if seerURLText.isEmpty { return true }
        switch seerMethod {
        case .jellyfinAccount: return false
        case .localAccount: return seerEmailText.isEmpty || seerPasswordText.isEmpty
        case .apiKey: return seerKeyText.isEmpty
        }
    }

    private func stepHeader(_ title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Actions

    private func probeServer() async {
        guard let url = normalizeServerURL(serverText) else {
            errorMessage = "That address doesn't look valid."
            return
        }
        isBusy = true
        errorMessage = nil
        do {
            let info = try await JellyfinClient.probe(url: url)
            serverURL = url
            serverInfo = info
            step = .credentials
        } catch {
            errorMessage = error.localizedDescription
        }
        isBusy = false
    }

    private func signIn() async {
        guard let serverURL else { return }
        isBusy = true
        errorMessage = nil
        do {
            authResult = try await JellyfinClient.authenticate(
                url: serverURL, username: username, password: password,
                deviceId: appState.deviceId)
            step = .jellyseerr
        } catch {
            errorMessage = error.localizedDescription
        }
        isBusy = false
    }

    private func connectJellyseerr() async {
        guard let url = normalizeServerURL(seerURLText) else {
            errorMessage = "That Jellyseerr address doesn't look valid."
            return
        }
        isBusy = true
        errorMessage = nil
        do {
            switch seerMethod {
            case .jellyfinAccount:
                // Reuse the Jellyfin credentials from the sign-in step.
                let cookie = try await JellyseerrClient.loginWithJellyfin(
                    baseURL: url, username: username, password: password)
                finish(seerURL: url, seerKey: nil, seerCookie: cookie)
            case .localAccount:
                let cookie = try await JellyseerrClient.loginLocal(
                    baseURL: url, email: seerEmailText, password: seerPasswordText)
                finish(seerURL: url, seerKey: nil, seerCookie: cookie)
            case .apiKey:
                let client = JellyseerrClient(baseURL: url, auth: .apiKey(seerKeyText))
                _ = try await client.me()
                finish(seerURL: url, seerKey: seerKeyText, seerCookie: nil)
            }
        } catch {
            errorMessage = "Couldn't connect to Jellyseerr: \(error.localizedDescription)"
        }
        isBusy = false
    }

    private func finish(seerURL: URL?, seerKey: String?, seerCookie: String?) {
        guard let serverURL, let authResult else { return }
        appState.addProfile(ServerProfile(
            id: UUID(),
            name: serverInfo?.serverName ?? "Jellyfin",
            jellyfinURL: serverURL,
            accessToken: authResult.accessToken,
            userId: authResult.user.id,
            username: authResult.user.name,
            jellyseerrURL: seerURL,
            jellyseerrAPIKey: seerKey,
            jellyseerrCookie: seerCookie))
    }
}
