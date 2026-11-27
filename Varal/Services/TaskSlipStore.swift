import Foundation

/// Persists `TaskSlip` records atomically to `slips.json` under
/// `~/Library/Application Support/Varal/`. No accounts, no cloud,
/// no EventKit/Reminders sync.
public final class TaskSlipStore {
    public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Varal/slips.json", conformingTo: .json)
    }

    private let fileURL: URL
    private var canPersist = true
    public var canMutate: Bool { canPersist }
    private(set) public var slips: [TaskSlip] = []

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        load()
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            slips = try JSONDecoder().decode([TaskSlip].self, from: Data(contentsOf: fileURL))
        } catch {
            canPersist = false
            NSLog("Varal: failed to load slips.json: \(error)")
        }
    }

    private func save() -> Bool {
        guard canPersist else { return false }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(slips)
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            canPersist = false
            NSLog("Varal: failed to save slips.json: \(error)")
            return false
        }
    }

    // MARK: - Quick-add parsing

    /// Parses an optional leading 24-hour `HH:mm` token. Without one,
    /// `timeLabel` defaults to the current local `HH:mm`.
    public static func parseQuickAdd(_ input: String, now: Date = Date()) -> (timeLabel: String, title: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        if let first = tokens.first, isHHMM(String(first)), tokens.count == 2 {
            return (String(first), String(tokens[1]).trimmingCharacters(in: .whitespaces))
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_GB")
        return (formatter.string(from: now), trimmed)
    }

    private static func isHHMM(_ s: String) -> Bool {
        guard s.count == 5 else { return false }
        let chars = Array(s)
        guard chars[2] == ":" else { return false }
        guard let hh = Int(String(chars[0...1])), let mm = Int(String(chars[3...4])) else { return false }
        return (0..<24).contains(hh) && (0..<60).contains(mm)
    }

    // MARK: - Mutations

    private func nextSlotIndex() -> Int {
        (slips.map(\.pinSlotIndex).max() ?? -1) + 1
    }

    @discardableResult
    public func addTask(_ input: String, now: Date = Date()) -> TaskSlip? {
        guard canPersist else { return nil }
        let parsed = Self.parseQuickAdd(input, now: now)
        guard !parsed.title.isEmpty else { return nil }
        let slip = TaskSlip(timeLabel: parsed.timeLabel, title: parsed.title, createdAt: now, pinSlotIndex: nextSlotIndex())
        slips.append(slip)
        guard save() else {
            slips.removeAll { $0.id == slip.id }
            return nil
        }
        return slip
    }

    /// Test seam: pin a fully-formed slip (used by GLW reminder sync).
    public func pin(_ slip: TaskSlip) {
        guard canPersist else { return }
        let previous = slips
        slips.append(slip)
        if !save() { slips = previous }
    }

    /// Phase C: downward tear-off detaches the slip; the empty clothespin
    /// stays on the line (pinSlotIndex retained) at 18pt bare-pin pitch.
    @discardableResult
    public func tearOff(id: UUID, at date: Date = Date()) -> Bool {
        guard canPersist else { return false }
        guard let i = slips.firstIndex(where: { $0.id == id }), slips[i].isHanging else { return false }
        let previous = slips
        slips[i].state = .inBasket(completedAt: date)
        guard save() else { slips = previous; return false }
        return true
    }

    /// Undo: drag back from the basket restores `.hanging` at the same slot.
    @discardableResult
    public func undoToLine(id: UUID) -> Bool {
        guard canPersist else { return false }
        guard let i = slips.firstIndex(where: { $0.id == id }), !slips[i].isHanging else { return false }
        let previous = slips
        slips[i].state = .hanging
        guard save() else { slips = previous; return false }
        return true
    }

    /// Slide reorder: moves `id` to `position` in the occupied-slot order.
    /// Only hanging slips are permuted; empty pins (basket slips) keep their
    /// `pinSlotIndex` so basket undo still lands on its own pin.
    @discardableResult
    public func reorderHanging(id: UUID, toPosition position: Int) -> Bool {
        guard canPersist else { return false }
        let hanging = hangingSlips.map { (id: $0.id, slot: $0.pinSlotIndex) }
        guard hanging.contains(where: { $0.id == id }) else { return false }
        let remap = LineDrag.reorderedSlots(occupied: hanging, moving: id, toPosition: position)
        let previous = slips
        var changed = false
        for i in slips.indices {
            if let slot = remap[slips[i].id], slips[i].pinSlotIndex != slot {
                slips[i].pinSlotIndex = slot
                changed = true
            }
        }
        guard changed else { return true }
        guard save() else { slips = previous; return false }
        return true
    }

    public func removeSlip(id: UUID) {
        guard canPersist else { return }
        let previous = slips
        slips.removeAll { $0.id == id }
        if !save() { slips = previous }
    }

    public var hangingSlips: [TaskSlip] { slips.filter(\.isHanging) }
    public var basketSlips: [TaskSlip] { slips.filter { !$0.isHanging } }

    // MARK: - [Limpar cesto] / rollover deletion

    /// Permanently DELETES all `.inBasket` slips (no `.archived` state) and
    /// compacts remaining `.hanging` pinSlotIndex values to `0..<N`.
    /// Returns the number of deleted slips.
    @discardableResult
    public func deleteBasketSlips() -> Int {
        guard canPersist else { return 0 }
        let previous = slips
        let before = slips.count
        slips.removeAll { !$0.isHanging }
        compactSlotIndexes()
        guard save() else { slips = previous; return 0 }
        return before - slips.count
    }

    /// 04:00 AM rollover: basket slips deleted; hanging slips stay and
    /// weather (`weatheredDays += 1`).
    @discardableResult
    public func applyRollover() -> (deleted: Int, weathered: Int) {
        guard canPersist else { return (0, 0) }
        let previous = slips
        let before = slips.count
        slips.removeAll { !$0.isHanging }
        compactSlotIndexes()
        let deleted = before - slips.count
        var weathered = 0
        for i in slips.indices where slips[i].isHanging {
            slips[i].weatheredDays += 1
            weathered += 1
        }
        if !save() { slips = previous; return (0, 0) }
        return (deleted, weathered)
    }

    private func compactSlotIndexes() {
        let ordered = slips.sorted { $0.pinSlotIndex < $1.pinSlotIndex }
        var remapped: [UUID: Int] = [:]
        for (slot, slip) in ordered.enumerated() { remapped[slip.id] = slot }
        for i in slips.indices {
            slips[i].pinSlotIndex = remapped[slips[i].id] ?? slips[i].pinSlotIndex
        }
    }
}
