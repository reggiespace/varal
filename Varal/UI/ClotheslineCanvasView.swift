import AppKit

/// One computed frame of the yard geometry: piece frames, per-slot slip
/// frames, and clothespin rects. Pure value; the canvas applies it to views
/// and uses it for rope/pin drawing and hit-testing.
public struct YardLayout: Sendable {
    public struct PieceFrame: Sendable {
        public let id: String
        public let frame: CGRect
    }
    public struct SlipFrame: Sendable {
        public let id: UUID
        public let slot: Int
        public let frame: CGRect
    }
    /// A clothespin to draw: its rect and its loosen angle in degrees.
    public struct PinMark: Sendable {
        public let rect: CGRect
        public let angle: CGFloat
        /// Item the pin belongs to (nil for bare pins).
        public var key: String? = nil
    }
    public var pieceFrames: [PieceFrame] = []
    public var slipFrames: [SlipFrame] = []
    /// 18pt bare-pin rects for slots with no hanging slip (torn/undo).
    public var emptyPinRects: [CGRect] = []
    /// Pin rects for occupied slots (drawn over the slip top).
    public var occupiedPinRects: [CGRect] = []
    /// Every pin to draw (slips, empty slots, and the two per big piece).
    public var pins: [PinMark] = []
    public var clusterRect: CGRect = .zero
    /// X origins of the occupied slip slots, left to right.
    public var occupiedSlotXs: [CGFloat] = []
    public var line1Y: CGFloat = 0
    public var line2Y: CGFloat = 0
    public var sag1: CGFloat = 0
    public var sag2: CGFloat = 0
    /// The arrangement the frames were laid out from (live preview while a
    /// piece is being dragged).
    public var arrangement = PieceArrangement()
    /// X that decides a dragged piece's side (cluster centre in landscape,
    /// display centre on portrait Line 1).
    public var pieceDividerX: CGFloat = 0
    /// Weight dip travelling with a dragged piece (nil at rest).
    public var dip: YardGeometry.Dip?
    /// Line the dip sits on (1 or 2).
    public var dipLine = 1
}

/// Clothesline stage on the selected display. Top-left (flipped) coordinate
/// space; ropes, pins, pieces, slips, and the basket are laid out here.
///
/// Landscape (`width >= height`): one rope — leading big pieces, a fixed
/// gap, the centred task cluster, a fixed gap, trailing big pieces.
/// Portrait (`height > width`): two stacked ropes — Line 1 big pieces,
/// Line 2 task slips.
///
/// Dragging is Option A, "slide on the rope": a big piece (any 6pt drag) or
/// a slip (sideways intent) slides along its own rope, neighbours yield, and
/// the pins clamp on release.
@MainActor
public final class ClotheslineCanvasView: NSView {
    private let slipStore: TaskSlipStore
    private let planStore: HolidayPlanStore
    private let piecesProvider: () -> [any CompanionPiece]
    private let environmentProvider: () -> EnvironmentSnapshot?
    public let pieceOrder: PieceOrderStore
    let engine = ClotheslinePhysicsEngine()

    private var displayLink: Timer?
    private var startTime = Date().timeIntervalSinceReferenceDate
    private var dwellTimer: Timer?
    private var collapseTimer: Timer?
    private var clusterTrackingArea: NSTrackingArea?
    private var slipViews: [UUID: TaskSlipView] = [:]
    private var pieceViews: [String: NSView] = [:]
    var basketView = LaundryBasketView()
    private var pulls: [UUID: CGFloat] = [:]
    private var flutterTimers: [UUID: Timer] = [:]

    // MARK: Drag state (Option A)

    /// One pointer session sliding a piece or a slip along its rope.
    struct DragSession {
        enum Kind: Equatable {
            case piece(String)
            case slip(UUID)
        }
        var kind: Kind
        var startWindowX: CGFloat
        var dx: CGFloat = 0
        /// Frame at rest when the session began.
        var homeFrame: CGRect
        var pieceTarget: PieceArrangement.Slot?
        var slipPosition: Int?
        var blocked = false
        var lastWindowX: CGFloat
        var lastTime: TimeInterval
        var velocityX: CGFloat = 0
    }

    /// Release settle for one item: pins clamp (120ms), then the 4pt lift
    /// drops on the pin-on spring, plus a sway impulse from release velocity.
    struct Settle {
        var start: TimeInterval
        var lift = ClotheslineMath.SpringState(position: LineDrag.liftHeight)
        var rotation = ClotheslineMath.SpringState(position: 0)
        var pinAngle: CGFloat = LineDrag.pinLoosenDegrees
    }

    private struct PendingPiecePress {
        let id: String
        let down: NSEvent
        let start: NSPoint
    }

    private(set) var session: DragSession?
    private var settles: [String: Settle] = [:]
    /// Displayed x springs for items yielding or settling (keyed by item key).
    private var xSprings: [String: ClotheslineMath.SpringState] = [:]
    private var xTargets: [String: CGFloat] = [:]
    private var pendingPiece: PendingPiecePress?
    private var replayPassThrough = 0
    private var pieceMouseMonitor: Any?
    private var keyMonitor: Any?
    private var globalUpMonitor: Any?
    private var activatedForDrag = false

    /// Governor-controlled render state (set by the app).
    public var rendersAtFullRate = true {
        didSet { rendersAtFullRate ? startLoop() : stopLoop() }
    }
    public var isMotionAllowed = true

    public var onHitRectsChanged: (@MainActor ([CGRect]) -> Void)?
    /// Fired after a drag commits a new order (menu-bar mirror refresh).
    public var onLineRearranged: (@MainActor () -> Void)?

    public var isDragSessionActive: Bool { session != nil }

    /// Expands or collapses the slip cluster (the 150ms hover dwell calls
    /// this path; also a test seam).
    public func setClusterExpanded(_ expanded: Bool) {
        engine.setClusterExpanded(expanded)
        refresh()
    }

    public init(
        slipStore: TaskSlipStore,
        planStore: HolidayPlanStore,
        pieceOrder: PieceOrderStore = PieceOrderStore(),
        pieces: @escaping () -> [any CompanionPiece],
        environment: @escaping () -> EnvironmentSnapshot?
    ) {
        self.slipStore = slipStore
        self.planStore = planStore
        self.pieceOrder = pieceOrder
        self.piecesProvider = pieces
        self.environmentProvider = environment
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(basketView)
        basketView.onEmptyBasket = { [weak self] in
            self?.slipStore.deleteBasketSlips()
            self?.refresh()
        }
        basketView.onUndoTop = { [weak self] in self?.undoTopSlip() }
        NotificationCenter.default.addObserver(
            self, selector: #selector(pieceOrderChanged(_:)),
            name: PieceOrderStore.didChange, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    public override var isFlipped: Bool { true }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { installDragMonitors() } else { removeDragMonitors() }
    }

    @objc private func pieceOrderChanged(_ note: Notification) {
        guard session == nil else { return }
        refresh()
    }

    // MARK: - Geometry

    public var layoutMode: ClotheslineMath.LayoutMode {
        ClotheslineMath.layoutMode(size: bounds.size)
    }

    public var topSafeInset: CGFloat {
        guard let screen = window?.screen else { return 0 }
        return screen.frame.maxY - screen.visibleFrame.maxY
    }

    public var line1Y: CGFloat { ClotheslineMath.lineY(topSafeInset: topSafeInset) }
    public var line2Y: CGFloat { ClotheslineMath.secondLineY(firstLineY: line1Y) }

    private var currentEnvironment: EnvironmentSnapshot? { environmentProvider() }

    /// AppKit layout always runs on the main thread; the card view itself is
    /// `@MainActor`-isolated per the `CompanionPiece` contract.
    private func mainView(of piece: any CompanionPiece) -> NSView {
        piece.pieceView
    }

    private func equilibrium(forLine line: Int, mode: ClotheslineMath.LayoutMode) -> CGFloat {
        let pieces = piecesProvider()
        let hanging = slipStore.hangingSlips.count
        let precip = currentEnvironment?.precipitation ?? .clear
        switch mode {
        case .landscape:
            return ClotheslineMath.equilibriumSag(
                bigPieceMassUnits: pieces.map(\.sizeMetrics.massUnits),
                hangingSlipCount: hanging, precipitation: precip)
        case .portrait:
            if line == 1 {
                return ClotheslineMath.equilibriumSag(
                    bigPieceMassUnits: pieces.map(\.sizeMetrics.massUnits),
                    hangingSlipCount: 0, precipitation: precip)
            } else {
                return ClotheslineMath.equilibriumSag(
                    bigPieceMassUnits: [],
                    hangingSlipCount: hanging, precipitation: precip)
            }
        }
    }

    /// The persisted arrangement resolved against the enabled pieces.
    public var arrangement: PieceArrangement {
        pieceOrder.resolve(active: piecesProvider().map { (id: $0.pieceID, side: $0.preferredSide) })
    }

    private static func key(piece id: String) -> String { "piece:\(id)" }
    private static func key(slip id: UUID) -> String { "slip:\(id.uuidString)" }

    private var draggedKey: String? {
        switch session?.kind {
        case .piece(let id)?: return Self.key(piece: id)
        case .slip(let id)?: return Self.key(slip: id)
        case nil: return nil
        }
    }

    private var motionActive: Bool { isMotionAllowed && rendersAtFullRate }

    // MARK: - Unified layout (single source of truth)

    /// Computes every frame from current bounds, stores, engine sag, and the
    /// live drag session. Slot-stable: slips are positioned by
    /// `pinSlotIndex`, so tearing one slip leaves its neighbors exactly where
    /// they were. Big pieces follow the fixed-gap rule on every landscape
    /// width and hang from the rope at their centre.
    public func computeLayout() -> YardLayout {
        let mode = layoutMode
        let pieces = piecesProvider()
        var byID: [String: any CompanionPiece] = [:]
        for p in pieces where byID[p.pieceID] == nil { byID[p.pieceID] = p }
        let W = bounds.width
        let sag1 = engine.sagLine1
        let sag2 = engine.sagLine2
        let expanded = engine.clusterExpanded
        let ultrawide = ClotheslineMath.isUltrawide(size: bounds.size)
        let lift = motionActive ? LineDrag.liftHeight : 0
        var layout = YardLayout(
            line1Y: line1Y, line2Y: line2Y, sag1: sag1, sag2: sag2)

        // Live preview of the dragged piece's target (blocked: no change).
        let base = arrangement
        var arr = base
        if let s = session, case .piece(let id) = s.kind, let target = s.pieceTarget, !s.blocked {
            arr = base.moving(id, to: target)
        }
        layout.arrangement = arr

        // Slots: occupancy is fixed by pinSlotIndex; a slip slide previews a
        // permutation of the occupied slots only.
        let hanging = slipStore.hangingSlips.sorted { $0.pinSlotIndex < $1.pinSlotIndex }
        let inBasketSlots = Set(slipStore.basketSlips.map(\.pinSlotIndex))
        let maxSlot = (hanging.map(\.pinSlotIndex) + inBasketSlots).max() ?? -1
        var slotOf: [UUID: Int] = Dictionary(uniqueKeysWithValues: hanging.map { ($0.id, $0.pinSlotIndex) })
        if let s = session, case .slip(let id) = s.kind, let pos = s.slipPosition, !s.blocked {
            slotOf = LineDrag.reorderedSlots(
                occupied: hanging.map { (id: $0.id, slot: $0.pinSlotIndex) }, moving: id, toPosition: pos)
        }
        var slots: [Bool] = []
        if maxSlot >= 0 {
            let occupied = Set(hanging.map(\.pinSlotIndex))
            slots = (0...maxSlot).map { occupied.contains($0) }
        }
        let slipLineY = (mode == .portrait) ? line2Y : line1Y
        let slipSag = (mode == .portrait) ? sag2 : sag1

        let leadW = arr.leading.compactMap { byID[$0]?.sizeMetrics.width }
        let trailW = arr.trailing.compactMap { byID[$0]?.sizeMetrics.width }

        let step: CGFloat
        if mode == .portrait {
            step = ClotheslineMath.clusterStep(
                slipCount: slots.count, expanded: expanded,
                availableWidth: max(200, W - 48), portraitLine2: true)
        } else {
            let available = max(200, YardGeometry.availableClusterWidth(
                displayWidth: W, leadingWidths: leadW, trailingWidths: trailW))
            step = ultrawide
                ? ClotheslineMath.ultrawideClusterStep(
                    slipCount: slots.count, expanded: expanded, availableWidth: available)
                : ClotheslineMath.clusterStep(
                    slipCount: slots.count, expanded: expanded,
                    availableWidth: available, portraitLine2: false)
        }
        let origins = ClotheslineMath.slotOrigins(slots: slots, step: step)
        let totalW = ClotheslineMath.slotTotalWidth(slots: slots, origins: origins)

        // Piece x origins.
        var pieceXs: [String: CGFloat] = [:]
        let x0: CGFloat
        if mode == .landscape {
            let stacks = YardGeometry.landscapeStacks(
                displayWidth: W, clusterWidth: totalW,
                leadingWidths: leadW, trailingWidths: trailW)
            x0 = stacks.clusterMinX
            for (i, id) in arr.leading.filter({ byID[$0] != nil }).enumerated() { pieceXs[id] = stacks.leadingXs[i] }
            for (i, id) in arr.trailing.filter({ byID[$0] != nil }).enumerated() { pieceXs[id] = stacks.trailingXs[i] }
            layout.pieceDividerX = totalW > 0 ? x0 + totalW / 2 : W / 2
        } else {
            // Portrait Line 1: legacy edge anchors, in arrangement order.
            var x = YardGeometry.edgeMargin
            for id in arr.leading {
                guard let p = byID[id] else { continue }
                pieceXs[id] = x
                x += p.sizeMetrics.width + YardGeometry.stackSpacing
            }
            x = W - YardGeometry.edgeMargin
            for id in arr.trailing.reversed() {
                guard let p = byID[id] else { continue }
                x -= p.sizeMetrics.width
                pieceXs[id] = x
                x -= YardGeometry.stackSpacing
            }
            x0 = (W - totalW) / 2
            layout.pieceDividerX = W / 2
        }

        // Dragged piece/slip: pointer-driven x, weight dip under it.
        var draggedPieceFrame: CGRect?
        if let s = session, case .piece(let id) = s.kind, let p = byID[id] {
            let w = p.sizeMetrics.width
            let x = s.homeFrame.minX + s.dx
            if motionActive { layout.dip = YardGeometry.Dip(centerX: x + w / 2) }
            layout.dipLine = 1
            let ropeY = YardGeometry.ropeY(x: x + w / 2, width: W, lineY: line1Y, sag: sag1, dip: layout.dip)
            draggedPieceFrame = CGRect(x: x, y: ropeY - lift, width: w, height: p.sizeMetrics.height)
        }

        let settleLift: (String) -> CGFloat = { [settles] key in settles[key]?.lift.position ?? 0 }
        let pinAngle: (String) -> CGFloat = { [settles, session, motionActive] key in
            if let s = session, motionActive {
                switch s.kind {
                case .piece(let id) where key == Self.key(piece: id): return LineDrag.pinLoosenDegrees
                case .slip(let id) where key == Self.key(slip: id): return LineDrag.pinLoosenDegrees
                default: break
                }
            }
            return settles[key]?.pinAngle ?? 0
        }

        for id in arr.all {
            guard let p = byID[id] else { continue }
            let key = Self.key(piece: id)
            let frame: CGRect
            if let dragged = draggedPieceFrame, session?.kind == .piece(id) {
                frame = dragged
            } else {
                guard let x = pieceXs[id] else { continue }
                let w = p.sizeMetrics.width
                let ropeY = YardGeometry.ropeY(x: x + w / 2, width: W, lineY: line1Y, sag: sag1, dip: layout.dipLine == 1 ? layout.dip : nil)
                frame = CGRect(x: x, y: ropeY - settleLift(key), width: w, height: p.sizeMetrics.height)
            }
            layout.pieceFrames.append(.init(id: id, frame: frame))
            // Two clothespins per big piece, straddling the rope.
            let angle = pinAngle(key)
            for (i, fx) in [frame.minX + frame.width * 0.18, frame.minX + frame.width * 0.82].enumerated() {
                let ropeY = YardGeometry.ropeY(x: fx, width: W, lineY: line1Y, sag: sag1, dip: layout.dipLine == 1 ? layout.dip : nil)
                layout.pins.append(.init(
                    rect: CGRect(x: fx - 7, y: ropeY - 14, width: 14, height: 26),
                    angle: i == 0 ? -angle : angle, key: key))
            }
        }

        // Slot-stable slip positions + pin rects.
        if !slots.isEmpty {
            let bySlot = Dictionary(uniqueKeysWithValues: hanging.map { (slotOf[$0.id] ?? $0.pinSlotIndex, $0) })
            let slipRopeY = slipLineY + slipSag * 0.925
            for slot in slots.indices {
                let x = x0 + origins[slot]
                if let slip = bySlot[slot] {
                    layout.occupiedSlotXs.append(x)
                    let key = Self.key(slip: slip.id)
                    let pull = pulls[slip.id] ?? 0
                    let ropeDip = pull <= 18 ? 0.45 * pull : 0.45 * 18
                    var frame = CGRect(
                        x: x, y: slipRopeY + ropeDip - settleLift(key),
                        width: ClotheslineMath.slipWidth, height: ClotheslineMath.slipHeight)
                    if let s = session, case .slip(let id) = s.kind, id == slip.id {
                        // Legal span: the occupied slots of the cluster.
                        let occupiedXs = slots.indices.filter { slots[$0] }.map { x0 + origins[$0] }
                        let banded = LineDrag.rubberBanded(
                            s.homeFrame.minX + s.dx,
                            minX: occupiedXs.first ?? x, maxX: occupiedXs.last ?? x)
                        frame.origin.x = banded.x
                        frame.origin.y = slipRopeY - lift
                        if motionActive {
                            layout.dip = YardGeometry.Dip(centerX: frame.midX)
                            layout.dipLine = mode == .portrait ? 2 : 1
                        }
                    }
                    layout.slipFrames.append(.init(id: slip.id, slot: slot, frame: frame))
                    let pin = pinRect(slotX: frame.minX, slotWidth: ClotheslineMath.slipWidth, ropeY: slipRopeY)
                    layout.occupiedPinRects.append(pin)
                    layout.pins.append(.init(rect: pin, angle: pinAngle(key), key: key))
                } else {
                    // Bare pin stays centered where the torn slip's pin was.
                    let pin = pinRect(slotX: x, slotWidth: ClotheslineMath.slipWidth, ropeY: slipRopeY)
                    layout.emptyPinRects.append(pin)
                    layout.pins.append(.init(rect: pin, angle: 0))
                }
            }
            layout.clusterRect = CGRect(
                x: x0 - 8, y: slipLineY - 24,
                width: totalW + 16, height: 200)
        }
        return layout
    }

    /// Wooden clothespin straddling the rope above a slip (or bare slot).
    private func pinRect(slotX: CGFloat, slotWidth: CGFloat, ropeY: CGFloat) -> CGRect {
        let w: CGFloat = 14
        return CGRect(x: slotX + (slotWidth - w) / 2, y: ropeY - 14, width: w, height: 26)
    }

    // MARK: - Refresh / layout application

    /// Rebuilds piece + slip subviews and positions after any store change.
    public func refresh() {
        let layout = computeLayout()
        updateClusterTrackingArea(layout.clusterRect)
        let pieces = piecesProvider()

        // Mount big-piece views (generic: no Atmos/GLW naming here);
        // unmount views for pieces no longer enabled.
        let activeIDs = Set(pieces.map(\.pieceID))
        for id in pieceViews.keys where !activeIDs.contains(id) {
            pieceViews[id]?.removeFromSuperview()
            pieceViews.removeValue(forKey: id)
        }
        for piece in pieces {
            let v = mainView(of: piece)
            if pieceViews[piece.pieceID] == nil {
                pieceViews[piece.pieceID] = v
                if v.superview !== self { addSubview(v) }
                Self.applyShadow(to: v, lifted: false)
            }
        }

        // Prune slip views for torn-off/deleted slips; add new ones.
        let hangingIDs = Set(slipStore.hangingSlips.map(\.id))
        for id in slipViews.keys where !hangingIDs.contains(id) && flutterTimers[id] == nil {
            slipViews[id]?.removeFromSuperview()
            slipViews.removeValue(forKey: id)
        }
        for slip in slipStore.hangingSlips where slipViews[slip.id] == nil {
            let v = TaskSlipView(slip: slip)
            v.onPullChanged = { [weak self] id, pull in
                self?.pulls[id] = pull
                // Release (pull back to 0) re-seats the slip on its pin.
                if pull == 0 { self?.refresh() }
            }
            v.onTearOff = { [weak self] id in self?.completeTearOff(id: id) }
            v.onSlideBegan = { [weak self] id, x, t in self?.beginSlipSlide(id: id, windowX: x, time: t) }
            v.onSlideMoved = { [weak self] _, x, t in self?.updateSlide(windowX: x, time: t) }
            v.onSlideEnded = { [weak self] _, p in self?.endSlide(windowPoint: p) }
            slipViews[slip.id] = v
            addSubview(v)
            Self.applyShadow(to: v, lifted: false)
        }

        applyLayout(layout)

        // Basket anchored bottom-right (full vertical drop for flutter).
        let bw = LaundryBasketView.basketSize.width
        let bh = LaundryBasketView.basketSize.height
        basketView.frame = NSRect(x: bounds.width - bw - 32, y: bounds.height - bh - 64 - 20, width: bw, height: bh)
        basketView.basketCount = slipStore.basketSlips.count
        basketView.hangingCount = slipStore.hangingSlips.count
        basketView.updateLabels()

        publishHitRects(layout: layout)
        needsDisplay = true
    }

    private func updateClusterTrackingArea(_ rect: CGRect) {
        if clusterTrackingArea?.rect == rect { return }
        if let clusterTrackingArea {
            removeTrackingArea(clusterTrackingArea)
            self.clusterTrackingArea = nil
        }
        guard !rect.isNull, !rect.isEmpty else { return }
        let area = NSTrackingArea(
            rect: rect,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        clusterTrackingArea = area
    }

    /// Applies precomputed frames to subviews. A slip mid-tear keeps its
    /// pointer-driven position; items yielding or settling ride their x
    /// springs; everything else follows the layout.
    private func applyLayout(_ layout: YardLayout) {
        for frame in layout.pieceFrames {
            guard let v = pieceViews[frame.id] else { continue }
            place(v, key: Self.key(piece: frame.id), to: frame.frame.origin)
        }
        for slipFrame in layout.slipFrames {
            guard let v = slipViews[slipFrame.id],
                  flutterTimers[slipFrame.id] == nil,
                  !v.isTearing else { continue }
            place(v, key: Self.key(slip: slipFrame.id), to: slipFrame.frame.origin)
        }
        applyDragStyling(layout)
    }

    private func place(_ view: NSView, key: String, to target: NSPoint) {
        if key == draggedKey {
            view.setFrameOrigin(target)
            return
        }
        let animating = session != nil || xSprings[key] != nil
        guard animating, abs(view.frame.minX - target.x) > 0.5 || xSprings[key] != nil else {
            view.setFrameOrigin(target)
            return
        }
        if motionActive {
            // Neighbours yield on the ζ 0.8 spring (no overshoot).
            if xSprings[key] == nil { xSprings[key] = .init(position: view.frame.minX) }
            xTargets[key] = target.x
            view.setFrameOrigin(NSPoint(x: xSprings[key]!.position, y: target.y))
        } else {
            // Reduce Motion / Pause Breeze: cross-fade to the new slot.
            xSprings.removeValue(forKey: key)
            if abs(view.frame.minX - target.x) > 0.5 { Self.crossFade(view) }
            view.setFrameOrigin(target)
        }
    }

    private static func crossFade(_ view: NSView) {
        view.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = LineDrag.crossFadeDuration
            view.animator().alphaValue = 1
        }
    }

    private static func applyShadow(to view: NSView, lifted: Bool) {
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        layer.masksToBounds = false
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = lifted ? LineDrag.liftShadowOpacity : LineDrag.restShadowOpacity
        layer.shadowRadius = lifted ? 8 : 2
        layer.shadowOffset = CGSize(width: 0, height: lifted ? -10 : -1)
    }

    /// Orange outline when blocked; slips dim while a lifted piece is over
    /// the cluster.
    private func applyDragStyling(_ layout: YardLayout) {
        var overCluster = false
        if let s = session, case .piece(let id) = s.kind,
           let f = layout.pieceFrames.first(where: { $0.id == id })?.frame {
            overCluster = f.intersects(layout.clusterRect)
            if let v = pieceViews[id] { Self.setBlockedOutline(v, s.blocked) }
        }
        if let s = session, case .slip(let id) = s.kind, let v = slipViews[id] {
            Self.setBlockedOutline(v, s.blocked)
        }
        let wanted: CGFloat = overCluster ? LineDrag.dimmedSlipAlpha : 1
        for (id, v) in slipViews where flutterTimers[id] == nil && abs(v.alphaValue - wanted) > 0.01 {
            v.alphaValue = wanted
        }
    }

    private static func setBlockedOutline(_ view: NSView, _ blocked: Bool) {
        view.wantsLayer = true
        if view is TaskSlipView { view.layer?.cornerRadius = 3 }
        view.layer?.borderWidth = blocked ? 2 : 0
        view.layer?.borderColor = NSColor(calibratedRed: 0xC2 / 255.0, green: 0x41 / 255.0, blue: 0x0C / 255.0, alpha: 1).cgColor
    }

    private func publishHitRects(layout: YardLayout) {
        var rects: [CGRect] = layout.pieceFrames.map(\.frame)
        if !layout.clusterRect.isNull, layout.clusterRect.width > 0 {
            rects.append(layout.clusterRect)
        }
        rects.append(basketView.frame.insetBy(dx: -16, dy: -24))
        onHitRectsChanged?(rects)
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        refresh()
    }

    // MARK: - Rope + pin drawing

    public override func draw(_ dirtyRect: NSRect) {
        // Extra local dip while a slip is mid-tear (prototype behavior:
        // rope follows 0.45 * pull, capped at +28pt).
        let maxPull = pulls.values.max() ?? 0
        let extraDip = min(28, 0.45 * maxPull)
        NSColor(calibratedWhite: 0.6, alpha: 1).setStroke()
        let W = bounds.width
        let layout = computeLayout()
        func rope(atY y: CGFloat, sag: CGFloat, dip: YardGeometry.Dip?) {
            let path = NSBezierPath()
            if let dip {
                // Sampled rope so the weight dip travels with the piece.
                var x: CGFloat = 0
                path.move(to: NSPoint(x: 0, y: y))
                while x < W {
                    x = min(W, x + 4)
                    path.line(to: NSPoint(x: x, y: YardGeometry.ropeY(
                        x: x, width: W, lineY: y, sag: sag + extraDip, dip: dip)))
                }
            } else {
                let a = ClotheslineMath.ropeCubicControlYOffset(sag: sag + extraDip)
                path.move(to: NSPoint(x: 0, y: y))
                path.curve(to: NSPoint(x: W, y: y),
                           controlPoint1: NSPoint(x: W / 3, y: y + a),
                           controlPoint2: NSPoint(x: 2 * W / 3, y: y + a))
            }
            path.lineWidth = 1.5
            path.stroke()
        }
        rope(atY: layout.line1Y, sag: layout.sag1, dip: layout.dipLine == 1 ? layout.dip : nil)
        if layoutMode == .portrait {
            rope(atY: layout.line2Y, sag: layout.sag2, dip: layout.dipLine == 2 ? layout.dip : nil)
        }
        // A faint outline marks home while dragging.
        if let s = session {
            let outline = NSBezierPath(roundedRect: s.homeFrame, xRadius: 4, yRadius: 4)
            outline.setLineDash([5, 4], count: 2, phase: 0)
            outline.lineWidth = 1.5
            NSColor(calibratedWhite: 0.55, alpha: 0.7).setStroke()
            outline.stroke()
        }
        // Clothespins: every big piece, every occupied slip top, and bare
        // pins at empty slots where torn slips used to hang.
        // Pins ride with their view while it yields or settles on a spring.
        var shift: [String: CGFloat] = [:]
        for f in layout.pieceFrames {
            if let v = pieceViews[f.id] { shift[Self.key(piece: f.id)] = v.frame.minX - f.frame.minX }
        }
        for f in layout.slipFrames {
            if let v = slipViews[f.id], !v.isTearing { shift[Self.key(slip: f.id)] = v.frame.minX - f.frame.minX }
        }
        for pin in layout.pins {
            let dx = pin.key.flatMap { shift[$0] } ?? 0
            drawPin(pin.rect.offsetBy(dx: dx, dy: 0), angle: pin.angle)
        }
    }

    private func drawPin(_ rect: CGRect, angle: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        if angle != 0 {
            let t = NSAffineTransform()
            t.translateX(by: rect.midX, yBy: rect.midY)
            t.rotate(byDegrees: angle)
            t.translateX(by: -rect.midX, yBy: -rect.midY)
            t.concat()
        }
        let pin = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
        NSColor(calibratedWhite: 0.72, alpha: 1).setFill()
        pin.fill()
        NSColor(calibratedWhite: 0.5, alpha: 1).setStroke()
        pin.lineWidth = 1
        pin.stroke()
        // Wire groove across the middle.
        let groove = NSBezierPath()
        groove.move(to: NSPoint(x: rect.minX + 2, y: rect.midY))
        groove.line(to: NSPoint(x: rect.maxX - 2, y: rect.midY))
        NSColor(calibratedWhite: 0.45, alpha: 1).setStroke()
        groove.lineWidth = 1
        groove.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: - Dwell-gated cluster (150ms in, 250ms out)

    public override func mouseEntered(with event: NSEvent) {
        collapseTimer?.invalidate()
        collapseTimer = nil
        // A big piece crossing the cluster must not expand it mid-drag.
        if let s = session, case .piece = s.kind { return }
        guard dwellTimer == nil, !engine.clusterExpanded else { return }
        dwellTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.dwellTimer = nil
                self?.engine.setClusterExpanded(true)
                self?.refresh()
            }
        }
    }

    public override func mouseExited(with event: NSEvent) {
        dwellTimer?.invalidate()
        dwellTimer = nil
        // A slip sliding past the cluster edge keeps the cluster expanded.
        guard session == nil else { return }
        scheduleCollapse()
    }

    private func scheduleCollapse() {
        guard engine.clusterExpanded, collapseTimer == nil else { return }
        collapseTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.collapseTimer = nil
                self?.engine.setClusterExpanded(false)
                self?.refresh()
            }
        }
    }

    // MARK: - Slide on the rope (Option A)

    private func installDragMonitors() {
        guard pieceMouseMonitor == nil else { return }
        // Big pieces host their own content (a web view, buttons), so the
        // canvas reads their drags here: a press is held back until it either
        // moves 6pt (slide) or is released (replayed as a normal click).
        // Local monitors fire on the main thread.
        pieceMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            nonisolated(unsafe) let ev = event
            let consumed = MainActor.assumeIsolated { self?.consumePieceMouse(ev) ?? false }
            return consumed ? nil : ev
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            nonisolated(unsafe) let ev = event
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard let self, ev.keyCode == 53, self.session != nil else { return false }
                self.cancelSlide()
                return true
            }
            return consumed ? nil : ev
        }
        // A mouse-up delivered to another app means the pointer session was
        // lost: slide the piece home.
        globalUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.session != nil else { return }
                self.cancelSlide()
            }
        }
    }

    private func removeDragMonitors() {
        for m in [pieceMouseMonitor, keyMonitor, globalUpMonitor] {
            if let m { NSEvent.removeMonitor(m) }
        }
        pieceMouseMonitor = nil
        keyMonitor = nil
        globalUpMonitor = nil
    }

    private func pieceID(atWindowPoint p: NSPoint) -> String? {
        let local = convert(p, from: nil)
        // Slips and the basket handle their own gestures.
        if slipViews.values.contains(where: { $0.frame.contains(local) }) { return nil }
        if basketView.frame.contains(local) { return nil }
        return pieceViews.first { $0.value.frame.contains(local) }?.key
    }

    /// Returns true when the canvas consumed the event.
    private func consumePieceMouse(_ event: NSEvent) -> Bool {
        guard event.window === window, window != nil else { return false }
        if replayPassThrough > 0, event.type == .leftMouseDown || event.type == .leftMouseUp {
            replayPassThrough -= 1
            return false
        }
        switch event.type {
        case .leftMouseDown:
            guard session == nil, let id = pieceID(atWindowPoint: event.locationInWindow) else { return false }
            pendingPiece = PendingPiecePress(id: id, down: event, start: event.locationInWindow)
            return true
        case .leftMouseDragged:
            if let s = session, case .piece = s.kind {
                updateSlide(windowX: event.locationInWindow.x, time: event.timestamp)
                return true
            }
            guard let pending = pendingPiece else { return false }
            let dx = event.locationInWindow.x - pending.start.x
            let dy = pending.start.y - event.locationInWindow.y
            if LineDrag.pieceSlideStarts(dx: dx, dy: dy) {
                pendingPiece = nil
                beginPieceSlide(id: pending.id, windowX: pending.start.x, time: event.timestamp)
                updateSlide(windowX: event.locationInWindow.x, time: event.timestamp)
            }
            return true
        case .leftMouseUp:
            if let s = session, case .piece = s.kind {
                endSlide(windowPoint: event.locationInWindow)
                return true
            }
            guard let pending = pendingPiece else { return false }
            // Not a slide: replay the press so the piece gets a normal click.
            pendingPiece = nil
            replayPassThrough = 2
            window?.postEvent(pending.down, atStart: false)
            window?.postEvent(event, atStart: false)
            return true
        default:
            return false
        }
    }

    /// Starts sliding big piece `id` (test seam: also driven by the monitor).
    public func beginPieceSlide(id: String, windowX: CGFloat, time: TimeInterval = 0) {
        guard session == nil else { return }
        let layout = computeLayout()
        guard let home = layout.pieceFrames.first(where: { $0.id == id })?.frame else { return }
        beginSession(.init(
            kind: .piece(id), startWindowX: windowX, homeFrame: home,
            pieceTarget: arrangement.slot(of: id), lastWindowX: windowX, lastTime: time),
            view: pieceViews[id])
    }

    /// Starts sliding slip `id` along the cluster (sideways intent).
    public func beginSlipSlide(id: UUID, windowX: CGFloat, time: TimeInterval = 0) {
        guard session == nil else { return }
        let layout = computeLayout()
        guard let home = layout.slipFrames.first(where: { $0.id == id })?.frame else { return }
        let order = slipStore.hangingSlips.sorted { $0.pinSlotIndex < $1.pinSlotIndex }.map(\.id)
        beginSession(.init(
            kind: .slip(id), startWindowX: windowX, homeFrame: home,
            slipPosition: order.firstIndex(of: id), lastWindowX: windowX, lastTime: time),
            view: slipViews[id])
    }

    private func beginSession(_ s: DragSession, view: NSView?) {
        session = s
        collapseTimer?.invalidate()
        collapseTimer = nil
        dwellTimer?.invalidate()
        dwellTimer = nil
        if let key = draggedKey {
            settles.removeValue(forKey: key)
            xSprings.removeValue(forKey: key)
        }
        if let view {
            view.layer?.zPosition = 100
            if motionActive { Self.applyShadow(to: view, lifted: true) }
        }
        if let yard = window as? DesktopYardWindow {
            yard.isDraggingOnLine = true
            // Key focus so Esc reaches us; given back on release.
            if !NSApp.isActive {
                activatedForDrag = true
                NSApp.activate()
            }
            yard.makeKey()
        }
        NSCursor.closedHand.push()
        refresh()
    }

    /// Pointer moved during a slide (window x).
    public func updateSlide(windowX: CGFloat, time: TimeInterval = 0) {
        guard var s = session else { return }
        s.dx = windowX - s.startWindowX
        let dt = time - s.lastTime
        if dt > 0.0005 {
            let v = (windowX - s.lastWindowX) / CGFloat(dt)
            s.velocityX = 0.6 * v + 0.4 * s.velocityX
        }
        s.lastWindowX = windowX
        s.lastTime = time
        session = s
        retarget()
        refresh()
    }

    /// Recomputes the target slot and blocked state from the live layout.
    private func retarget() {
        guard var s = session else { return }
        let layout = computeLayout()
        switch s.kind {
        case .piece(let id):
            guard let frame = layout.pieceFrames.first(where: { $0.id == id })?.frame else { return }
            let others = layout.pieceFrames.filter { $0.id != id }
            let lead = Set(layout.arrangement.leading)
            let target = LineDrag.pieceTarget(
                centerX: frame.midX, dividerX: layout.pieceDividerX,
                remainingLeadingCenters: others.filter { lead.contains($0.id) }.map(\.frame.midX),
                remainingTrailingCenters: others.filter { !lead.contains($0.id) }.map(\.frame.midX))
            let fits = arrangementFits(arrangement.moving(id, to: target), layout: layout)
            s.blocked = !fits
            if fits { s.pieceTarget = target }
        case .slip:
            let xs = layout.occupiedSlotXs
            guard let minX = xs.first, let maxX = xs.last else { return }
            let raw = s.homeFrame.minX + s.dx
            let banded = LineDrag.rubberBanded(raw, minX: minX, maxX: maxX)
            s.blocked = banded.blocked
            if !banded.blocked {
                s.slipPosition = LineDrag.slipTargetPosition(x: raw, occupiedOrigins: xs)
            }
        }
        session = s
    }

    /// Whether `candidate` keeps the gap rule inside the 24pt edge margins
    /// with the cluster at its current width.
    private func arrangementFits(_ candidate: PieceArrangement, layout: YardLayout) -> Bool {
        var widths: [String: CGFloat] = [:]
        for p in piecesProvider() { widths[p.pieceID] = p.sizeMetrics.width }
        let leadW = candidate.leading.compactMap { widths[$0] }
        let trailW = candidate.trailing.compactMap { widths[$0] }
        if layoutMode == .portrait {
            return YardGeometry.stackWidth(leadW) + YardGeometry.stackWidth(trailW)
                + YardGeometry.stackSpacing <= bounds.width - 2 * YardGeometry.edgeMargin
        }
        let clusterW = layout.clusterRect.width > 0 ? layout.clusterRect.width - 16 : 0
        return LineDrag.pieceArrangementFits(
            displayWidth: bounds.width, clusterWidth: clusterW,
            leadingWidths: leadW, trailingWidths: trailW)
    }

    /// Menu-bar mirror check: can `id` hang in `slot` on this yard?
    public func canPlacePiece(_ id: String, at slot: PieceArrangement.Slot) -> Bool {
        arrangementFits(arrangement.moving(id, to: slot), layout: computeLayout())
    }

    public func cancelSlide() {
        finishSlide(commit: false)
    }

    /// Pointer released (window point). Outside the yard counts as cancel.
    public func endSlide(windowPoint: NSPoint) {
        let local = convert(windowPoint, from: nil)
        finishSlide(commit: bounds.contains(local))
    }

    func finishSlide(commit: Bool) {
        guard let s = session, let key = draggedKey else { return }
        let view: NSView?
        var committed = false
        switch s.kind {
        case .piece(let id):
            view = pieceViews[id]
            if commit, !s.blocked, let target = s.pieceTarget {
                let next = arrangement.moving(id, to: target)
                if next != arrangement {
                    session = nil // persisting posts a change; refresh happens below
                    pieceOrder.save(next)
                    committed = true
                }
            }
        case .slip(let id):
            view = slipViews[id]
            if commit, !s.blocked, let pos = s.slipPosition {
                let order = slipStore.hangingSlips.sorted { $0.pinSlotIndex < $1.pinSlotIndex }.map(\.id)
                if order.firstIndex(of: id) != pos {
                    committed = slipStore.reorderHanging(id: id, toPosition: pos)
                }
            }
        }
        session = nil
        if let yard = window as? DesktopYardWindow { yard.isDraggingOnLine = false }
        if activatedForDrag {
            activatedForDrag = false
            NSApp.deactivate()
        }
        NSCursor.pop()
        if let view {
            Self.setBlockedOutline(view, false)
            if motionActive {
                // Into the slot (or home) on the yield spring; pins clamp in
                // 120ms, then the lift drops on the pin-on spring with a
                // sway impulse from the release velocity.
                xSprings[key] = .init(position: view.frame.minX)
                var settle = Settle(start: Date().timeIntervalSinceReferenceDate)
                settle.rotation.velocity = max(-40, min(40, s.velocityX * 0.01))
                settles[key] = settle
            } else {
                view.layer?.zPosition = 0
                Self.crossFade(view)
            }
        }
        if !isPointerInsideCluster() { scheduleCollapse() }
        refresh()
        if committed { onLineRearranged?() }
    }

    private func isPointerInsideCluster() -> Bool {
        guard let window else { return false }
        let p = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return computeLayout().clusterRect.contains(p)
    }

    // MARK: - Tear-off completion + flutter

    private func completeTearOff(id: UUID) {
        guard let view = slipViews[id] else { return }
        guard slipStore.tearOff(id: id) else {
            pulls.removeValue(forKey: id)
            view.frameRotation = 0
            refresh()
            return
        }
        pulls.removeValue(forKey: id)
        engine.tick(dt: 1.0 / 60.0, equilibrium1: equilibrium(forLine: 1, mode: layoutMode), equilibrium2: equilibrium(forLine: 2, mode: layoutMode))
        if isMotionAllowed {
            flyToBasket(view: view, id: id)
        } else {
            fade(view: view, id: id, from: view.frame.origin,
                 to: NSPoint(x: basketView.frame.midX - 40, y: basketView.frame.minY - 10),
                 duration: 0.2, fadeOut: true)
        }
        refresh()
    }

    /// 850ms wind-biased falling-leaf trajectory into the basket.
    private func flyToBasket(view: NSView, id: UUID) {
        let from = view.frame.origin
        let to = NSPoint(x: basketView.frame.midX - 40, y: basketView.frame.minY - 10)
        let windKmh = currentEnvironment?.windSpeedKmh ?? ClotheslineMath.fallbackBreezeKmh
        let bias = CGFloat(windKmh) * 1.5 // downwind drift in points
        let start = Date()
        flutterTimers[id]?.invalidate()
        flutterTimers[id] = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                let t = Date().timeIntervalSince(start) / 0.85
                guard t < 1 else {
                    self?.flutterTimers[id]?.invalidate()
                    self?.flutterTimers.removeValue(forKey: id)
                    view.removeFromSuperview()
                    self?.slipViews.removeValue(forKey: id)
                    self?.refresh()
                    return
                }
                let ease = t * t
                let x = from.x + (to.x - from.x) * CGFloat(ease) + sin(CGFloat(t) * 9) * 14 + bias * CGFloat(t)
                let y = from.y + (to.y - from.y) * CGFloat(ease) + abs(sin(CGFloat(t) * 6)) * -10
                view.setFrameOrigin(NSPoint(x: x, y: y))
                view.frameRotation = -14 + 36 * CGFloat(t)
            }
        }
    }

    private func fade(view: NSView, id: UUID, from: NSPoint, to: NSPoint, duration: TimeInterval, fadeOut: Bool) {
        let start = Date()
        view.setFrameOrigin(from)
        view.alphaValue = fadeOut ? 1 : 0
        flutterTimers[id]?.invalidate()
        flutterTimers[id] = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                let t = min(1, Date().timeIntervalSince(start) / duration)
                guard t < 1 else {
                    self?.flutterTimers[id]?.invalidate()
                    self?.flutterTimers.removeValue(forKey: id)
                    if fadeOut {
                        view.removeFromSuperview()
                        self?.slipViews.removeValue(forKey: id)
                    } else {
                        view.alphaValue = 1
                    }
                    self?.refresh()
                    return
                }
                view.setFrameOrigin(NSPoint(
                    x: from.x + (to.x - from.x) * CGFloat(t),
                    y: from.y + (to.y - from.y) * CGFloat(t)))
                view.alphaValue = fadeOut ? 1 - CGFloat(t) : CGFloat(t)
            }
        }
    }

    /// Undo: the slip flies back up from the basket and snaps into its
    /// empty clothespin at `pinSlotIndex`, restoring 4.5pt of rope sag.
    private func undoTopSlip() {
        guard let top = slipStore.basketSlips.last else { return }
        let from = NSPoint(x: basketView.frame.midX - 52, y: basketView.frame.minY - 10)
        guard slipStore.undoToLine(id: top.id) else { return }
        engine.tick(dt: 1.0 / 60.0, equilibrium1: equilibrium(forLine: 1, mode: layoutMode), equilibrium2: equilibrium(forLine: 2, mode: layoutMode))
        refresh()
        guard let view = slipViews[top.id] else { return }
        let to = view.frame.origin
        guard isMotionAllowed else {
            fade(view: view, id: top.id, from: from, to: to, duration: 0.2, fadeOut: false)
            return
        }
        view.setFrameOrigin(from)
        view.frameRotation = 0
        let start = Date()
        let duration = 0.35
        flutterTimers[top.id]?.invalidate()
        flutterTimers[top.id] = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                let t = min(1, Date().timeIntervalSince(start) / duration)
                guard t < 1 else {
                    self?.flutterTimers[top.id]?.invalidate()
                    self?.flutterTimers.removeValue(forKey: top.id)
                    self?.refresh()
                    return
                }
                // Ease-out: fast lift, gentle seat onto the pin.
                let e = 1 - pow(1 - t, 3)
                view.setFrameOrigin(NSPoint(
                    x: from.x + (to.x - from.x) * e,
                    y: from.y + (to.y - from.y) * e))
            }
        }
    }

    // MARK: - Frame loop (60fps frame timer; 0fps when the governor stops it)

    private func startLoop() {
        guard displayLink == nil else { return }
        startTime = Date().timeIntervalSinceReferenceDate
        displayLink = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.frameTick() }
        }
    }

    private func stopLoop() {
        displayLink?.invalidate()
        displayLink = nil
        snapDragAnimations()
    }

    /// Governor stopped the loop: no springs can run, so land everything.
    private func snapDragAnimations() {
        for key in settles.keys { resetLift(key: key) }
        settles.removeAll()
        xSprings.removeAll()
        xTargets.removeAll()
    }

    private func frameTick() {
        let dt: CGFloat = 1.0 / 60.0
        let mode = layoutMode
        let e1 = equilibrium(forLine: 1, mode: mode)
        let e2 = equilibrium(forLine: 2, mode: mode)
        if rendersAtFullRate {
            engine.tick(dt: dt, equilibrium1: e1, equilibrium2: e2)
            stepDragAnimations(dt: dt)
            applySway()
        } else {
            engine.settleInstantly(equilibrium1: e1, equilibrium2: e2)
            snapDragAnimations()
        }
        applyLayout(computeLayout())
        needsDisplay = true
    }

    /// Advances the yield springs and release settles one frame.
    private func stepDragAnimations(dt: CGFloat) {
        for (key, state) in xSprings {
            guard let target = xTargets[key] else { continue }
            let next = ClotheslineMath.springStep(
                state, equilibrium: target, dt: dt,
                omega0: LineDrag.yieldOmega, zeta: LineDrag.yieldZeta)
            if session == nil, abs(next.position - target) < 0.3, abs(next.velocity) < 5 {
                xSprings.removeValue(forKey: key)
                xTargets.removeValue(forKey: key)
            } else {
                xSprings[key] = next
            }
        }
        let now = Date().timeIntervalSinceReferenceDate
        for (key, var settle) in settles {
            let t = now - settle.start
            settle.pinAngle = t < LineDrag.pinClampDuration
                ? LineDrag.pinLoosenDegrees * CGFloat(1 - t / LineDrag.pinClampDuration) : 0
            if t >= LineDrag.pinClampDuration {
                // Existing pin-on spring: ω₀ 18 rad/s, ζ 0.35.
                settle.lift = ClotheslineMath.springStep(settle.lift, equilibrium: 0, dt: dt)
            }
            settle.rotation = ClotheslineMath.springStep(
                settle.rotation, equilibrium: 0, dt: dt, omega0: 5.2, zeta: 0.35)
            let done = t >= LineDrag.pinClampDuration
                && abs(settle.lift.position) < 0.1 && abs(settle.lift.velocity) < 1
                && abs(settle.rotation.position) < 0.05 && abs(settle.rotation.velocity) < 0.5
            if done {
                settles.removeValue(forKey: key)
                resetLift(key: key)
            } else {
                settles[key] = settle
            }
        }
    }

    private func resetLift(key: String) {
        let view: NSView?
        if key.hasPrefix("piece:") {
            view = pieceViews[String(key.dropFirst("piece:".count))]
        } else if let id = UUID(uuidString: String(key.dropFirst("slip:".count))) {
            view = slipViews[id]
        } else {
            view = nil
        }
        guard let view else { return }
        view.layer?.zPosition = 0
        Self.applyShadow(to: view, lifted: false)
    }

    private func applySway() {
        let t = CGFloat(Date().timeIntervalSinceReferenceDate - startTime)
        let wind = currentEnvironment?.windSpeedKmh ?? ClotheslineMath.fallbackBreezeKmh
        let night = currentEnvironment?.solarPhase == .night
        // Amplitude scales gently with wind; night damps to ±0.8°, T=6.5s.
        let period: CGFloat = night ? 6.5 : max(2.5, 5 - CGFloat(wind) / 8)
        let pieceAmp: CGFloat = night ? 0.8 : min(2.2, 0.6 + CGFloat(wind) / 12)
        let slipAmp: CGFloat = night ? 0.8 : min(4.5, 1.5 + CGFloat(wind) / 6)
        let dragged = draggedKey
        let pieces = piecesProvider()
        for (i, piece) in pieces.enumerated() {
            let key = Self.key(piece: piece.pieceID)
            guard key != dragged else { pieceViews[piece.pieceID]?.frameRotation = 0; continue }
            let a = ClotheslineMath.swayAngle(time: t, phase: CGFloat(i) * 1.3, amplitudeDegrees: pieceAmp, period: period)
            pieceViews[piece.pieceID]?.frameRotation = a + (settles[key]?.rotation.position ?? 0)
        }
        for (i, id) in slipViews.keys.sorted(by: { "\($0)" < "\($1)" }).enumerated() {
            if flutterTimers[id] != nil { continue }
            let key = Self.key(slip: id)
            if key == dragged { slipViews[id]?.frameRotation = 0; continue }
            if slipViews[id]?.isTearing == true { continue }
            let a = ClotheslineMath.swayAngle(time: t, phase: CGFloat(i) * 0.9, amplitudeDegrees: slipAmp, period: period)
            slipViews[id]?.frameRotation = a + (settles[key]?.rotation.position ?? 0)
        }
    }
}
