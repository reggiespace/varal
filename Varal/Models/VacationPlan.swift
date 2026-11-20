import Foundation

public struct VacationBlock: Codable, Equatable, Sendable {
    /// ISO-8601 "YYYY-MM-DD".
    public let startDate: String
    /// ISO-8601 "YYYY-MM-DD".
    public let endDate: String

    public init(startDate: String, endDate: String) {
        self.startDate = startDate
        self.endDate = endDate
    }
}

public struct VacationPlan: Codable, Equatable, Sendable {
    /// Deterministic ID from `varal://weekend?...&plan=<id>`.
    public let planID: String
    /// Sorted chronologically by startDate.
    public var blocks: [VacationBlock]
    public var updatedAt: Date

    public init(planID: String, blocks: [VacationBlock], updatedAt: Date = Date()) {
        self.planID = planID
        self.blocks = blocks
        self.updatedAt = updatedAt
    }
}
