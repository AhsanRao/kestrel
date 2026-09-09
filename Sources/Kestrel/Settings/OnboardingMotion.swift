import SwiftUI

/// The setup window's motion, in one place so the checklist, its rows and the progress bar settle
/// on the same spring — and so Reduce Motion turns all of them off together rather than one by one.
enum OnboardingMotion {
    /// Rows opening and closing, and the window settling once everything is in place.
    static let settle = Animation.spring(response: 0.35, dampingFraction: 0.85)
    static let progress = Animation.spring(response: 0.45, dampingFraction: 0.85)
    /// The one place overshoot is earned: a tick landing is the reward for granting a permission in
    /// another app and coming back.
    static let tick = Animation.spring(response: 0.3, dampingFraction: 0.55)
    /// How far apart consecutive rows arrive.
    static let stagger: Double = 0.045

    /// `nil` under Reduce Motion, which is how SwiftUI is told to apply a change without animating.
    static func honoring(_ reduceMotion: Bool, _ animation: Animation) -> Animation? {
        reduceMotion ? nil : animation
    }
}

/// Rows arrive one after another instead of all at once, which turns a wall of requirements into a
/// list the eye reads top to bottom. Under Reduce Motion they are simply already there — a delay is
/// the last thing someone who asked for less movement wants.
struct StaggeredEntrance: ViewModifier {
    let delay: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 8)
            .onAppear {
                guard !reduceMotion else { shown = true; return }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.85).delay(delay)) {
                    shown = true
                }
            }
    }
}
