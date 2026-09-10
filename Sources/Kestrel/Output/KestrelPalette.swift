import AppKit
import SwiftUI

/// Kestrel's colours, in one place.
///
/// The bottom half is the brand: the values measured off the shipped artwork
/// (`assets/AppIconMaster.png`, `assets/KestrelMark.png`). The top half is what those values are
/// *for*, and it is the half the views use. Naming a colour by its job rather than its hue is what
/// stops a green tick in one window and a slightly different green tick in the next, and it means
/// the brand can be retuned in one place instead of thirty.
///
/// Every role that has to survive both themes is a *dynamic* colour: one value that resolves itself
/// against whatever appearance it is drawn into. That is not a nicety. Neither brand colour carries
/// on both grounds — aqua on light glass is 1.09:1 and navy on dark glass is 1.18:1 — so a single
/// fixed accent is invisible in one theme whichever of the two is picked.
enum KestrelPalette {
    // MARK: - Roles

    /// The one colour that says "this is Kestrel doing something": a tinted control, a filled step
    /// on the rail, an icon beside a feature, a progress bar.
    ///
    /// Dark gets the logo's aqua. Light gets `teal`, because the aqua is unreadable there and the
    /// navy, though it has the contrast, reads as plain black rather than as a colour — a step rail
    /// drawn in it is indistinguishable from an underline.
    static let accent = dynamic(light: 0x02_58_6F, dark: 0x02_F8_E6)
    /// What sits legibly on top of `accent`.
    static let onAccent = dynamic(light: 0xFF_FF_FF, dark: 0x02_1D_3D)

    /// The primary action's fill and the label on it. Navy under white in light (16.9:1), aqua
    /// under navy in dark (12.5:1) — each brand colour used on the ground it actually works on.
    static let primaryFill = dynamic(light: 0x02_1D_3D, dark: 0x02_F8_E6)
    static let onPrimaryFill = dynamic(light: 0xFF_FF_FF, dark: 0x02_1D_3D)

    /// The accent on the grounds Kestrel does not control: the island, whose fill is pure black,
    /// and the marks drawn over whatever happens to be on screen. Fixed rather than dynamic —
    /// neither of those follows the system theme, so neither may the colour on them.
    static let accentOnDark = aqua
    /// What sits legibly on `accentOnDark`.
    static let onAccentOnDark = navy
    /// Failure, on those same grounds.
    static let dangerOnDark = Color(hex: 0xE8_6E_43)

    /// Type and surfaces on the island's black, as a ladder rather than as an opacity picked afresh
    /// at each call site. Fixed for the same reason `accentOnDark` is: the island's fill does not
    /// follow the system theme, so nothing drawn on it may either.
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

    /// Done, granted, installed. Cooled towards the brand rather than the system's stock green, so
    /// a row of ticks beside an aqua rail reads as one palette.
    static let success = dynamic(light: 0x0E_8A_63, dark: 0x34_CA_98)
    /// Worth noticing but not broken — a download declined, a voice missing.
    static let warning = dynamic(light: 0xA8_6A_08, dark: 0xF2_AD_40)
    /// Failed, missing, required.
    static let danger = dynamic(light: 0xB3_3F_1C, dark: 0xE8_6E_43)

    /// A raised surface on the glass: a card, a group of rows.
    static let surface = Color.primary.opacity(0.05)
    static let surfaceBorder = Color.primary.opacity(0.09)
    /// A surface that has to read as a control rather than a container — a key cap, a chip.
    static let surfaceStrong = Color.primary.opacity(0.08)
    /// The unfilled half of a progress rail or a meter.
    static let track = Color.secondary.opacity(0.22)

    // MARK: - The brand itself

    /// The island's fill. Pure black with no opacity of its own and no material behind it, because
    /// it has to be the same colour as the camera housing it grows out of — anything lighter, or
    /// anything that lets the wallpaper through, puts a visible edge around the notch.
    static let housing = Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1)
    /// The logo's two colours, measured off the artwork: the bird's body, and its waveform.
    static let navy = Color(hex: 0x02_1D_3D)
    static let aqua = Color(hex: 0x02_F8_E6)
    /// The darker teal the artwork already contains where the waveform crosses the body. It is what
    /// the aqua has to become to sit on white — 7.99:1 there, against the aqua's 1.09:1.
    static let teal = Color(hex: 0x02_58_6F)
    /// A mid blue lifted for use on the island's black.
    static let sky = Color(hex: 0x67_AA_F2)
    static let idle = Color.secondary

    /// One colour that resolves itself against the appearance it is drawn into, so a call site can
    /// name the role and never ask which theme it is in — including the ones, like `.tint()`, that
    /// have no `ColorScheme` to hand.
    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(hex: dark) : NSColor(hex: light)
        })
    }
}

extension Color {
    /// `0xRRGGBB`, so a brand value can be written the way it is given rather than as three
    /// decimals that quietly drift from it.
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
