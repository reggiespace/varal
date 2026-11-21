import Foundation

/// Pure catenary / kinematics math shared by the desktop canvas and the
/// menu-bar mini mirror. No AppKit: fully unit-testable.
///
/// Per-rope equilibrium sag (spec §2.4.1):
///   Δy_sag(k) = min(54pt, 8pt + Σ massUnits + 4.5pt·N_slips + W_moisture)
/// Rope curve: quadratic Bezier between `(0, y_k)` and `(W, y_k)` with
/// control point `(W/2, y_k + 1.85·Δy_sag)` → mid-span deflection 0.925·Δy.
public enum ClotheslineMath: Sendable {
    public static let maxSag: CGFloat = 54
    public static let baseSag: CGFloat = 8
    public static let slipMassUnits: CGFloat = 4.5
    public static let shingledStep: CGFloat = 38
    public static let sideBySidePitch: CGFloat = 116
    public static let emptyPinPitch: CGFloat = 18
    public static let slipSpacing: CGFloat = 12
    public static let slipWidth: CGFloat = 104
    public static let slipHeight: CGFloat = 126

    /// Moisture weight: clear 0pt, snow 5pt, rain 8pt.
    public static func moistureWeight(_ precipitation: PrecipitationState) -> CGFloat {
        switch precipitation {
        case .clear: return 0
        case .snow: return 5
        case .rain: return 8
        }
    }

    public static func equilibriumSag(
        bigPieceMassUnits: [CGFloat],
        hangingSlipCount: Int,
        precipitation: PrecipitationState
    ) -> CGFloat {
        let raw = baseSag
            + bigPieceMassUnits.reduce(0, +)
            + slipMassUnits * CGFloat(hangingSlipCount)
            + moistureWeight(precipitation)
        return min(maxSag, raw)
    }

    public static func controlPointYOffset(sag: CGFloat) -> CGFloat {
        1.85 * sag
    }

    public static func midSpanDeflection(sag: CGFloat) -> CGFloat {
        0.925 * sag
    }

    /// Cubic-Bezier control-point Y offset that reproduces the spec
    /// quadratic rope exactly: with C1=(W/3, y+a), C2=(2W/3, y+a), the
    /// cubic midpoint is y+3a/4; a=(4/3)*0.925*sag keeps the 0.925 mid-span
    /// deflection the slip layout math assumes (correction v1-app2: the old
    /// cubic used 0.55*1.85*sag and rendered ~0.76x sag, floating slips
    /// below the visible rope).
    public static func ropeCubicControlYOffset(sag: CGFloat) -> CGFloat {
        (4.0 / 3.0) * midSpanDeflection(sag: sag)
    }

    // MARK: - Tear-off phases (spec §2.4.3)

    public enum TearPhase: Equatable, Sendable {
        /// 0 < Δy_pull <= 18pt — elastic stretch, release springs back.
        case elastic
        /// 18 < Δy_pull <= 48pt — perforation unzip, release springs back.
        case perforation
        /// Δy_pull > 48pt — snap, recoil + flutter. Completes.
        case snap
    }

    public static func tearPhase(pull: CGFloat) -> TearPhase {
        if pull <= 18 { return .elastic }
        if pull <= 48 { return .perforation }
        return .snap
    }

    // MARK: - Cluster layout (spec §2.4.2)

    /// Unclustered side-by-side threshold: ≤3 slips (Landscape) / ≤5 (Line 2).
    public static func isClustered(slipCount: Int, portraitLine2: Bool) -> Bool {
        slipCount > (portraitLine2 ? 5 : 3)
    }

    /// Horizontal step between slip pins.
    public static func clusterStep(slipCount: Int, expanded: Bool, availableWidth: CGFloat, portraitLine2: Bool) -> CGFloat {
        if !isClustered(slipCount: slipCount, portraitLine2: portraitLine2) {
            return sideBySidePitch // 104pt slip + 12pt spacing
        }
        if !expanded { return shingledStep }
        guard slipCount > 1 else { return sideBySidePitch }
        return min(sideBySidePitch, max(0, availableWidth - slipWidth) / CGFloat(slipCount - 1))
    }

    // MARK: - Underdamped spring recoil (ω0 = 18 rad/s, ζ = 0.35)

    public struct SpringState: Sendable {
        public var position: CGFloat
        public var velocity: CGFloat
        public init(position: CGFloat, velocity: CGFloat = 0) {
            self.position = position
            self.velocity = velocity
        }
    }

    /// Semi-implicit Euler step of the sag spring toward equilibrium.
    public static func springStep(
        _ state: SpringState,
        equilibrium: CGFloat,
        dt: CGFloat,
        omega0: CGFloat = 18,
        zeta: CGFloat = 0.35
    ) -> SpringState {
        let accel = -omega0 * omega0 * (state.position - equilibrium)
            - 2 * zeta * omega0 * state.velocity
        var next = state
        next.velocity += accel * dt
        next.position += next.velocity * dt
        return next
    }

    /// Upward clamp: Line 1 never rises above topSafeMargin + 2pt.
    public static func clampedLineY(_ y: CGFloat, topSafeMargin: CGFloat) -> CGFloat {
        max(y, topSafeMargin + 2)
    }

    // MARK: - Layout mode + geometry

    public enum LayoutMode: Equatable, Sendable {
        /// width >= height: 1 rope.
        case landscape
        /// height > width: 2 stacked ropes.
        case portrait
    }

    public static func layoutMode(size: CGSize) -> LayoutMode {
        size.width >= size.height ? .landscape : .portrait
    }

    /// Top rope anchor. Displays with a menu bar clear it by `menuClearance`
    /// (correction v1-app2: the legacy `+14` sat the rope right under the
    /// menu bar on the 3440x1440 display); menu-less displays (e.g. the
    /// portrait Dell) keep the legacy 38pt anchor pixel-identical.
    public static let menuClearance: CGFloat = 28
    public static let legacyLineY: CGFloat = 38

    public static func lineY(topSafeInset: CGFloat) -> CGFloat {
        topSafeInset > 0 ? topSafeInset + menuClearance : legacyLineY
    }

    public static func secondLineY(firstLineY: CGFloat) -> CGFloat {
        firstLineY + 235
    }

    // MARK: - Ultrawide yard rules (correction v1-app2)

    /// Aspect ratio at or above which the landscape yard switches to
    /// proportional-thirds big-piece placement and width-aware slip layout.
    /// 21:9 (2.33) and wider qualify; 16:9 (1.78) and portrait do not.
    public static let ultrawideAspectThreshold: CGFloat = 2.0

    public static func isUltrawide(size: CGSize) -> Bool {
        layoutMode(size: size) == .landscape
            && size.height > 0
            && size.width / size.height >= ultrawideAspectThreshold
    }

    /// Leading piece center sits at W/3, trailing at 2W/3.
    public static func thirdsLeadingX(displayWidth: CGFloat, pieceWidth: CGFloat) -> CGFloat {
        displayWidth / 3 - pieceWidth / 2
    }

    public static func thirdsTrailingX(displayWidth: CGFloat, pieceWidth: CGFloat) -> CGFloat {
        2 * displayWidth / 3 - pieceWidth / 2
    }

    /// Ultrawide cluster step: slips lay side-by-side at full pitch while
    /// they fit the available span (no overlap); only beyond fit do they
    /// shingle (collapsed) or compress (expanded).
    public static func ultrawideClusterStep(
        slipCount: Int,
        expanded: Bool,
        availableWidth: CGFloat
    ) -> CGFloat {
        let needed = CGFloat(slipCount) * sideBySidePitch - slipSpacing
        if needed <= availableWidth { return sideBySidePitch }
        if !expanded { return shingledStep }
        guard slipCount > 1 else { return sideBySidePitch }
        return min(sideBySidePitch, max(0, availableWidth - slipWidth) / CGFloat(slipCount - 1))
    }

    // MARK: - Slot-stable cluster layout (correction v1-app2)

    /// X-origin of each slot `0..<slots.count` relative to the cluster
    /// start: a uniform `step` grid fixed by `pinSlotIndex`. Tearing a slip
    /// never moves its neighbors; only the pin graphic at an empty slot
    /// collapses to the bare 18pt pin pitch. `slots[i] == true` means a
    /// hanging slip pins there.
    public static func slotOrigins(slots: [Bool], step: CGFloat) -> [CGFloat] {
        slots.indices.map { CGFloat($0) * step }
    }

    /// Full cluster width: the last slot contributes a slip width
    /// (occupied) or one bare pin pitch (empty).
    public static func slotTotalWidth(slots: [Bool], origins: [CGFloat]) -> CGFloat {
        guard let last = slots.indices.last else { return 0 }
        return origins[last] + slipWidth
    }

    // MARK: - Sway

    /// Compound pendulum sway. Big 2-pin pieces: ±1.2°; single-pin slips: ±3.5°.
    /// Night calm: period 6.5s, amplitude ±0.8°.
    public static func swayAngle(time: CGFloat, phase: CGFloat, amplitudeDegrees: CGFloat, period: CGFloat) -> CGFloat {
        amplitudeDegrees * sin(2 * .pi * time / period + phase)
    }

    /// Calm fallback breeze when Atmos is disabled/offline: 6 km/h.
    public static let fallbackBreezeKmh: Double = 6
}

/// Per-rope dynamic sag state driven each frame by `ClotheslineMath.springStep`,
/// plus dwell-gated cluster expansion. Rendering + timers live in the views;
/// this class holds only numbers so the governor/tests can drive it headless.
/// `ClotheslinePhysicsEngine` is touched from the main thread (canvas) and
/// from tests; the lock guards the two sag states.
public final class ClotheslinePhysicsEngine: @unchecked Sendable {
    private let lock = NSLock()
    private var _sagLine1: ClotheslineMath.SpringState
    private var _sagLine2: ClotheslineMath.SpringState
    private var _clusterExpanded = false

    public init(initialSag: CGFloat = ClotheslineMath.baseSag) {
        _sagLine1 = ClotheslineMath.SpringState(position: initialSag)
        _sagLine2 = ClotheslineMath.SpringState(position: initialSag)
    }

    public var sagLine1: CGFloat { lock.withLock { _sagLine1.position } }
    public var sagLine2: CGFloat { lock.withLock { _sagLine2.position } }
    public var clusterExpanded: Bool { lock.withLock { _clusterExpanded } }

    public func setClusterExpanded(_ expanded: Bool) {
        lock.withLock { _clusterExpanded = expanded }
    }

    /// Advance both rope springs one frame toward their equilibria.
    public func tick(dt: CGFloat, equilibrium1: CGFloat, equilibrium2: CGFloat) {
        lock.withLock {
            _sagLine1 = ClotheslineMath.springStep(_sagLine1, equilibrium: equilibrium1, dt: dt)
            _sagLine2 = ClotheslineMath.springStep(_sagLine2, equilibrium: equilibrium2, dt: dt)
        }
    }

    /// Instant settle for Reduce Motion / Pause Breeze: no bounce, no sway.
    public func settleInstantly(equilibrium1: CGFloat, equilibrium2: CGFloat) {
        lock.withLock {
            _sagLine1 = ClotheslineMath.SpringState(position: equilibrium1)
            _sagLine2 = ClotheslineMath.SpringState(position: equilibrium2)
        }
    }
}
