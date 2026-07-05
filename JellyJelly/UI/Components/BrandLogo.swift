import SwiftUI

struct BrandLogo: View {
    var size: CGFloat = 84
    var cornerRadius: CGFloat = 22

    var body: some View {
        Image("JellyJellyLogo")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
            }
            .shadow(color: Theme.accentB.opacity(0.35), radius: size * 0.24, y: size * 0.08)
    }
}
