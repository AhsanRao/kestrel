import SwiftUI

/// The voice row's controls: download, watch it arrive, or skip. Its own view because it is the
/// only checklist row with state beyond granted/not-granted.
struct KokoroRowAction: View {
    @ObservedObject var downloader: KokoroDownloader
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            switch downloader.phase {
            case .downloading, .installing:
                DownloadMeter(fraction: downloader.fraction, caption: caption)
                Button("Cancel") { downloader.cancel() }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            case .failed(let message):
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(KestrelPalette.danger)
                    .frame(width: 168, alignment: .trailing)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try again") { downloader.start() }
                    .buttonStyle(KestrelPrimaryButton(size: 11))
            default:
                Button("Download") { downloader.start() }
                    .buttonStyle(KestrelPrimaryButton(size: 11))
                Button("Use macOS voice") { model.skipKokoro() }
                    .buttonStyle(KestrelSecondaryButton(size: 11))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: downloader.phase)
    }

    private var caption: String {
        switch downloader.phase {
        case .downloading(let received, let total):
            let f = ByteCountFormatter()
            f.allowedUnits = [.useMB]
            f.countStyle = .file
            return "\(f.string(fromByteCount: received)) of \(f.string(fromByteCount: total))"
        case .installing: return "Unpacking…"
        default: return ""
        }
    }
}

/// Fills as bytes land. The travelling highlight keeps a slow download looking alive.
private struct DownloadMeter: View {
    let fraction: Double
    let caption: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmer: CGFloat = -1

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ZStack(alignment: .leading) {
                Capsule().fill(KestrelPalette.track)
                Capsule()
                    .fill(KestrelPalette.accent)
                    .frame(width: max(6, 168 * fraction))
                    .overlay(alignment: .leading) {
                        if !reduceMotion {
                            Capsule()
                                .fill(LinearGradient(
                                    colors: [.clear, KestrelPalette.onAccent.opacity(0.55), .clear],
                                    startPoint: .leading, endPoint: .trailing))
                                .frame(width: 52)
                                .offset(x: shimmer * (168 * fraction + 52) - 26)
                                .blendMode(.plusLighter)
                        }
                    }
                    .clipShape(Capsule())
            }
            .frame(width: 168, height: 5)
            .animation(.easeOut(duration: 0.35), value: fraction)

            Text(caption)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                shimmer = 1.4
            }
        }
    }
}
