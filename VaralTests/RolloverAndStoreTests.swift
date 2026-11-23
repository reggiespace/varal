import Foundation
import Testing
@testable import VaralKit

private func isolatedStore() -> (TaskSlipStore, URL) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let file = dir.appendingPathComponent("slips.json")
    return (TaskSlipStore(fileURL: file), file)
}

@Suite("RolloverAndStore")
struct RolloverAndStoreTests {
    @Test("quick-add parses leading HH:mm, defaults to now")
    func quickAddParsing() {
        let (time, title) = TaskSlipStore.parseQuickAdd("17:30 Buy coffee beans")
        #expect(time == "17:30")
        #expect(title == "Buy coffee beans")

        var comps = DateComponents()
        comps.year = 2026; comps.month = 11; comps.day = 16
        comps.hour = 9; comps.minute = 42
        let now = Calendar.current.date(from: comps)!
        let (t2, title2) = TaskSlipStore.parseQuickAdd("Buy coffee beans", now: now)
        #expect(t2 == "09:42")
        #expect(title2 == "Buy coffee beans")

        // Invalid time-like prefix is treated as title text.
        let (t3, title3) = TaskSlipStore.parseQuickAdd("25:99 nope", now: now)
        #expect(t3 == "09:42")
        #expect(title3 == "25:99 nope")
    }

    @Test("slip fields persist and remain immutable through store ops")
    func persistenceRoundTrip() {
        let (store, file) = isolatedStore()
        let slip = store.addTask("08:00 Standup")!
        #expect(slip.timeLabel == "08:00")
        #expect(slip.title == "Standup")

        let reloaded = TaskSlipStore(fileURL: file)
        #expect(reloaded.slips.count == 1)
        #expect(reloaded.slips.first?.title == "Standup")
        #expect(reloaded.slips.first?.pinSlotIndex == 0)

        // Tear-off + undo preserve identity, title, and slot.
        reloaded.tearOff(id: slip.id)
        #expect(reloaded.basketSlips.count == 1)
        reloaded.undoToLine(id: slip.id)
        let back = reloaded.hangingSlips.first
        #expect(back?.title == "Standup")
        #expect(back?.timeLabel == "08:00")
        #expect(back?.pinSlotIndex == 0)
    }

    @Test("[Limpar cesto] deletes basket slips and compacts slots")
    func emptyBasket() {
        let (store, _) = isolatedStore()
        let a = store.addTask("08:00 A")!
        let b = store.addTask("09:00 B")!
        let c = store.addTask("10:00 C")!
        store.tearOff(id: a.id)
        store.tearOff(id: c.id)
        #expect(store.basketSlips.count == 2)
        let deleted = store.deleteBasketSlips()
        #expect(deleted == 2)
        #expect(store.basketSlips.isEmpty)
        #expect(store.hangingSlips.map(\.id) == [b.id])
        #expect(store.hangingSlips.first?.pinSlotIndex == 0) // compacted to 0..<N
        // No .archived state exists anywhere.
        for slip in store.slips {
            if case .hanging = slip.state { continue }
            Issue.record("inBasket slip survived [Limpar cesto]")
        }
    }

    @Test("04:00 AM rollover deletes basket, weathers hanging slips")
    func rollover() {
        let (store, _) = isolatedStore()
        let a = store.addTask("08:00 A")!
        let b = store.addTask("09:00 B")!
        store.tearOff(id: a.id)
        let (deleted, weathered) = store.applyRollover()
        #expect(deleted == 1)
        #expect(weathered == 1)
        #expect(store.basketSlips.isEmpty)
        #expect(store.hangingSlips.count == 1)
        #expect(store.hangingSlips.first?.id == b.id)
        #expect(store.hangingSlips.first?.weatheredDays == 1)
        #expect(store.hangingSlips.first?.pinSlotIndex == 0)
    }

    @Test("rollover boundary fires once across 04:00, including wake-after-sleep")
    func rolloverBoundary() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        func at(_ h: Int, _ m: Int) -> Date {
            var c = DateComponents()
            c.year = 2026; c.month = 11; c.day = 16; c.hour = h; c.minute = m
            return cal.date(from: c)!
        }
        // Asleep at 03:50, wake at 06:10 -> crossed 04:00 -> roll.
        #expect(RolloverScheduler.shouldRoll(lastCheck: at(3, 50), now: at(6, 10), calendar: cal))
        // Same evening, no crossing.
        #expect(!RolloverScheduler.shouldRoll(lastCheck: at(22, 0), now: at(23, 30), calendar: cal))
        // Already rolled this morning: 05:00 -> 06:00 does not re-fire.
        #expect(!RolloverScheduler.shouldRoll(lastCheck: at(5, 0), now: at(6, 0), calendar: cal))
    }
}
