import XCTest
@testable import ScrollCore

final class ScrollAxisTests: XCTestCase {
    private func run(hz: Double, distance: Double = 240) -> (Int, ScrollAxis) {
        var axis = ScrollAxis()
        axis.add(distance)
        var total = 0
        for _ in 0..<Int(hz * 3) {
            total += Int(axis.advance(seconds: 1 / hz, settlingTime: 0.3))
        }
        return (total, axis)
    }

    func testDistanceIsPreservedAtDifferentRefreshRates() {
        for hz in [30.0, 60, 120, 144, 240] {
            for distance in [240.0, -240, 1, -1, 7.5] {
                let (total, axis) = run(hz: hz, distance: distance)
                XCTAssertLessThanOrEqual(abs(Double(total) - distance), 1)
                XCTAssertFalse(axis.isMoving)
            }
        }
    }

    func testAnalyticMotionDoesNotDependOnFrameRate() {
        var a = ScrollAxis()
        var b = ScrollAxis()
        a.add(300)
        b.add(300)
        _ = a.advance(seconds: 0.1, settlingTime: 0.35)
        for _ in 0..<12 { _ = b.advance(seconds: 1 / 120, settlingTime: 0.35) }
        XCTAssertEqual(a.remaining, b.remaining, accuracy: 1e-8)
        XCTAssertEqual(a.velocity, b.velocity, accuracy: 1e-8)
    }

    func testReversalImmediatelyChangesDirection() {
        var axis = ScrollAxis()
        axis.add(300)
        for _ in 0..<5 { _ = axis.advance(seconds: 1 / 120, settlingTime: 0.3) }
        axis.add(-100)
        var total: Int32 = 0
        for _ in 0..<300 {
            let delta = axis.advance(seconds: 1 / 120, settlingTime: 0.3)
            XCTAssertLessThanOrEqual(delta, 0)
            total += delta
        }
        XCTAssertEqual(Double(total), -100, accuracy: 1)
    }

    func testRepeatedStepsAccumulateWithoutOvershooting() {
        var axis = ScrollAxis()
        var total = 0
        for frame in 0..<500 {
            if frame < 100 && frame % 10 == 0 { axis.add(40) }
            let delta = axis.advance(seconds: 1 / 120, settlingTime: 0.28)
            XCTAssertGreaterThanOrEqual(delta, 0)
            total += Int(delta)
        }
        XCTAssertEqual(Double(total), 400, accuracy: 1)
        XCTAssertFalse(axis.isMoving)
    }

    func testResetCancelsAllMotion() {
        var axis = ScrollAxis()
        axis.add(500)
        _ = axis.advance(seconds: 0.01, settlingTime: 0.3)
        axis.reset()
        XCTAssertEqual(axis.advance(seconds: 1, settlingTime: 0.3), 0)
        XCTAssertFalse(axis.isMoving)
    }

    func testInvalidInputAndLongPauseAreSafe() {
        var axis = ScrollAxis()
        axis.add(.nan)
        axis.add(.infinity)
        XCTAssertFalse(axis.isMoving)
        axis.add(100)
        XCTAssertEqual(axis.advance(seconds: .nan, settlingTime: 0.3), 0)
        XCTAssertEqual(axis.advance(seconds: 10, settlingTime: .nan), 100)
        XCTAssertFalse(axis.isMoving)
    }
}
