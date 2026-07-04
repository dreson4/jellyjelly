import SwiftUI

/// AsyncImage with a themed placeholder and a soft fade-in.
struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            case .failure:
                placeholder(icon: "photo")
            case .empty:
                placeholder(icon: nil)
            @unknown default:
                placeholder(icon: nil)
            }
        }
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
