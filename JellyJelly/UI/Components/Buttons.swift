import SwiftUI

/// Capsule button for hero/detail actions. Fills with the accent gradient
/// when focused, translucent white otherwise.
struct PillButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, prominent: prominent)
    }

    private struct PillBody: View {
        @Environment(\.isFocused) private var isFocused
        let configuration: ButtonStyle.Configuration
        let prominent: Bool

        var body: some View {
            configuration.label
                .font(.headline.weight(.semibold))
                .foregroundStyle(isFocused ? .white : Theme.textPrimary.opacity(0.9))
                .padding(.horizontal, 36)
                .padding(.vertical, 16)
                .background {
                    if isFocused {
                        Capsule().fill(Theme.accentGradient)
                    } else if prominent {
                        Capsule().fill(Color.white.opacity(0.16))
                    } else {
                        Capsule().fill(Color.white.opacity(0.08))
                    }
                }
                .overlay {
                    Capsule().strokeBorder(Color.white.opacity(isFocused ? 0.35 : 0.12), lineWidth: 1)
                }
                .shadow(color: isFocused ? Theme.accentB.opacity(0.5) : .clear, radius: 20, y: 8)
                .scaleEffect(isFocused ? 1.06 : 1)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isFocused)
        }
    }
}

/// Circular icon button (favorite, watched, …).
struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IconBody(configuration: configuration)
    }

    private struct IconBody: View {
        @Environment(\.isFocused) private var isFocused
        let configuration: ButtonStyle.Configuration

        var body: some View {
            configuration.label
                .font(.title3)
                .foregroundStyle(isFocused ? .white : Theme.textSecondary)
                .frame(width: 68, height: 68)
                .background {
                    Circle().fill(isFocused ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.white.opacity(0.08)))
                }
                .overlay {
                    Circle().strokeBorder(Color.white.opacity(isFocused ? 0.35 : 0.12), lineWidth: 1)
                }
                .scaleEffect(isFocused ? 1.1 : 1)
                .scaleEffect(configuration.isPressed ? 0.95 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isFocused)
        }
    }
}

/// Card-like focus treatment for a circular target (cast headshots). Grows and
/// rings itself with the accent gradient when focused, mirroring `.card`.
struct CircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CircleBody(configuration: configuration)
    }

    private struct CircleBody: View {
        @Environment(\.isFocused) private var isFocused
        let configuration: ButtonStyle.Configuration

        var body: some View {
            configuration.label
                .clipShape(Circle())
                .overlay {
                    Circle().strokeBorder(
                        isFocused ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.white.opacity(0.12)),
                        lineWidth: isFocused ? 4 : 1)
                }
                .shadow(color: isFocused ? .black.opacity(0.5) : .clear, radius: 18, y: 10)
                .scaleEffect(isFocused ? 1.12 : 1)
                .scaleEffect(configuration.isPressed ? 0.95 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isFocused)
        }
    }
}

/// Selectable capsule chip (season picker, sort options). Selection only
/// changes on click — unlike tvOS segmented pickers, which switch as focus
/// passes over them.
struct ChipButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        ChipBody(configuration: configuration, isSelected: isSelected)
    }

    private struct ChipBody: View {
        @Environment(\.isFocused) private var isFocused
        let configuration: ButtonStyle.Configuration
        let isSelected: Bool

        var body: some View {
            configuration.label
                .font(.callout.weight(.semibold))
                .foregroundStyle(isFocused || isSelected ? .white : Theme.textSecondary)
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .background {
                    if isFocused {
                        Capsule().fill(Theme.accentGradient)
                    } else if isSelected {
                        Capsule().fill(Color.white.opacity(0.18))
                    } else {
                        Capsule().fill(Color.white.opacity(0.06))
                    }
                }
                .scaleEffect(isFocused ? 1.06 : 1)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isFocused)
        }
    }
}

/// Small capsule tag: "Available", "Requested", genre chips…
struct Badge: View {
    let text: String
    var tint: Color = .white.opacity(0.15)
    var textColor: Color = .white

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(textColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Capsule().fill(tint))
    }
}
