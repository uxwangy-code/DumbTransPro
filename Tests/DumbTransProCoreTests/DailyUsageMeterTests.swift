import Foundation
import Testing
@testable import DumbTransProCore

struct DailyUsageMeterTests {
    private final class Clock: @unchecked Sendable {
        var current: Date
        init(_ date: Date = Date(timeIntervalSince1970: 1_750_000_000)) { current = date }
    }

    private func freshDefaults() -> UserDefaults {
        let suiteName = "test.usage-meter.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test func startsAtZeroAndIncrements() {
        let meter = DailyUsageMeter(defaults: freshDefaults())
        #expect(meter.count() == 0)
        meter.increment()
        meter.increment()
        #expect(meter.count() == 2)
    }

    @Test func resetsOnNewDay() {
        let clock = Clock()
        let meter = DailyUsageMeter(defaults: freshDefaults(), now: { clock.current })
        meter.increment()
        #expect(meter.count() == 1)

        clock.current = clock.current.addingTimeInterval(86400)
        #expect(meter.count() == 0)
        meter.increment()
        #expect(meter.count() == 1)
    }

    @Test func persistsAcrossInstancesSameDay() {
        let defaults = freshDefaults()
        let meter1 = DailyUsageMeter(defaults: defaults)
        meter1.increment()
        let meter2 = DailyUsageMeter(defaults: defaults)
        #expect(meter2.count() == 1)
    }
}
