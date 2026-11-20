import Foundation

/// Parses `varal://weekend?start=...&end=...&plan=...` deep links.
///
/// The comma-separated `start`/`end` lists are the complete authoritative
/// block list for `planID`. Re-hanging the same plan replaces blocks in
/// place (idempotent, no duplication).
public enum URLSchemeRouter {
    public struct WeekendPlan: Equatable, Sendable {
        public let planID: String
        public let blocks: [VacationBlock]
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.isLenient = false
        return f
    }()

    public static func isValidISODate(_ s: String) -> Bool {
        guard s.count == 10 else { return false }
        return dateFormatter.date(from: s) != nil
    }

    public static func parse(_ url: URL) -> WeekendPlan? {
        guard url.scheme?.lowercased() == "varal" else { return nil }
        guard url.host?.lowercased() == "weekend" else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let query = components.queryItems ?? []
        func values(_ name: String) -> [String] {
            query.filter { $0.name == name }.compactMap(\.value)
                .flatMap { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
                .filter { !$0.isEmpty }
        }
        let starts = values("start")
        let ends = values("end")
        let planIDs = values("plan")
        guard let planID = planIDs.first, !planID.isEmpty else { return nil }
        guard !starts.isEmpty, starts.count == ends.count else { return nil }
        var blocks: [VacationBlock] = []
        for (s, e) in zip(starts, ends) {
            guard isValidISODate(s), isValidISODate(e), s <= e else { continue }
            blocks.append(VacationBlock(startDate: s, endDate: e))
        }
        guard !blocks.isEmpty else { return nil }
        blocks.sort { $0.startDate < $1.startDate }
        return WeekendPlan(planID: planID, blocks: blocks)
    }
}
