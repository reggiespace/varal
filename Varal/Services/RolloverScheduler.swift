import Foundation

/// Triggers the daily 04:00 AM local rollover. Basket slips are DELETED,
/// hanging slips stay and weather (`weatheredDays += 1`). Also fires on wake
/// when 04:00 AM was crossed while asleep.
public enum RolloverScheduler {
    public static let rolloverHour = 4

    /// True when `now` is on a later rollover boundary than `lastCheck`:
    /// i.e. a 04:00 AM instant exists in `(lastCheck, now]`.
    public static func shouldRoll(lastCheck: Date, now: Date, calendar: Calendar = .current) -> Bool {
        guard now > lastCheck else { return false }
        guard let next = nextRollover(after: lastCheck, calendar: calendar) else { return false }
        return next <= now
    }

    /// Next 04:00 AM strictly after `date`.
    public static func nextRollover(after date: Date, calendar: Calendar = .current) -> Date? {
        var comps = calendar.dateComponents([.year, .month, .day], from: date)
        comps.hour = rolloverHour
        comps.minute = 0
        comps.second = 0
        guard let today4am = calendar.date(from: comps) else { return nil }
        if today4am > date { return today4am }
        return calendar.date(byAdding: .day, value: 1, to: today4am)
    }

    @discardableResult
    public static func performRollover(on store: TaskSlipStore) -> (deleted: Int, weathered: Int) {
        store.applyRollover()
    }
}
