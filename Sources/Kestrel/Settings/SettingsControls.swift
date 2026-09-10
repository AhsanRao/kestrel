import SwiftUI

/// A setting and the sentence explaining it, in one row instead of two. A `Form` row per
/// explanation costs a separator and two lots of padding, which is what made eight controls
/// overflow the window — and put each note under the row after the one it described.
struct Setting<Control: View>: View {
    let title: String
    var note: String?
    @ViewBuilder var control: () -> Control

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            LabeledContent(title) { control() }
            if let note { SettingNote(note) }
        }
    }
}

/// The same, for a toggle — whose label lives inside the control rather than beside it.
struct ToggleSetting: View {
    let title: String
    var note: String?
    @Binding var isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Toggle(title, isOn: $isOn)
            if let note { SettingNote(note) }
        }
    }
}

/// One explanation, at the size and colour every explanation uses.
struct SettingNote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Something worth noticing that is not an error: a voice missing, a download declined.
struct SettingWarning: View {
    let text: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(KestrelPalette.warning)
            VStack(alignment: .leading, spacing: 6) {
                Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    Button(actionTitle, action: action).controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The three macOS grants, as three dots at the foot of the sidebar. Not a page of their own:
/// they cannot be flipped from in here, and what is needed is to notice a revoked one at a glance.
struct PermissionStrip: View {
    @ObservedObject var model: OnboardingModel
    var onFix: () -> Void

    var body: some View {
        let missing = model.permissions.filter { !$0.ok }
        return Button(action: onFix) {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    ForEach(model.permissions, id: \.requirement) { item in
                        Circle()
                            .fill(item.ok ? KestrelPalette.success : KestrelPalette.danger)
                            .frame(width: 7, height: 7)
                    }
                }
                Text(missing.isEmpty ? "All access granted"
                                     : "\(missing.count) still needed")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassPanel(cornerRadius: 8)
        .help("Open setup to grant what's missing")
        .accessibilityLabel(missing.isEmpty
            ? "All access granted. Open setup."
            : "\(missing.map(\.requirement.title).joined(separator: ", ")) still needed. Open setup.")
    }
}
