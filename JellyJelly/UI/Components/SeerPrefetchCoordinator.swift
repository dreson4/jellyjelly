import Foundation

@MainActor
final class SeerPrefetchCoordinator: ObservableObject {
    private var warmedKeys: Set<String> = []
    private var pending: Task<Void, Never>?

    func schedule(_ media: SeerResult, using seer: JellyseerrClient?) {
        guard let seer, media.isMovie || media.isTV else { return }
        let key = "\(media.mediaType)-\(media.id)"
        guard !warmedKeys.contains(key) else { return }

        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(550))
            guard !Task.isCancelled else { return }
            await seer.prefetch(media)
            guard !Task.isCancelled else { return }
            self?.warmedKeys.insert(key)
        }
    }

    func cancel() {
        pending?.cancel()
        pending = nil
    }
}
