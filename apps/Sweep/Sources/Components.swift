import SwiftUI

// MARK: - Surfaces

/// Material 3 card: tonal surface, large continuous corners.
struct M3Card<Content: View>: View {
    @Environment(\.m3) private var m3
    var color: Color?
    var padding: CGFloat
    var corner: CGFloat
    let content: Content

    init(color: Color? = nil, padding: CGFloat = 16, corner: CGFloat = 28, @ViewBuilder content: () -> Content) {
        self.color = color
        self.padding = padding
        self.corner = corner
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color ?? m3.surfaceContainerLow, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

/// Scalloped "cookie" shape from the Material 3 Expressive shape set.
struct CookieShape: Shape {
    var lobes: Int = 9
    var depth: CGFloat = 0.06

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let base = min(rect.width, rect.height) / 2
        let r0 = base * (1 - depth)
        var p = Path()
        let steps = 240
        for i in 0...steps {
            let a = Double(i) / Double(steps) * 2 * .pi - .pi / 2
            let r = r0 + base * depth * cos(Double(lobes) * a)
            let pt = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

/// Icon on a tonal rounded square (or cookie).
struct IconBadge: View {
    let icon: String
    let tones: Tones
    var size: CGFloat = 44
    var cookie = false

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tones.onContainer)
            .frame(width: size, height: size)
            .background {
                if cookie {
                    CookieShape().fill(tones.container)
                } else {
                    RoundedRectangle(cornerRadius: size * 0.34, style: .continuous).fill(tones.container)
                }
            }
    }
}

/// Big expressive icon + title + message, used for empty and final states.
struct HeroMessage: View {
    @Environment(\.m3) private var m3
    let icon: String
    var tones: Tones?
    let title: String
    let message: String

    var body: some View {
        let t = tones ?? Tones(accent: m3.primary, container: m3.primaryContainer, onContainer: m3.onPrimaryContainer)
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(t.onContainer)
                .frame(width: 120, height: 120)
                .background(CookieShape().fill(t.container))
            Text(title)
                .font(.m3HeadlineSmall)
                .foregroundStyle(m3.onSurface)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.m3BodyMedium)
                .foregroundStyle(m3.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}

struct SectionTitle: View {
    @Environment(\.m3) private var m3
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.m3TitleMedium)
                .foregroundStyle(m3.onSurface)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.m3LabelLarge)
                    .foregroundStyle(m3.onSurfaceVariant)
            }
        }
        .padding(.top, 10)
        .padding(.horizontal, 6)
    }
}

// MARK: - Buttons

struct M3ButtonStyle: ButtonStyle {
    enum Kind { case filled, tonal, outlined, text, danger, dangerFilled }

    @Environment(\.m3) private var m3
    @Environment(\.isEnabled) private var isEnabled
    var kind: Kind
    var large = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(large ? .m3TitleSmall : .m3LabelLarge)
            .lineLimit(1)
            .padding(.horizontal, kind == .text ? 12 : 22)
            .frame(minHeight: large ? 56 : 44)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
            .overlay {
                if kind == .outlined { Capsule().strokeBorder(m3.outlineVariant, lineWidth: 1) }
            }
            .contentShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .filled: return m3.onPrimary
        case .tonal: return m3.onSecondaryContainer
        case .outlined, .text: return m3.primary
        case .danger: return m3.onErrorContainer
        case .dangerFilled: return m3.onError
        }
    }

    private var background: Color {
        switch kind {
        case .filled: return m3.primary
        case .tonal: return m3.secondaryContainer
        case .outlined, .text: return .clear
        case .danger: return m3.errorContainer
        case .dangerFilled: return m3.error
        }
    }
}

extension ButtonStyle where Self == M3ButtonStyle {
    static var m3Filled: M3ButtonStyle { M3ButtonStyle(kind: .filled) }
    static var m3FilledLarge: M3ButtonStyle { M3ButtonStyle(kind: .filled, large: true) }
    static var m3Tonal: M3ButtonStyle { M3ButtonStyle(kind: .tonal) }
    static var m3TonalLarge: M3ButtonStyle { M3ButtonStyle(kind: .tonal, large: true) }
    static var m3Outlined: M3ButtonStyle { M3ButtonStyle(kind: .outlined) }
    static var m3Text: M3ButtonStyle { M3ButtonStyle(kind: .text) }
    static var m3Danger: M3ButtonStyle { M3ButtonStyle(kind: .danger) }
    static var m3DangerLarge: M3ButtonStyle { M3ButtonStyle(kind: .dangerFilled, large: true) }
}

/// Plain press feedback for custom tappable surfaces.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(duration: 0.22), value: configuration.isPressed)
    }
}

/// Round tonal icon button (top bars).
struct IconButton: View {
    @Environment(\.m3) private var m3
    let icon: String
    var label: String
    var badge: Int = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(m3.onSurfaceVariant)
                .frame(width: 44, height: 44)
                .background(m3.surfaceContainerHigh, in: Circle())
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Text(badge > 999 ? "999+" : "\(badge)")
                            .font(.m3LabelSmall)
                            .monospacedDigit()
                            .foregroundStyle(m3.onError)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(m3.error, in: Capsule())
                            .offset(x: 6, y: -4)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}

// MARK: - Chips

struct FilterChip: View {
    @Environment(\.m3) private var m3
    let label: String
    var icon: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                } else if let icon {
                    Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                }
                Text(label).font(.m3LabelLarge).lineLimit(1)
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .foregroundStyle(selected ? m3.onSecondaryContainer : m3.onSurfaceVariant)
            .background(selected ? m3.secondaryContainer : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Color.clear : m3.outlineVariant, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .animation(.spring(duration: 0.25), value: selected)
    }
}

// MARK: - Progress

/// Material 3 linear progress indicator (with the gap between track and indicator).
struct M3Progress: View {
    let value: Double
    let color: Color
    let track: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { g in
            let v = min(1, max(0, value))
            HStack(spacing: v > 0 && v < 1 ? 4 : 0) {
                if v > 0 {
                    Capsule().fill(color).frame(width: max(height, (g.size.width - 4) * v))
                }
                if v < 1 {
                    Capsule().fill(track)
                }
            }
        }
        .frame(height: height)
        .animation(.spring(duration: 0.45), value: value)
    }
}

// MARK: - Snackbar

struct Snackbar: View {
    @Environment(\.m3) private var m3
    let text: String

    var body: some View {
        Text(text)
            .font(.m3BodyMedium)
            .foregroundStyle(m3.surface)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(m3.onSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
            .padding(.horizontal, 16)
    }
}
