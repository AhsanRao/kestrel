import SwiftUI

/// The About page: which build this is, and who made it.
///
/// The only page with no `Form` heading above it — the mark and the name say what the heading would
/// have said, and twice is once too many.
struct AboutPane: View {
    var onOpenSetup: () -> Void
    var onCheckInstalled: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    AppIconMark(size: 68)
                    VStack(spacing: 3) {
                        Text("Kestrel")
                            .font(.system(size: 24, weight: .semibold))
                            .tracking(-0.4)
                        Text("Hover. Ask. Do.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Text(AppInfo.version.map { "Version \($0)" } ?? "Running from source")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(KestrelPalette.surfaceStrong, in: Capsule())
                }
                .padding(.top, 34)
                .padding(.bottom, 26)

                VStack(spacing: 0) {
                    fact("Made by", "Ahsan Rao")
                    Divider()
                    fact("Licence", "MIT")
                    Divider()
                    fact("Your files", Paths.tildeAbbreviated(Paths.root))
                }
                .glassPanel()

                VStack(spacing: 0) {
                    action("Setup & permissions", "checklist", onOpenSetup)
                    Divider()
                    action("Check what's installed", "stethoscope", onCheckInstalled)
                }
                .glassPanel()
                .padding(.top, 12)

                VStack(spacing: 6) {
                    Text("Runs on your own Claude and ChatGPT subscriptions. No backend, no "
                         + "telemetry, nothing kept anywhere but this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(AppInfo.copyright)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.top, 20)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).font(.system(size: 12))
                .textSelection(.enabled)
                .lineLimit(1).truncationMode(.middle)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func action(_ title: String, _ symbol: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(KestrelPalette.accent)
                    .frame(width: 17)
                Text(title).font(.system(size: 12))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
