import AppKit

/// Which side of the center small-slip cluster a big piece hangs on
/// (Landscape mode). In Portrait mode all big pieces share Line 1.
public enum PieceAnchorSide: String, Codable, Sendable {
    case leading
    case trailing
}

/// Fixed geometry + sag contribution of a big companion piece.
public struct PieceSizeMetrics: Equatable, Sendable {
    /// Standard big piece width (170pt per spec).
    public let width: CGFloat
    /// Standard big piece height (205pt per spec).
    public let height: CGFloat
    /// Sag contribution in points (default 6.0pt per spec).
    public let massUnits: CGFloat

    public init(width: CGFloat = 170, height: CGFloat = 205, massUnits: CGFloat = 6.0) {
        self.width = width
        self.height = height
        self.massUnits = massUnits
    }
}

public enum PrecipitationState: String, Codable, Sendable {
    case clear
    case rain
    case snow
}

public enum SolarPhase: String, Codable, Sendable {
    case morning
    case day
    case dusk
    case night
}

/// Weather + solar telemetry posted by the Atmos web app via
/// `window.webkit.messageHandlers.varalEnvironment.postMessage(...)`.
public struct EnvironmentSnapshot: Codable, Equatable, Sendable {
    public let temperatureCelsius: Double
    public let windSpeedKmh: Double
    public let windDirectionDegrees: Double
    public let precipitation: PrecipitationState
    public let solarPhase: SolarPhase

    public init(
        temperatureCelsius: Double,
        windSpeedKmh: Double,
        windDirectionDegrees: Double,
        precipitation: PrecipitationState,
        solarPhase: SolarPhase
    ) {
        self.temperatureCelsius = temperatureCelsius
        self.windSpeedKmh = windSpeedKmh
        self.windDirectionDegrees = windDirectionDegrees
        self.precipitation = precipitation
        self.solarPhase = solarPhase
    }
}

/// Contract for every first-party big piece on the line.
///
/// Layout, catenary physics, hit-testing, and cluster-expansion math
/// operate strictly over `[any CompanionPiece]` and never name concrete
/// pieces. No polling surface: pieces push `environmentalBroadcast`
/// (or nil); per review ZO-2 there is no `updateCadence`/`refreshData`.
@MainActor
public protocol CompanionPiece: Identifiable {
    /// Stable ID persisted in `enabledCompanionPieceIDs`, e.g. "atmos".
    var pieceID: String { get }
    var displayName: String { get }
    var sizeMetrics: PieceSizeMetrics { get }
    /// Standard big piece: 2 clothespins.
    var pinCount: Int { get }
    var preferredSide: PieceAnchorSide { get }
    /// Optional wind/moisture/solar output consumed by the physics engine.
    /// Nil when the piece is offline — physics uses the calm fallback breeze.
    var environmentalBroadcast: EnvironmentSnapshot? { get }
    /// Card view mounted by `ClotheslineCanvasView` without downcasting.
    @MainActor var pieceView: NSView { get }
}

/// Namespace for the one collection-level operation over built-in pieces.
/// There is no registry class (review ZO-3): this filter is the whole
/// mechanism.
public enum CompanionPieces {
    /// Filters the built-in first-party pieces against the user's Settings
    /// selection (`enabledCompanionPieceIDs`).
    @MainActor
    public static func activePieces(
        from builtIn: [any CompanionPiece],
        enabledIDs: [String]
    ) -> [any CompanionPiece] {
        builtIn.filter { enabledIDs.contains($0.pieceID) }
    }
}
