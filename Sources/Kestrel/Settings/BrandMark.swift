import AppKit
import SwiftUI

/// Who made this and which version of it you are looking at.
enum AppInfo {
    /// From the bundle's `CFBundleShortVersionString`, which `build.sh` fills in from the top entry
    /// of the changelog. Absent under `swift run`, where there is no bundle to read.
    static var version: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    static let copyright = "© 2026 Ahsan Rao · MIT"

    /// One line: the version when there is one, and the notice either way.
    static var line: String {
        version.map { "Kestrel \($0) · \(copyright)" } ?? "Kestrel · \(copyright)"
    }
}

/// The logo on its own, no plate: the artwork `build.sh` copies in as `Logo.png`.
///
/// Right where it sits next to text at a small size, and wrong at a large one on dark glass — most
/// of the bird is a deep navy that all but vanishes against it. `AppIconMark` is the large one.
struct BrandMark: View {
    var size: CGFloat = 22

    var body: some View {
        Group {
            if let image = BrandMark.logo {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                Image(systemName: "bird.fill")
                    .resizable()
                    .foregroundStyle(KestrelPalette.accent)
            }
        }
        .aspectRatio(contentMode: .fit)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private static let logo: NSImage? = {
        if let url = BundleResources.url(for: "Logo.png"), let image = NSImage(contentsOf: url) {
            return image
        }
        return NSApp?.applicationIconImage
    }()
}

/// The app icon, plate and all, for the one place the product introduces itself.
///
/// Deliberately the icon rather than the bare mark: its plate is what carries the artwork against
/// a dark background, it is the thing the user will look for in the Dock afterwards, and it costs
/// no extra asset — every bundled app already has one.
struct AppIconMark: View {
    var size: CGFloat = 56

    var body: some View {
        Group {
            if let icon = NSApp?.applicationIconImage {
                Image(nsImage: icon).resizable().interpolation(.high)
            } else {
                BrandMark(size: size)
            }
        }
        .aspectRatio(contentMode: .fit)
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        .accessibilityHidden(true)
    }
}

/// The quiet strip along the bottom of Kestrel's windows: the mark, the version, the notice.
///
/// It earns its place twice — it says what this is and which build it is, and it gives the bottom
/// of a window somewhere to end rather than trailing off into empty glass.
struct BrandFooter: View {
    var body: some View {
        HStack(spacing: 8) {
            BrandMark(size: 15)
            Text(AppInfo.line)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 26)
        .padding(.bottom, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(AppInfo.line)
    }
}
