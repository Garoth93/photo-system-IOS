import SwiftUI
import SweepCore

extension Color {
    init(rgb: RGBColor) {
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }
}

/// Accent / container / on-container colors of one role.
struct Tones: Sendable {
    let accent: Color
    let container: Color
    let onContainer: Color
}

/// Material 3 color roles generated from the seed color.
struct M3Theme: Sendable {
    let dark: Bool
    let primary: Color
    let onPrimary: Color
    let primaryContainer: Color
    let onPrimaryContainer: Color
    let secondaryContainer: Color
    let onSecondaryContainer: Color
    let tertiary: Color
    let tertiaryContainer: Color
    let onTertiaryContainer: Color
    let surface: Color
    let surfaceContainerLowest: Color
    let surfaceContainerLow: Color
    let surfaceContainer: Color
    let surfaceContainerHigh: Color
    let surfaceContainerHighest: Color
    let onSurface: Color
    let onSurfaceVariant: Color
    let outline: Color
    let outlineVariant: Color
    let error: Color
    let onError: Color
    let errorContainer: Color
    let onErrorContainer: Color
    let success: Color
    let successContainer: Color
    let onSuccessContainer: Color

    init(seed: String, dark: Bool) {
        let s = MaterialScheme(seed: seed, dark: dark)
        self.dark = dark
        primary = Color(rgb: s.primary)
        onPrimary = Color(rgb: s.onPrimary)
        primaryContainer = Color(rgb: s.primaryContainer)
        onPrimaryContainer = Color(rgb: s.onPrimaryContainer)
        secondaryContainer = Color(rgb: s.secondaryContainer)
        onSecondaryContainer = Color(rgb: s.onSecondaryContainer)
        tertiary = Color(rgb: s.tertiary)
        tertiaryContainer = Color(rgb: s.tertiaryContainer)
        onTertiaryContainer = Color(rgb: s.onTertiaryContainer)
        surface = Color(rgb: s.surface)
        surfaceContainerLowest = Color(rgb: s.surfaceContainerLowest)
        surfaceContainerLow = Color(rgb: s.surfaceContainerLow)
        surfaceContainer = Color(rgb: s.surfaceContainer)
        surfaceContainerHigh = Color(rgb: s.surfaceContainerHigh)
        surfaceContainerHighest = Color(rgb: s.surfaceContainerHighest)
        onSurface = Color(rgb: s.onSurface)
        onSurfaceVariant = Color(rgb: s.onSurfaceVariant)
        outline = Color(rgb: s.outline)
        outlineVariant = Color(rgb: s.outlineVariant)
        error = Color(rgb: s.error)
        onError = Color(rgb: dark ? TonalPalette(hue: 32, chroma: 80).tone(20) : RGBColor(red: 1, green: 1, blue: 1))
        errorContainer = Color(rgb: s.errorContainer)
        onErrorContainer = Color(rgb: s.onErrorContainer)
        success = Color(rgb: s.success)
        successContainer = Color(rgb: s.successContainer)
        onSuccessContainer = Color(rgb: s.onSuccessContainer)
    }

    static let fallback = M3Theme(seed: Palette.defaultAccent, dark: false)

    /// Colors used for "keep" (swipe left).
    var keep: Tones { Tones(accent: success, container: successContainer, onContainer: onSuccessContainer) }
    /// Colors used for "delete" (swipe right).
    var delete: Tones { Tones(accent: error, container: errorContainer, onContainer: onErrorContainer) }
}

extension EnvironmentValues {
    @Entry var m3: M3Theme = .fallback
}

/// Material 3 type scale, with the rounded system face for an expressive look.
extension Font {
    static let m3DisplaySmall = Font.system(size: 36, weight: .bold, design: .rounded)
    static let m3HeadlineLarge = Font.system(size: 32, weight: .bold, design: .rounded)
    static let m3HeadlineMedium = Font.system(size: 28, weight: .semibold, design: .rounded)
    static let m3HeadlineSmall = Font.system(size: 24, weight: .semibold, design: .rounded)
    static let m3TitleLarge = Font.system(size: 22, weight: .semibold, design: .rounded)
    static let m3TitleMedium = Font.system(size: 17, weight: .semibold, design: .rounded)
    static let m3TitleSmall = Font.system(size: 15, weight: .semibold, design: .rounded)
    static let m3BodyLarge = Font.system(size: 17, weight: .regular)
    static let m3BodyMedium = Font.system(size: 15, weight: .regular)
    static let m3BodySmall = Font.system(size: 13, weight: .regular)
    static let m3LabelLarge = Font.system(size: 15, weight: .semibold, design: .rounded)
    static let m3LabelMedium = Font.system(size: 12, weight: .semibold, design: .rounded)
    static let m3LabelSmall = Font.system(size: 11, weight: .medium, design: .rounded)
}

extension Date {
    /// "12 marzo 2024 · 18:42"
    var sweepLabel: String {
        let it = Locale(identifier: "it_IT")
        let day = formatted(.dateTime.day().month(.wide).year().locale(it))
        let time = formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(it))
        return "\(day) · \(time)"
    }
}
