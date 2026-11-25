import Foundation

/// Pure yard geometry for the fixed-gap layout rule and Option A
/// ("slide on the rope") dragging. No AppKit: every rule here is unit-tested.
///
/// Layout rule (design "Varal: peças arrastáveis", 2026-11-23): on every
/// landscape width the slip cluster is centred and big pieces sit a fixed
/// gap `G` from its edges; pieces in one stack are 16pt apart. When the
/// cluster grows the stacks move out by half the growth, clamped 24pt from
/// the screen edge.
public enum YardGeometry: Sendable {
    /// Fixed gap between the cluster's edges and the nearest big piece.
    public static let clusterGap: CGFloat = 32
    /// Gap between two big pieces in the same stack.
    public static let stackSpacing: CGFloat = 16
    /// Minimum distance between a stack's outer edge and the screen edge.
    public static let edgeMargin: CGFloat = 24

    // MARK: - Fixed-gap stacks

    public struct Stacks: Equatable, Sendable {
        /// X origin of the cluster's first slot.
        public var clusterMinX: CGFloat
        /// X origins of the leading pieces, left to right.
        public var leadingXs: [CGFloat]
        /// X origins of the trailing pieces, left to right.
        public var trailingXs: [CGFloat]
    }

    /// Total width of a stack of pieces, including the 16pt spacing.
    public static func stackWidth(_ widths: [CGFloat]) -> CGFloat {
        guard !widths.isEmpty else { return 0 }
        return widths.reduce(0, +) + stackSpacing * CGFloat(widths.count - 1)
    }

    /// Widest the cluster may get before a stack would cross the 24pt edge
    /// margin. Expanded clusters compress their step to fit this.
    public static func availableClusterWidth(
        displayWidth: CGFloat, leadingWidths: [CGFloat], trailingWidths: [CGFloat]
    ) -> CGFloat {
        let lead = stackWidth(leadingWidths)
        let trail = stackWidth(trailingWidths)
        let gaps = (leadingWidths.isEmpty ? 0 : clusterGap) + (trailingWidths.isEmpty ? 0 : clusterGap)
        return max(0, displayWidth - 2 * edgeMargin - lead - trail - gaps)
    }

    /// Centred cluster, stacks a fixed `G` from its edges. If a stack would
    /// cross the 24pt edge margin the whole group shifts away from that edge;
    /// if both sides overflow, both stacks clamp to the margins and the
    /// cluster centres between them.
    public static func landscapeStacks(
        displayWidth W: CGFloat,
        clusterWidth cw: CGFloat,
        leadingWidths: [CGFloat],
        trailingWidths: [CGFloat]
    ) -> Stacks {
        let lead = stackWidth(leadingWidths)
        let trail = stackWidth(trailingWidths)
        let leadGap = leadingWidths.isEmpty ? 0 : clusterGap
        let trailGap = trailingWidths.isEmpty ? 0 : clusterGap
        var cl = W / 2 - cw / 2
        let minCl = edgeMargin + lead + leadGap
        let maxCl = W - edgeMargin - trail - trailGap - cw
        if minCl <= maxCl {
            cl = min(max(cl, minCl), maxCl)
        } else {
            // Both sides overflow: centre the cluster between clamped stacks.
            cl = (minCl + maxCl) / 2
        }
        var leadingXs: [CGFloat] = []
        var leadStart = cl - leadGap - lead
        if minCl > maxCl { leadStart = edgeMargin }
        var x = leadStart
        for w in leadingWidths {
            leadingXs.append(x)
            x += w + stackSpacing
        }
        var trailingXs: [CGFloat] = []
        x = (minCl > maxCl) ? (W - edgeMargin - trail) : (cl + cw + trailGap)
        for w in trailingWidths {
            trailingXs.append(x)
            x += w + stackSpacing
        }
        return Stacks(clusterMinX: cl, leadingXs: leadingXs, trailingXs: trailingXs)
    }

    // MARK: - Rope shape

    /// Y of the drawn rope at `x` (the cubic with controls at W/3 and 2W/3
    /// reduces to y + 4·0.925·sag·t(1−t), t = x/W), plus an optional local
    /// dip that travels with a dragged piece.
    public static func ropeY(
        x: CGFloat, width W: CGFloat, lineY: CGFloat, sag: CGFloat, dip: Dip? = nil
    ) -> CGFloat {
        guard W > 0 else { return lineY }
        let t = min(1, max(0, x / W))
        var y = lineY + 4 * ClotheslineMath.midSpanDeflection(sag: sag) * t * (1 - t)
        if let dip { y += dip.depth(at: x) }
        return y
    }

    /// Weight dip that travels with a piece sliding on the rope. Visual
    /// only: total sag is unchanged by a move.
    public struct Dip: Equatable, Sendable {
        public static let defaultDepth: CGFloat = 4
        public static let defaultSigma: CGFloat = 28
        public var centerX: CGFloat
        public var depth: CGFloat = defaultDepth
        public var sigma: CGFloat = defaultSigma
        public init(centerX: CGFloat, depth: CGFloat = defaultDepth, sigma: CGFloat = defaultSigma) {
            self.centerX = centerX; self.depth = depth; self.sigma = sigma
        }
        public func depth(at x: CGFloat) -> CGFloat {
            let d = x - centerX
            return depth * CGFloat(exp(-Double(d * d) / Double(2 * sigma * sigma)))
        }
    }
}

// MARK: - Piece arrangement (order + side, persisted as `pieceOrder`)

/// Left-to-right order of the big pieces on each side of the cluster.
/// `preferredSide` only seeds it on first run (or for a newly enabled piece).
public struct PieceArrangement: Codable, Equatable, Sendable {
    public var leading: [String]
    public var trailing: [String]

    public init(leading: [String] = [], trailing: [String] = []) {
        self.leading = leading
        self.trailing = trailing
    }

    public var all: [String] { leading + trailing }

    /// Keeps the stored order for pieces that are still active, drops
    /// disabled ones, and appends newly enabled pieces on their preferred
    /// side, in enabled order.
    public static func resolve(
        active: [(id: String, side: PieceAnchorSide)],
        stored: PieceArrangement?
    ) -> PieceArrangement {
        let activeIDs = Set(active.map(\.id))
        var result = PieceArrangement(
            leading: (stored?.leading ?? []).filter { activeIDs.contains($0) },
            trailing: (stored?.trailing ?? []).filter { activeIDs.contains($0) })
        var seen = Set(result.all)
        for piece in active where !seen.contains(piece.id) {
            switch piece.side {
            case .leading: result.leading.append(piece.id)
            case .trailing: result.trailing.append(piece.id)
            }
            seen.insert(piece.id)
        }
        return result
    }

    public enum Slot: Equatable, Sendable {
        case leading(Int)
        case trailing(Int)
    }

    public func slot(of id: String) -> Slot? {
        if let i = leading.firstIndex(of: id) { return .leading(i) }
        if let i = trailing.firstIndex(of: id) { return .trailing(i) }
        return nil
    }

    public func removing(_ id: String) -> PieceArrangement {
        PieceArrangement(leading: leading.filter { $0 != id }, trailing: trailing.filter { $0 != id })
    }

    /// `id` moved to `slot` (indices are into the arrangement without `id`).
    public func moving(_ id: String, to slot: Slot) -> PieceArrangement {
        var next = removing(id)
        switch slot {
        case .leading(let i): next.leading.insert(id, at: min(max(0, i), next.leading.count))
        case .trailing(let i): next.trailing.insert(id, at: min(max(0, i), next.trailing.count))
        }
        return next
    }
}

// MARK: - Option A drag rules

public enum LineDrag: Sendable {
    /// Movement before intent is read (also the big-piece slide threshold).
    public static let intentThreshold: CGFloat = 6
    public static let liftHeight: CGFloat = 4
    public static let pinLoosenDegrees: CGFloat = 10
    public static let restShadowOpacity: Float = 0.10
    public static let liftShadowOpacity: Float = 0.26
    /// Fraction of the pointer's travel followed past the legal span.
    public static let rubberBand: CGFloat = 0.3
    public static let pinClampDuration: TimeInterval = 0.12
    public static let crossFadeDuration: TimeInterval = 0.2
    /// Slips dim to this while a lifted piece is over the cluster.
    public static let dimmedSlipAlpha: CGFloat = 0.5
    /// Yield / return spring: ζ 0.8, settles in ~180ms, no visible overshoot.
    public static let yieldOmega: CGFloat = 28
    public static let yieldZeta: CGFloat = 0.8

    public enum Intent: Equatable, Sendable {
        /// Under 6pt of travel: nothing moves yet.
        case undecided
        /// |dx| ≥ 2·|dy|: slide along the rope.
        case slide
        /// Downward-dominant: the existing tear phases, untouched.
        case tear
        /// Upward-dominant: inert (no slide, no tear).
        case none
    }

    /// Reads a slip drag's intent from its first 6pt. `dy` is positive
    /// downward. A misread can never complete a task: `.slide` and `.none`
    /// never reach the tear path, and `.tear` still needs > 48pt.
    public static func classifySlipIntent(dx: CGFloat, dy: CGFloat) -> Intent {
        guard (dx * dx + dy * dy).squareRoot() >= intentThreshold else { return .undecided }
        if abs(dx) >= 2 * abs(dy) { return .slide }
        return dy > 0 ? .tear : .none
    }

    /// Big pieces have no tear: any 6pt drag starts a slide.
    public static func pieceSlideStarts(dx: CGFloat, dy: CGFloat) -> Bool {
        (dx * dx + dy * dy).squareRoot() >= intentThreshold
    }

    /// Menu mirror slides pieces in any direction, while slips require a
    /// horizontal first movement.
    public static func menuSlideStarts(isPiece: Bool, dx: CGFloat, dy: CGFloat) -> Bool {
        if isPiece { return pieceSlideStarts(dx: dx, dy: dy) }
        return classifySlipIntent(dx: dx, dy: dy) == .slide
    }

    /// Past `[minX, maxX]` the position follows at 30%.
    public static func rubberBanded(_ x: CGFloat, minX: CGFloat, maxX: CGFloat) -> (x: CGFloat, blocked: Bool) {
        if x < minX { return (minX + (x - minX) * rubberBand, true) }
        if x > maxX { return (maxX + (x - maxX) * rubberBand, true) }
        return (x, false)
    }

    // MARK: Big pieces

    /// Target slot for a piece whose centre is at `centerX`. Crossing the
    /// divider (the cluster's centre; the display centre on portrait Line 1)
    /// switches side; within a side the index is the number of remaining
    /// pieces whose resting centre lies left of `centerX`.
    public static func pieceTarget(
        centerX: CGFloat,
        dividerX: CGFloat,
        remainingLeadingCenters: [CGFloat],
        remainingTrailingCenters: [CGFloat]
    ) -> PieceArrangement.Slot {
        if centerX < dividerX {
            return .leading(remainingLeadingCenters.filter { $0 < centerX }.count)
        }
        return .trailing(remainingTrailingCenters.filter { $0 < centerX }.count)
    }

    /// A slot is blocked when the resulting stacks cannot keep the gap rule
    /// inside the 24pt edge margins with the cluster at its current width.
    public static func pieceArrangementFits(
        displayWidth: CGFloat, clusterWidth: CGFloat,
        leadingWidths: [CGFloat], trailingWidths: [CGFloat]
    ) -> Bool {
        clusterWidth <= YardGeometry.availableClusterWidth(
            displayWidth: displayWidth, leadingWidths: leadingWidths, trailingWidths: trailingWidths) + 0.5
    }

    // MARK: Slips

    /// Index into the occupied-slot order nearest to `x` (slot origins are
    /// the occupied slots' x origins, left to right).
    public static func slipTargetPosition(x: CGFloat, occupiedOrigins: [CGFloat]) -> Int {
        guard !occupiedOrigins.isEmpty else { return 0 }
        var best = 0
        var bestD = CGFloat.infinity
        for (i, o) in occupiedOrigins.enumerated() where abs(o - x) < bestD {
            bestD = abs(o - x); best = i
        }
        return best
    }

    /// Reorders `id` within the occupied slots only. Returns the new slot
    /// index for every hanging slip; empty pins keep their slots, so the
    /// neighbours step one occupied slot toward the vacated one.
    public static func reorderedSlots(
        occupied: [(id: UUID, slot: Int)], moving id: UUID, toPosition position: Int
    ) -> [UUID: Int] {
        let sorted = occupied.sorted { $0.slot < $1.slot }
        let slots = sorted.map(\.slot)
        var order = sorted.map(\.id)
        guard let from = order.firstIndex(of: id) else {
            return Dictionary(uniqueKeysWithValues: sorted.map { ($0.id, $0.slot) })
        }
        order.remove(at: from)
        order.insert(id, at: min(max(0, position), order.count))
        var result: [UUID: Int] = [:]
        for (i, slipID) in order.enumerated() { result[slipID] = slots[i] }
        return result
    }
}
