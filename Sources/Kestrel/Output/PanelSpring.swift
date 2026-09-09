import Foundation

/// One number on a spring, integrated a frame at a time.
///
/// Parameterised the way SwiftUI's `.spring(response:dampingFraction:)` is, so the window and the
/// island drawn inside it can be handed the same two numbers and settle as one object.
struct Spring {
    var value: Double
    var velocity: Double = 0
    var target: Double

    /// The island's own spring, from `PanelView`.
    static let response: Double = 0.38
    static let dampingFraction: Double = 0.86

    init(value: Double, target: Double? = nil) {
        self.value = value
        self.target = target ?? value
    }

    /// Semi-implicit Euler. At this response a frame is a twentieth of a period, far inside where
    /// the integration stays stable, and it costs a fraction of what solving the closed form does.
    mutating func step(_ dt: Double) {
        let omega = 2 * Double.pi / Spring.response
        let acceleration = -omega * omega * (value - target)
            - 2 * Spring.dampingFraction * omega * velocity
        velocity += acceleration * dt
        value += velocity * dt
    }

    /// Within half a point of the target and slowing: closer than the screen can draw.
    var isSettled: Bool { abs(target - value) < 0.5 && abs(velocity) < 0.5 }

    mutating func settle() {
        value = target
        velocity = 0
    }
}
