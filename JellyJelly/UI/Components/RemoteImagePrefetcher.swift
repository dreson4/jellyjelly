import Foundation
import Kingfisher

@MainActor
final class RemoteImagePrefetcher {
    static let shared = RemoteImagePrefetcher()

    private var warmedURLs: Set<URL> = []
    private var activePrefetcher: ImagePrefetcher?

    private init() {}

    func prefetch(_ urls: [URL?], limit: Int = 8) {
        var seen: Set<URL> = []
        let targets = urls.compactMap { $0 }
            .filter { seen.insert($0).inserted && !warmedURLs.contains($0) }
            .prefix(limit)

        guard !targets.isEmpty else { return }
        let targetURLs = Array(targets)
        targetURLs.forEach { warmedURLs.insert($0) }

        activePrefetcher?.stop()
        activePrefetcher = ImagePrefetcher(urls: targetURLs, options: [.cacheOriginalImage])
        activePrefetcher?.start()
    }
}
