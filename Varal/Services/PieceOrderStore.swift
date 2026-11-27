import Foundation

/// Persists the big pieces' order and side (`pieceOrder` in UserDefaults).
/// `preferredSide` only seeds the arrangement on first run or when a piece
/// is newly enabled; after a drag the stored arrangement wins.
public final class PieceOrderStore {
    public static let defaultsKey = "pieceOrder"
    public static let didChange = Notification.Name("ca.reggiespace.varal.pieceOrderChanged")

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var stored: PieceArrangement? {
        guard let dict = defaults.dictionary(forKey: Self.defaultsKey) else { return nil }
        return PieceArrangement(
            leading: dict["leading"] as? [String] ?? [],
            trailing: dict["trailing"] as? [String] ?? [])
    }

    public func save(_ arrangement: PieceArrangement) {
        defaults.set(["leading": arrangement.leading, "trailing": arrangement.trailing], forKey: Self.defaultsKey)
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    public func resolve(active: [(id: String, side: PieceAnchorSide)]) -> PieceArrangement {
        PieceArrangement.resolve(active: active, stored: stored)
    }
}
