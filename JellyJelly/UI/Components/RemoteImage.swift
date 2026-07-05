import Kingfisher
import SwiftUI
import UIKit

/// Kingfisher-backed remote image with downsampling, disk/memory cache, and
/// cancellation handled by the library.
struct RemoteImage: View {
    let url: URL?
    var contentMode: SwiftUI.ContentMode = .fill

    @State private var failedURL: URL?

    var body: some View {
        GeometryReader { proxy in
            if let url {
                KFImage.url(url)
                    .placeholder { placeholder(icon: nil) }
                    .setProcessor(DownsamplingImageProcessor(size: targetSize(for: proxy.size)))
                    .scaleFactor(UIScreen.main.scale)
                    .cacheOriginalImage()
                    .fade(duration: 0.12)
                    .cancelOnDisappear(true)
                    .onSuccess { _ in
                        if failedURL == url { failedURL = nil }
                    }
                    .onFailure { _ in
                        failedURL = url
                    }
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .overlay {
                        if failedURL == url {
                            placeholder(icon: "photo")
                        }
                    }
            } else {
                placeholder(icon: nil)
            }
        }
        .clipped()
        .onChange(of: url) { _, _ in
            failedURL = nil
        }
    }

    private func targetSize(for size: CGSize) -> CGSize {
        CGSize(width: max(size.width, 1), height: max(size.height, 1))
    }

    private func placeholder(icon: String?) -> some View {
        ZStack {
            Theme.placeholderGradient
            if let icon {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }
}
