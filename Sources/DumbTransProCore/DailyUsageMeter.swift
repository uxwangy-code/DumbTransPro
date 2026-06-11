import Foundation

/// 按自然日计数的本地用量表。Free tier 的每日翻译次数靠它结算；
/// 跨天自动归零，不需要后台任务，也不上报任何数据。
public struct DailyUsageMeter {
    private let defaults: UserDefaults
    private let now: () -> Date
    private let dateKey = "usage.daily.date"
    private let countKey = "usage.daily.count"

    public init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
    }

    public func count() -> Int {
        guard defaults.string(forKey: dateKey) == todayStamp() else { return 0 }
        return defaults.integer(forKey: countKey)
    }

    public func increment() {
        let today = todayStamp()
        if defaults.string(forKey: dateKey) != today {
            defaults.set(today, forKey: dateKey)
            defaults.set(1, forKey: countKey)
        } else {
            defaults.set(defaults.integer(forKey: countKey) + 1, forKey: countKey)
        }
    }

    private func todayStamp() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: now())
    }
}
