import SwiftUI

/// Kestrel's colours, in one place.
///
/// The bottom half is the brand: the six values read off the shipped logo
/// (`assets/kestrel-logo.svg`) — a deep navy body and a cyan waveform. The top half is what those
/// values are *for*, and it is the half the views use. Naming a colour by its job rather than its
/// hue is what stops a green tick in one window and a slightly different green tick in the next,
/// and it means the brand can be retuned in one place instead of thirty.
enum KestrelPalette {
    // MARK: - Roles

    /// The brand mark, and the one colour that says "this is Kestrel doing something": the
    /// waveform, a filled step on the rail, a drawn mark on the screen.
    static let accent = cyan
    /// Accent on a light background, where cyan on white is unreadable.
    static let accentDeep = blue
    /// Accent on the island, whose fill is pure black.
    static let accentOnDark = sky

    /// Done, granted, installed. Cooled towards the brand rather than the system's stock green, so
    /// a row of ticks beside a cyan rail reads as one palette.
    static let success = Color(red: 0.204, green: 0.792, blue: 0.596)
    /// Worth noticing but not broken — a download declined, a voice missing.
    static let warning = Color(red: 0.949, green: 0.678, blue: 0.251)
    /// Failed, missing, required. The logo's own warm counterweight to all that cyan.
    static let danger = coral

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
    static let navy = Color(red: 0.059, green: 0.125, blue: 0.220)
    static let cyan = Color(red: 0.165, green: 0.941, blue: 0.855)
    static let blue = Color(red: 0.180, green: 0.361, blue: 0.541)
    /// The same blue, lifted for use on black.
    static let sky = Color(red: 0.404, green: 0.667, blue: 0.949)
    static let cream = Color(red: 0.961, green: 0.945, blue: 0.910)
    static let coral = Color(red: 0.847, green: 0.353, blue: 0.188)
    static let idle = Color.secondary
}
