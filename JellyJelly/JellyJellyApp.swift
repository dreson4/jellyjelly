import SwiftUI

@main
struct JellyJellyApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var ambience = Ambience()

    init() {
        // Artwork-heavy UI: give URLCache generous limits.
        URLCache.shared = URLCache(memoryCapacity: 128 * 1024 * 1024,
                                   diskCapacity: 1024 * 1024 * 1024)
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                Theme.backgroundGradient
                AmbientBackground()
                if appState.isSignedIn {
                    RootView()
                } else {
                    OnboardingView()
                }
            }
            .environmentObject(appState)
            .environmentObject(ambience)
            .preferredColorScheme(.dark)
        }
    }
}
