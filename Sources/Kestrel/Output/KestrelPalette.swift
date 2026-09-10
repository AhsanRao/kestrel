import AppKit
import SwiftUI

/// Kestrel's colours, in one place. Views name a role; only this file names a hue.
///
/// Roles that must survive both themes are *dynamic* colours — one value that resolves itself
/// against the appearance it is drawn into. Neither brand colour carries on both grounds (aqua on
/// light glass is 1.09:1, navy on dark glass is 1.18:1), so a fixed accent is invisible in one
/// theme whichever is picked.
enum KestrelPalette {
    // MARK: - Roles

    /// "This is Kestrel doing something": a tinted control, a filled step, a feature's icon.
    /// Light gets teal, not navy — navy has the contrast but reads as black, so a rail drawn in it
    /// is indistinguishable from an underline.
    static let accent = dynamic(light: Brand.teal, dark: Brand.aqua)
    /// What sits legibly on top of `accent`.
    static let onAccent = dynamic(light: Brand.white, dark: Brand.navy)

    /// The primary action's fill and the label on it. Navy under white in light (16.9:1), aqua
    /// under navy in dark (12.5:1) — each brand colour used on the ground it actually works on.
    static let primaryFill = dynamic(light: Brand.navy, dark: Brand.aqua)
    static let onPrimaryFill = dynamic(light: Brand.white, dark: Brand.navy)

    /// The accent on grounds Kestrel does not control: the island's black, and marks drawn over
    /// whatever is on screen. Fixed — neither follows the system theme.
    static let accentOnDark = Color(hex: Brand.aqua)
    /// What sits legibly on `accentOnDark`.
    static let onAccentOnDark = Color(hex: Brand.navy)
    /// Failure, on those same grounds.
    static let dangerOnDark = Color(hex: 0xE8_6E_43)

    /// Type and surfaces on the island's black, as a ladder rather than an opacity picked afresh at
    /// each call site.
    static let onHousing = Color.white
    static let onHousingBody = Color.white.opacity(0.92)
    static let onHousingSecondary = Color.white.opacity(0.60)
    static let onHousingMuted = Color.white.opacity(0.45)
    static let onHousingFaint = Color.white.opacity(0.35)
    /// A card on the island, and a control on it.
    static let surfaceOnHousing = Color.white.opacity(0.06)
    static let surfaceOnHousingBorder = Color.white.opacity(0.10)
    static let controlOnHousing = Color.white.opacity(0.12)
    /// The sheen that lifts the island's lower edge, and its drop shadow.
    static func housingSheen(strong: Bool) -> Color { .white.opacity(strong ? 0.18 : 0.10) }
    static let housingShadow = Color.black.opacity(0.38)
    /// A hairline under a mark drawn over unknown screen content, so it survives a pale background.
    static let markKeyline = Color.black.opacity(0.30)

    /// Done, granted, installed. Cooled towards the brand, so a row of ticks beside an aqua rail
    /// reads as one palette.
    static let success = dynamic(light: 0x0E_8A_63, dark: 0x34_CA_98)
    /// Worth noticing but not broken — a download declined, a voice missing.
    static let warning = dynamic(light: 0xA8_6A_08, dark: 0xF2_AD_40)
    /// Failed, missing, required. Also as an `NSColor`, for the menu, whose item titles are
    /// attributed strings rather than views.
    static let dangerColor = nsDynamic(light: 0xB3_3F_1C, dark: 0xE8_6E_43)
    static let danger = Color(nsColor: dangerColor)

    /// A raised surface on the glass: a card, a group of rows.
    static let surface = Color.primary.opacity(0.05)
    static let surfaceBorder = Color.primary.opacity(0.09)
    /// A surface that has to read as a control rather than a container — a key cap, a chip.
    static let surfaceStrong = Color.primary.opacity(0.08)
    /// The unfilled half of a progress rail or a meter.
    static let track = Color.secondary.opacity(0.22)

    // MARK: - The brand itself

    /// The numbers, written once. Every role above builds from these, so no hex appears twice.
    enum Brand {
        /// Measured off the artwork: the bird's body, and its waveform.
        static let navy: UInt32 = 0x02_1D_3D
        static let aqua: UInt32 = 0x02_F8_E6
        /// The darker teal the artwork already makes where the waveform crosses the body. It is
        /// what the aqua has to become to sit on white — 7.99:1 there, against the aqua's 1.09:1.
        static let teal: UInt32 = 0x02_58_6F
        /// The same family, lifted for the island's black.
        static let sky: UInt32 = 0x67_AA_F2
        static let white: UInt32 = 0xFF_FF_FF
    }

    /// The island's fill. Pure black with no opacity of its own and no material behind it: it has
    /// to match the camera housing it grows out of, and anything lighter, or anything that lets the
    /// wallpaper through, puts a visible edge around the notch.
    static let housing = Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1)
    static let sky = Color(hex: Brand.sky)
    static let idle = Color.secondary

    /// Resolves itself against the appearance it is drawn into, so a call site never asks which
    /// theme it is in — including `.tint()`, which has no `ColorScheme` to hand.
    private static func nsDynamic(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(hex: dark) : NSColor(hex: light)
        }
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: nsDynamic(light: light, dark: dark))
    }
}

extension Color {
    /// `0xRRGGBB`, so a brand value is written the way it is given.
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}
