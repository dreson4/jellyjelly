import SwiftUI
import UIKit

/// Tracks the artwork of whatever the user is focused on and exposes it as a
/// loaded image. Debounced so racing across a shelf doesn't thrash, and the
/// previous image is kept until the next one has actually loaded — the
/// background never dips to empty.
@MainActor
final class Ambience: ObservableObject {
    @Published private(set) var image: UIImage?

    private var currentURL: URL?
    private var pending: Task<Void, Never>?

    func set(_ url: URL?) {
        guard let url, url != currentURL else { return }
        currentURL = url
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            let loaded = await Task.detached(priority: .utility) { () -> UIImage? in
                guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
                return UIImage(data: data)
            }.value
            guard let loaded, !Task.isCancelled, self?.currentURL == url else { return }
            withAnimation(.easeInOut(duration: 1.4)) {
                self?.image = loaded
            }
        }
    }

    func clear() {
        pending?.cancel()
        currentURL = nil
        withAnimation(.easeInOut(duration: 0.8)) { image = nil }
    }
}

/// Full-screen ambient layer: the focused title's artwork, heavily blurred and
/// dimmed, sitting between the base gradient and the content. Subtle by design.
struct AmbientBackground: View {
    @EnvironmentObject private var ambience: Ambience

    var body: some View {
        ZStack {
            if let image = ambience.image {
                GeometryReader { geo in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .blur(radius: 44)
                        .scaleEffect(1.08)
                        .saturation(1.25)
                }
                .opacity(0.24)
                .transition(.opacity)
                .id(image)
            }
        }
        .overlay {
            // Keep the lower half (where shelves and text live) anchored to the theme.
            LinearGradient(
                colors: [Theme.background.opacity(0.1), Theme.background.opacity(0.55)],
                startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Reports this view's focus to the ambience engine: while focused, the given
/// artwork drives the app background.
private struct AmbienceSource: ViewModifier {
    @EnvironmentObject private var ambience: Ambience
    @FocusState private var isFocused: Bool
    let url: URL?

    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .onChange(of: isFocused) { _, focused in
                if focused { ambience.set(url) }
            }
    }
}

extension View {
    func ambientSource(_ url: URL?) -> some View {
        modifier(AmbienceSource(url: url))
    }
}
