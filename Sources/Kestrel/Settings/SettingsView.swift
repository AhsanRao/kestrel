import AppKit
import SwiftUI

/// Settings, as a sidebar and a page.
///
/// It was three tabs, and every one of them was a scroll — which is where a setting goes to be
/// lost. Eight short pages named in a list means the window itself is the index: you read down the
/// left until you find the word you had in mind, and the thing is on the screen with no scrolling.
///
/// The two columns are an `HStack` rather than a `NavigationSplitView`. The split view brings its
/// own sidebar material, which sits opaque in front of the glass, and its own selection highlight,
/// which is the Mac's accent colour and not Kestrel's — and neither can be turned off from SwiftUI.
/// Two views and a divider get the same layout with the appearance under our own control.
struct SettingsView: View {
    @StateObject private var model = SettingsModel()
    @StateObject private var status = OnboardingModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var section = SettingsView.initialSection

    var onOpenSetup: () -> Void = {}

    /// Room for the titlebar, which the glass runs underneath.
    private let titlebar: CGFloat = 30

    /// `KESTREL_PREVIEW_SETTINGS` names a page, for the preview harness.
    static var initialSection: SettingsSection {
        let name = ProcessInfo.processInfo.environment["KESTREL_PREVIEW_SETTINGS"] ?? ""
        return SettingsSection(rawValue: name) ?? .brain
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
        }
        .frame(width: 660, height: 560)
        .background(GlassBackground().ignoresSafeArea())
        .tint(KestrelPalette.accent)
        // A settling arrival, matching the panel and onboarding rather than the flat pop of a
        // stock window.
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 6)
        .onAppear {
            status.refresh()
            status.startPolling()
            guard !reduceMotion else { appeared = true; return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { appeared = true }
        }
        .onDisappear { status.stopPolling() }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsSection.allCases) { item in
                SidebarRow(item: item, isSelected: item == section) {
                    guard !reduceMotion else { return section = item }
                    withAnimation(.easeOut(duration: 0.16)) { section = item }
                }
            }
            Spacer(minLength: 12)
            // Pinned rather than a row in the list: it is not a page you visit, it is a light that
            // has to be on whichever page you are looking at.
            PermissionStrip(model: status, onFix: onOpenSetup)
        }
        .padding(.horizontal, 10)
        .padding(.top, titlebar + 8)
        .padding(.bottom, 10)
        .frame(width: 186)
    }

    // MARK: - Detail

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(section.title)
                    .font(.system(size: 19, weight: .semibold))
                    .tracking(-0.3)
                Text(section.caption)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.top, titlebar + 10)
            .padding(.bottom, 2)

            SettingsPane(section: section, model: model, onOpenSetup: onOpenSetup)
                .id(section)

            BrandFooter()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// One name in the sidebar, and the shape that says you are on it.
private struct SidebarRow: View {
    let item: SettingsSection
    let isSelected: Bool
    let select: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 9) {
                Image(systemName: item.symbol)
                    .font(.system(size: 12))
                    .frame(width: 17)
                Text(item.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? KestrelPalette.onAccent : .primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(background)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder private var background: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        if isSelected {
            shape.fill(KestrelPalette.accent)
        } else if isHovering {
            shape.fill(KestrelPalette.surface)
        }
    }
}
