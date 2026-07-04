import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}

/// JellyJelly design system: deep night background, jellyfin-inspired
/// violet→pink accent, Netflix-style shelves.
enum Theme {
    static let background = Color(hex: 0x0A0B12)
    static let backgroundElevated = Color(hex: 0x151725)
    static let accentA = Color(hex: 0x7B5CFF)   // violet
    static let accentB = Color(hex: 0xC44FE2)   // magenta
    static let accentC = Color(hex: 0xFF5CA8)   // pink

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.65)
    static let textTertiary = Color.white.opacity(0.4)

    static let accentGradient = LinearGradient(
        colors: [accentA, accentB, accentC],
        startPoint: .leading, endPoint: .trailing)

    /// Full-screen app background: near-black with a faint violet bloom.
    static var backgroundGradient: some View {
        ZStack {
            background
            LinearGradient(
                colors: [Color(hex: 0x141327), background.opacity(0)],
                startPoint: .top, endPoint: .center)
            RadialGradient(
                colors: [accentA.opacity(0.12), .clear],
                center: .topTrailing, startRadius: 0, endRadius: 1400)
        }
        .ignoresSafeArea()
    }

    /// Placeholder shown while artwork loads (or when there is none).
    static let placeholderGradient = LinearGradient(
        colors: [Color(hex: 0x232438), Color(hex: 0x15161F)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    // Card dimensions (tvOS layout space is 1920×1080 points).
    static let posterWidth: CGFloat = 220
    static let posterHeight: CGFloat = 330
    static let wideCardWidth: CGFloat = 400
    static let wideCardHeight: CGFloat = 225
    static let shelfSpacing: CGFloat = 36
}

/// Formats seconds like "1h 12m left".
func remainingLabel(totalTicks: Int64?, positionTicks: Int64?) -> String? {
    guard let total = totalTicks, let position = positionTicks, total > position else { return nil }
    let minutes = Int((total - position) / 600_000_000)
    if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m left" }
    return "\(max(minutes, 1))m left"
}
