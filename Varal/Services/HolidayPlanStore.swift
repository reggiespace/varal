import Foundation

/// Persists `VacationPlan` records to `holiday_plans.json` and owns the
/// State B lifecycle: authoritative block replacement, next-block countdown
/// resolution, and T-7d reminder-slip sync (idempotent, orphan-removing).
public final class HolidayPlanStore {
    public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Varal/holiday_plans.json", conformingTo: .json)
    }

    private let fileURL: URL
    private let slipStore: TaskSlipStore
    private let locale: AppLocale
    private var canPersist = true
    private(set) public var plans: [String: VacationPlan] = [:]

    public init(fileURL: URL? = nil, slipStore: TaskSlipStore, locale: AppLocale = .current()) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.slipStore = slipStore
        self.locale = locale
        load()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            plans = try JSONDecoder().decode([String: VacationPlan].self, from: Data(contentsOf: fileURL))
        } catch {
            canPersist = false
            NSLog("Varal: failed to load holiday_plans.json: \(error)")
        }
    }

    private func save() {
        guard canPersist else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(plans)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Varal: failed to save holiday_plans.json: \(error)")
        }
    }

    // MARK: - Authoritative replacement (idempotent)

    /// Replaces the block list for `planID` in place and re-syncs reminder
    /// slips. Re-hanging the same plan never duplicates card or slips.
    public func applyWeekendPlan(_ parsed: URLSchemeRouter.WeekendPlan, today: String, now: Date = Date()) {
        guard canPersist else { return }
        var plan = plans[parsed.planID] ?? VacationPlan(planID: parsed.planID, blocks: [])
        plan.blocks = parsed.blocks
        plan.updatedAt = now
        plans[parsed.planID] = plan
        save()
        syncReminderSlips(today: today, now: now)
    }

    // MARK: - Countdown

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    public static func todayString(_ date: Date = Date()) -> String {
        dayFormatter.string(from: date)
    }

    /// Next upcoming block across all plans (`endDate >= today`), earliest first.
    public func nextUpcomingBlock(today: String) -> (plan: VacationPlan, block: VacationBlock)? {
        var best: (VacationPlan, VacationBlock)?
        for plan in plans.values {
            for block in plan.blocks where block.endDate >= today {
                if best == nil || block.startDate < best!.1.startDate {
                    best = (plan, block)
                }
            }
        }
        return best
    }

    public var hasActivePlan: Bool {
        let today = Self.todayString()
        return nextUpcomingBlock(today: today) != nil
    }

    // MARK: - Reminder slips

    /// Days from `today` until `startDate` (negative = past). ISO strings
    /// compare lexicographically; day math uses the cached calendar below.
    public static func daysUntil(start: String, from today: String) -> Int? {
        guard let s = dayFormatter.date(from: start), let t = dayFormatter.date(from: today) else { return nil }
        return Calendar(identifier: .gregorian).dateComponents([.day], from: t, to: s).day
    }

    /// Ensures one reminder slip per block with `0 <= T <= 7 days`, keyed
    /// idempotently by `(sourcePlanID, sourceBlockStart)`; removes orphaned
    /// `.hanging` reminder slips whose block left the plan or is now >7d out.
    public func syncReminderSlips(today: String, now: Date = Date()) {
        var wanted: Set<String> = [] // "planID|blockStart"
        for plan in plans.values {
            for block in plan.blocks {
                guard let days = Self.daysUntil(start: block.startDate, from: today),
                      days >= 0, days <= 7
                else { continue }
                let key = "\(plan.planID)|\(block.startDate)"
                wanted.insert(key)
                let exists = slipStore.slips.contains {
                    $0.sourcePlanID == plan.planID && $0.sourceBlockStart == block.startDate
                }
                if !exists {
                    slipStore.pin(TaskSlip(
                        timeLabel: UIStrings.reminderTimeLabel,
                        title: UIStrings.reminderTitle(start: block.startDate, end: block.endDate, locale: locale),
                        createdAt: now,
                        pinSlotIndex: (slipStore.slips.map(\.pinSlotIndex).max() ?? -1) + 1,
                        sourcePlanID: plan.planID,
                        sourceBlockStart: block.startDate
                    ))
                }
            }
        }
        // Orphan sweep: hanging GLW reminders no longer wanted.
        for slip in slipStore.slips where slip.isHanging {
            guard let pid = slip.sourcePlanID, let start = slip.sourceBlockStart else { continue }
            if !wanted.contains("\(pid)|\(start)") {
                slipStore.removeSlip(id: slip.id)
            }
        }
    }
}
