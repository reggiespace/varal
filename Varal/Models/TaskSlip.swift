import Foundation

/// Slip lifecycle. There is deliberately no `.archived` state (review D-7):
/// slips in the basket are DELETED on 04:00 AM rollover / [Limpar cesto].
public enum SlipState: Codable, Equatable, Sendable {
    case hanging
    case inBasket(completedAt: Date)
}

/// Immutable paper slip. `title` and `timeLabel` never change after pinning;
/// to fix a typo, tear the slip off and pin a new one.
public struct TaskSlip: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    /// Leading "HH:mm" token, creation-time "HH:mm", or "T-7d" for GLW slips.
    public let timeLabel: String
    /// Immutable once pinned.
    public let title: String
    public let createdAt: Date
    /// Clothespin slot on the rope, preserved while .hanging or .inBasket.
    public var pinSlotIndex: Int
    public var state: SlipState
    /// Incremented at 04:00 AM rollover while .hanging.
    public var weatheredDays: Int
    /// Non-nil when spawned by a Get Long Weekend block.
    public var sourcePlanID: String?
    /// ISO-8601 date of the associated vacation block.
    public var sourceBlockStart: String?

    public init(
        id: UUID = UUID(),
        timeLabel: String,
        title: String,
        createdAt: Date = Date(),
        pinSlotIndex: Int,
        state: SlipState = .hanging,
        weatheredDays: Int = 0,
        sourcePlanID: String? = nil,
        sourceBlockStart: String? = nil
    ) {
        self.id = id
        self.timeLabel = timeLabel
        self.title = title
        self.createdAt = createdAt
        self.pinSlotIndex = pinSlotIndex
        self.state = state
        self.weatheredDays = weatheredDays
        self.sourcePlanID = sourcePlanID
        self.sourceBlockStart = sourceBlockStart
    }

    public var isHanging: Bool {
        if case .hanging = state { return true }
        return false
    }
}
