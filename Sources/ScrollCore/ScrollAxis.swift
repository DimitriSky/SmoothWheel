import Foundation

/// A critically damped spring. Analytic integration keeps the feel independent
/// of timer frequency. All of the requested distance is eventually delivered.
public struct ScrollAxis {
    public private(set) var remaining = 0.0
    public private(set) var velocity = 0.0
    private var fraction = 0.0

    public init() {}

    public var isMoving: Bool { remaining != 0 || velocity != 0 }

    public mutating func reset() {
        remaining = 0
        velocity = 0
        fraction = 0
    }

    public mutating func add(_ distance: Double) {
        guard distance.isFinite, distance != 0 else { return }
        // Reversing the wheel must immediately reverse the output.
        if distance * remaining < 0 || distance * velocity < 0 {
            reset()
        }
        remaining = max(-20_000, min(20_000, remaining + distance))
    }

    public mutating func advance(seconds dt: Double, settlingTime: Double) -> Int32 {
        guard dt.isFinite, dt > 0, isMoving else { return 0 }
        let duration = settlingTime.isFinite ? max(0.08, min(0.8, settlingTime)) : 0.28
        // Approximately 99% settled after the requested duration.
        let omega = 6.64 / duration
        let c = omega * remaining - velocity
        let decay = exp(-omega * dt)
        let nextRemaining = (remaining + c * dt) * decay
        let nextVelocity = (velocity + omega * c * dt) * decay
        var movement = remaining - nextRemaining
        remaining = nextRemaining
        velocity = nextVelocity

        if abs(remaining) < 0.01 && abs(velocity) < 0.1 {
            movement += remaining
            remaining = 0
            velocity = 0
        }

        // Keep subpixel residuals rather than losing them on each frame.
        fraction += movement
        let whole = fraction.rounded(.towardZero)
        fraction -= whole
        return Int32(whole)
    }
}
