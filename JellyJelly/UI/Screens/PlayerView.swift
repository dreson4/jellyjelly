import SwiftUI
import AVKit

struct PlaybackRequest: Identifiable, Equatable {
    let id = UUID()
    let item: BaseItem
    var fromBeginning = false
}

/// Full-screen playback: negotiates a stream with Jellyfin, plays it, and
/// reports start/progress/stop so the server tracks resume positions.
struct PlayerScreen: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let request: PlaybackRequest

    @State private var session: PlaybackSession?
    @State private var loadError: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let session {
                PlayerViewController(session: session, onFinished: { dismiss() })
                    .ignoresSafeArea()
            } else if let loadError {
                VStack(spacing: 28) {
                    Text("Playback failed")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(loadError)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(maxWidth: 800)
                        .multilineTextAlignment(.center)
                    Button("Close") { dismiss() }
                        .buttonStyle(PillButtonStyle(prominent: true))
                }
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .task { await start() }
        .onDisappear {
            session?.stop()
            session = nil
        }
    }

    private func start() async {
        guard let jellyfin = appState.jellyfin else { return }
        do {
            let resumeAt = request.fromBeginning ? 0 : request.item.resumePositionSeconds
            let context = try await jellyfin.playbackContext(for: request.item, startAtSeconds: resumeAt)
            session = PlaybackSession(client: jellyfin, context: context)
        } catch {
            loadError = error.localizedDescription
        }
    }
}

/// Owns the AVPlayer and the progress-reporting loop for one playback.
@MainActor
final class PlaybackSession {
    let player: AVPlayer
    let context: PlaybackContext

    private let client: JellyfinClient
    private var timeObserver: Any?
    private var stopped = false

    init(client: JellyfinClient, context: PlaybackContext) {
        self.client = client
        self.context = context

        let asset = AVURLAsset(url: context.streamURL)
        let item = AVPlayerItem(asset: asset)
        item.externalMetadata = Self.metadata(for: context.item)
        player = AVPlayer(playerItem: item)

        if context.seekOnStartSeconds > 1 {
            player.seek(to: CMTime(seconds: context.seekOnStartSeconds, preferredTimescale: 600),
                        toleranceBefore: .zero, toleranceAfter: .positiveInfinity)
        }
        player.play()

        Task { await client.reportPlaybackStart(context, positionSeconds: currentPositionSeconds) }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 10, preferredTimescale: 600),
            queue: .main) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in self.reportProgress() }
            }
    }

    /// Position on the *item's* timeline. HLS transcodes restart their clock at
    /// the seek point, so the negotiated offset is added back.
    var currentPositionSeconds: Double {
        let raw = player.currentTime().seconds
        guard raw.isFinite, raw >= 0 else { return context.startOffsetSeconds }
        return raw + context.startOffsetSeconds
    }

    private func reportProgress() {
        guard !stopped else { return }
        let paused = player.timeControlStatus != .playing
        let position = currentPositionSeconds
        Task { await client.reportPlaybackProgress(context, positionSeconds: position, isPaused: paused) }
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        let position = currentPositionSeconds
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        player.pause()
        player.replaceCurrentItem(with: nil)
        Task { await client.reportPlaybackStopped(context, positionSeconds: position) }
    }

    /// Title/artwork metadata for the tvOS player info panel.
    private static func metadata(for item: BaseItem) -> [AVMetadataItem] {
        var entries: [(AVMetadataIdentifier, String)] = []
        if item.isEpisode {
            entries.append((.commonIdentifierTitle, item.name ?? ""))
            let context = [item.seriesName, item.episodeLabel].compactMap { $0 }.joined(separator: " · ")
            entries.append((.iTunesMetadataTrackSubTitle, context))
        } else {
            entries.append((.commonIdentifierTitle, item.name ?? ""))
        }
        if let overview = item.overview {
            entries.append((.commonIdentifierDescription, overview))
        }
        return entries.map { identifier, value in
            let entry = AVMutableMetadataItem()
            entry.identifier = identifier
            entry.value = value as NSString
            entry.extendedLanguageTag = "und"
            return entry
        }
    }
}

/// AVPlayerViewController wrapper — native tvOS transport controls.
struct PlayerViewController: UIViewControllerRepresentable {
    let session: PlaybackSession
    let onFinished: () -> Void

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = session.player
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.playerDidFinish),
            name: .AVPlayerItemDidPlayToEndTime,
            object: session.player.currentItem)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinished: onFinished)
    }

    final class Coordinator: NSObject {
        let onFinished: () -> Void
        init(onFinished: @escaping () -> Void) { self.onFinished = onFinished }

        @objc func playerDidFinish() {
            onFinished()
        }
    }
}
