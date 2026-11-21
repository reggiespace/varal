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

    private func save() {
        guard canPersist else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(slips)
            let tmp = fileURL.appendingPathExtension("tmp")
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Varal: failed to save slips.json: \(error)")
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
        let parsed = Self.parseQuickAdd(input, now: now)
        guard !parsed.title.isEmpty else { return nil }
        let slip = TaskSlip(timeLabel: parsed.timeLabel, title: parsed.title, createdAt: now, pinSlotIndex: nextSlotIndex())
        slips.append(slip)
        save()
        return slip
    }

    /// Test seam: pin a fully-formed slip (used by GLW reminder sync).
    public func pin(_ slip: TaskSlip) {
        slips.append(slip)
        save()
    }

    /// Phase C: downward tear-off detaches the slip; the empty clothespin
    /// stays on the line (pinSlotIndex retained) at 18pt bare-pin pitch.
    public func tearOff(id: UUID, at date: Date = Date()) {
        guard let i = slips.firstIndex(where: { $0.id == id }), slips[i].isHanging else { return }
        slips[i].state = .inBasket(completedAt: date)
        save()
    }

    /// Undo: drag back from the basket restores `.hanging` at the same slot.
    public func undoToLine(id: UUID) {
        guard let i = slips.firstIndex(where: { $0.id == id }), !slips[i].isHanging else { return }
        slips[i].state = .hanging
        save()
    }

    public func removeSlip(id: UUID) {
        slips.removeAll { $0.id == id }
        save()
    }

    public var hangingSlips: [TaskSlip] { slips.filter(\.isHanging) }
    public var basketSlips: [TaskSlip] { slips.filter { !$0.isHanging } }

    // MARK: - [Limpar cesto] / rollover deletion

    /// Permanently DELETES all `.inBasket` slips (no `.archived` state) and
    /// compacts remaining `.hanging` pinSlotIndex values to `0..<N`.
    /// Returns the number of deleted slips.
    @discardableResult
    public func deleteBasketSlips() -> Int {
        let before = slips.count
        slips.removeAll { !$0.isHanging }
        compactSlotIndexes()
        save()
        return before - slips.count
    }

    /// 04:00 AM rollover: basket slips deleted; hanging slips stay and
    /// weather (`weatheredDays += 1`).
    @discardableResult
    public func applyRollover() -> (deleted: Int, weathered: Int) {
        let deleted = deleteBasketSlips()
        var weathered = 0
        for i in slips.indices where slips[i].isHanging {
            slips[i].weatheredDays += 1
            weathered += 1
        }
        save()
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
