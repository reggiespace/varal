import Foundation
import Testing
@testable import VaralKit

@Suite("URLSchemeRouter")
struct URLSchemeRouterTests {
    @Test("single-block plan parses")
    func singleBlock() {
        let url = URL(string: "varal://weekend?start=2026-06-04&end=2026-06-07&plan=summer")!
        let parsed = URLSchemeRouter.parse(url)
        #expect(parsed?.planID == "summer")
        #expect(parsed?.blocks == [VacationBlock(startDate: "2026-06-04", endDate: "2026-06-07")])
    }

    @Test("multi-block plan parses sorted")
    func multiBlock() {
        let url = URL(string: "varal://weekend?start=2026-09-03,2026-06-04&end=2026-09-06,2026-06-07&plan=two")!
        let parsed = URLSchemeRouter.parse(url)
        #expect(parsed?.blocks.map(\.startDate) == ["2026-06-04", "2026-09-03"])
    }

    @Test("rejects wrong scheme, host, missing plan, mismatched lists, bad dates")
    func rejections() {
        #expect(URLSchemeRouter.parse(URL(string: "https://weekend?start=2026-06-04&end=2026-06-07&plan=x")!) == nil)
        #expect(URLSchemeRouter.parse(URL(string: "varal://other?start=2026-06-04&end=2026-06-07&plan=x")!) == nil)
        #expect(URLSchemeRouter.parse(URL(string: "varal://weekend?start=2026-06-04&end=2026-06-07")!) == nil)
        #expect(URLSchemeRouter.parse(URL(string: "varal://weekend?start=2026-06-04&end=2026-06-07,2026-06-08&plan=x")!) == nil)
        #expect(URLSchemeRouter.parse(URL(string: "varal://weekend?start=not-a-date&end=2026-06-07&plan=x")!) == nil)
        #expect(URLSchemeRouter.parse(URL(string: "varal://weekend?start=2026-06-09&end=2026-06-07&plan=x")!) == nil)
    }

    @Test("re-hanging the same plan is idempotent, no duplicate slips")
    func idempotentRehang() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let slips = TaskSlipStore(fileURL: dir.appendingPathComponent("slips.json"))
        let store = HolidayPlanStore(
            fileURL: dir.appendingPathComponent("plans.json"),
            slipStore: slips, locale: .en)
        let url = URL(string: "varal://weekend?start=2026-06-04&end=2026-06-07&plan=p1")!
        let parsed = try #require(URLSchemeRouter.parse(url))
        // T-7d window for 2026-06-04 starts 2026-05-28.
        store.applyWeekendPlan(parsed, today: "2026-05-28")
        store.applyWeekendPlan(parsed, today: "2026-05-28")
        let reminders = slips.slips.filter { $0.sourcePlanID == "p1" }
        #expect(reminders.count == 1)
        #expect(store.plans["p1"]?.blocks.count == 1)
    }

    @Test("authoritative replacement removes orphaned reminder slips")
    func orphanRemoval() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let slips = TaskSlipStore(fileURL: dir.appendingPathComponent("slips.json"))
        let store = HolidayPlanStore(
            fileURL: dir.appendingPathComponent("plans.json"),
            slipStore: slips, locale: .en)
        let v1 = try #require(URLSchemeRouter.parse(
            URL(string: "varal://weekend?start=2026-06-04,2026-09-03&end=2026-06-07,2026-09-06&plan=p1")!))
        store.applyWeekendPlan(v1, today: "2026-05-28")
        #expect(slips.slips.filter { $0.sourcePlanID == "p1" }.count == 1)
        let v2 = try #require(URLSchemeRouter.parse(
            URL(string: "varal://weekend?start=2026-09-03&end=2026-09-06&plan=p1")!))
        store.applyWeekendPlan(v2, today: "2026-08-28")
        let remaining = slips.slips.filter { $0.sourcePlanID == "p1" }
        #expect(remaining.count == 1)
        #expect(remaining.first?.sourceBlockStart == "2026-09-03")
        #expect(store.plans["p1"]?.blocks.count == 1)
    }

    @Test("reminder slips match the exact bilingual templates")
    func bilingualTemplates() {
        #expect(UIStrings.reminderTitleEN(start: "2026-06-04", end: "2026-06-07")
            == "Long weekend (2026-06-04 \u{2013} 2026-06-07) \u{2014} confirm time off")
        #expect(UIStrings.reminderTitlePT(start: "2026-06-04", end: "2026-06-07")
            == "Feriad\u{00E3}o (2026-06-04 \u{2013} 2026-06-07) \u{2014} confirmar folga")
        #expect(UIStrings.reminderTimeLabel == "T-7d")
    }

    @Test("no reminder before T-7d; reminder on the day")
    func reminderWindow() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let slips = TaskSlipStore(fileURL: dir.appendingPathComponent("slips.json"))
        let store = HolidayPlanStore(
            fileURL: dir.appendingPathComponent("plans.json"),
            slipStore: slips, locale: .pt)
        let parsed = URLSchemeRouter.parse(
            URL(string: "varal://weekend?start=2026-06-04&end=2026-06-07&plan=p1")!)!
        store.applyWeekendPlan(parsed, today: "2026-05-20") // T-15: nothing
        #expect(slips.slips.isEmpty)
        store.applyWeekendPlan(parsed, today: "2026-06-04") // T-0: pinned, PT template
        #expect(slips.slips.count == 1)
        #expect(slips.slips.first?.timeLabel == "T-7d")
        #expect(slips.slips.first?.title == "Feriad\u{00E3}o (2026-06-04 \u{2013} 2026-06-07) \u{2014} confirmar folga")
    }
}
