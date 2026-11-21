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
    public var pieceFrames: [PieceFrame] = []
    public var slipFrames: [SlipFrame] = []
    /// 18pt bare-pin rects for slots with no hanging slip (torn/undo).
    public var emptyPinRects: [CGRect] = []
    /// Pin rects for occupied slots (drawn over the slip top).
    public var occupiedPinRects: [CGRect] = []
    public var clusterRect: CGRect = .zero
    public var line1Y: CGFloat = 0
    public var line2Y: CGFloat = 0
    public var sag1: CGFloat = 0
    public var sag2: CGFloat = 0
}

/// Clothesline stage on the selected display. Top-left (flipped) coordinate
/// space; ropes, pins, pieces, slips, and the basket are laid out here.
///
/// Landscape (`width >= height`): one rope — leading big pieces, center
/// task cluster, trailing big pieces. Portrait (`height > width`): two
/// stacked ropes — Line 1 big pieces, Line 2 task slips.
@MainActor
public final class ClotheslineCanvasView: NSView {
    private let slipStore: TaskSlipStore
    private let planStore: HolidayPlanStore
    private let piecesProvider: () -> [any CompanionPiece]
    private let environmentProvider: () -> EnvironmentSnapshot?
    private let engine = ClotheslinePhysicsEngine()

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

    /// Governor-controlled render state (set by the app).
    public var rendersAtFullRate = true {
        didSet { rendersAtFullRate ? startLoop() : stopLoop() }
    }
    public var isMotionAllowed = true

    public var onHitRectsChanged: (@MainActor ([CGRect]) -> Void)?

    public init(
        slipStore: TaskSlipStore,
        planStore: HolidayPlanStore,
        pieces: @escaping () -> [any CompanionPiece],
        environment: @escaping () -> EnvironmentSnapshot?
    ) {
        self.slipStore = slipStore
        self.planStore = planStore
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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    public override var isFlipped: Bool { true }

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

    // MARK: - Unified layout (single source of truth)

    /// Computes every frame from current bounds, stores, and engine sag.
    /// Slot-stable: slips are positioned by `pinSlotIndex`, so tearing one
    /// slip leaves its neighbors exactly where they were.
    public func computeLayout() -> YardLayout {
        let mode = layoutMode
        let pieces = piecesProvider()
        let W = bounds.width
        let sag1 = engine.sagLine1
        let sag2 = engine.sagLine2
        let expanded = engine.clusterExpanded
        let ultrawide = ClotheslineMath.isUltrawide(size: bounds.size)
        var layout = YardLayout(
            line1Y: line1Y, line2Y: line2Y, sag1: sag1, sag2: sag2)

        let leading = pieces.filter { $0.preferredSide == .leading }
        let trailing = pieces.filter { $0.preferredSide == .trailing }

        // Piece placement: ultrawide centers pieces in the display thirds;
        // standard and portrait keep the legacy edge anchors pixel-identical.
        var leadRight: CGFloat = 24
        var trailLeft: CGFloat = W - 24
        if mode == .landscape, ultrawide {
            for piece in leading {
                let w = piece.sizeMetrics.width
                layout.pieceFrames.append(.init(
                    id: piece.pieceID,
                    frame: NSRect(
                        x: ClotheslineMath.thirdsLeadingX(displayWidth: W, pieceWidth: w),
                        y: line1Y, width: w, height: piece.sizeMetrics.height)))
            }
            for piece in trailing {
                let w = piece.sizeMetrics.width
                layout.pieceFrames.append(.init(
                    id: piece.pieceID,
                    frame: NSRect(
                        x: ClotheslineMath.thirdsTrailingX(displayWidth: W, pieceWidth: w),
                        y: line1Y, width: w, height: piece.sizeMetrics.height)))
            }
        } else {
            var xLead: CGFloat = 24
            for piece in leading {
                let w = piece.sizeMetrics.width, h = piece.sizeMetrics.height
                layout.pieceFrames.append(.init(
                    id: piece.pieceID,
                    frame: NSRect(x: xLead, y: line1Y, width: w, height: h)))
                xLead += w + 16
            }
            var xTrail: CGFloat = W - 24
            for piece in trailing.reversed() {
                let w = piece.sizeMetrics.width, h = piece.sizeMetrics.height
                xTrail -= w
                layout.pieceFrames.append(.init(
                    id: piece.pieceID,
                    frame: NSRect(x: xTrail, y: line1Y, width: w, height: h)))
                xTrail -= 16
            }
        }
        if ultrawide {
            leadRight = layout.pieceFrames
                .filter { leading.map(\.pieceID).contains($0.id) }
                .map(\.frame.maxX).max() ?? 24
            trailLeft = layout.pieceFrames
                .filter { trailing.map(\.pieceID).contains($0.id) }
                .map(\.frame.minX).min() ?? W - 24
        } else if mode == .landscape {
            leadRight = layout.pieceFrames
                .filter { leading.map(\.pieceID).contains($0.id) }
                .map(\.frame.maxX).max() ?? 24
            trailLeft = layout.pieceFrames
                .filter { trailing.map(\.pieceID).contains($0.id) }
                .map(\.frame.minX).min() ?? W - 24
        }

        // Cluster expansion pushes shared-rope pieces toward the edges.
        let hanging = slipStore.hangingSlips.sorted { $0.pinSlotIndex < $1.pinSlotIndex }
        let inBasketSlots = Set(slipStore.basketSlips.map(\.pinSlotIndex))
        let maxSlot = (hanging.map(\.pinSlotIndex) + inBasketSlots).max() ?? -1
        var slots: [Bool] = []
        if maxSlot >= 0 {
            let bySlot = Dictionary(uniqueKeysWithValues: hanging.map { ($0.pinSlotIndex, $0) })
            slots = (0...maxSlot).map { bySlot[$0] != nil }
        }
        let slipLineY = (mode == .portrait) ? line2Y : line1Y
        let slipSag = (mode == .portrait) ? sag2 : sag1

        let step: CGFloat
        let availableWidth: CGFloat
        if mode == .portrait {
            availableWidth = W - 48
            step = ClotheslineMath.clusterStep(
                slipCount: slots.count, expanded: expanded,
                availableWidth: max(200, availableWidth), portraitLine2: true)
        } else if ultrawide {
            availableWidth = max(200, trailLeft - leadRight - 16)
            step = ClotheslineMath.ultrawideClusterStep(
                slipCount: slots.count, expanded: expanded,
                availableWidth: availableWidth)
        } else {
            availableWidth = max(200, trailLeft - leadRight - 16)
            step = ClotheslineMath.clusterStep(
                slipCount: slots.count, expanded: expanded,
                availableWidth: availableWidth, portraitLine2: false)
        }
        var pushOut: CGFloat = (mode == .landscape && expanded)
            ? max(0, (CGFloat(slots.count) * step - CGFloat(slots.count) * ClotheslineMath.shingledStep) / 2) : 0
        if pushOut > 0 {
            let limits = layout.pieceFrames.map { frame in
                leading.map(\.pieceID).contains(frame.id)
                    ? frame.frame.minX - 24
                    : W - 24 - frame.frame.maxX
            }
            pushOut = min(pushOut, max(0, limits.min() ?? 0))
        }
        if expanded, mode == .landscape {
            for i in layout.pieceFrames.indices {
                let id = layout.pieceFrames[i].id
                var f = layout.pieceFrames[i].frame
                if leading.map(\.pieceID).contains(id) { f.origin.x -= pushOut }
                else { f.origin.x += pushOut }
                layout.pieceFrames[i] = .init(id: id, frame: f)
            }
            if !ultrawide {
                leadRight = layout.pieceFrames
                    .filter { leading.map(\.pieceID).contains($0.id) }
                    .map(\.frame.maxX).max() ?? 24
                trailLeft = layout.pieceFrames
                    .filter { trailing.map(\.pieceID).contains($0.id) }
                    .map(\.frame.minX).min() ?? W - 24
            } else {
                leadRight -= pushOut
                trailLeft += pushOut
            }
        }

        // Slot-stable slip positions + pin rects.
        let origins = ClotheslineMath.slotOrigins(slots: slots, step: step)
        let totalW = ClotheslineMath.slotTotalWidth(slots: slots, origins: origins)
        var x0 = (W - totalW) / 2
        if mode == .landscape {
            x0 = max(x0, leadRight + 8)
            if x0 + totalW > trailLeft - 8 { x0 = trailLeft - 8 - totalW }
        }
        if !slots.isEmpty {
            let bySlot = Dictionary(uniqueKeysWithValues: hanging.map { ($0.pinSlotIndex, $0) })
            for slot in slots.indices {
                let x = x0 + origins[slot]
                let pull = bySlot[slot].flatMap { pulls[$0.id] } ?? 0
                let ropeDip = pull <= 18 ? 0.45 * pull : 0.45 * 18
                if let slip = bySlot[slot] {
                    layout.slipFrames.append(.init(
                        id: slip.id, slot: slot,
                        frame: NSRect(
                            x: x, y: slipLineY + slipSag * 0.925 + ropeDip,
                            width: ClotheslineMath.slipWidth,
                            height: ClotheslineMath.slipHeight)))
                    layout.occupiedPinRects.append(pinRect(
                        slotX: x, slotWidth: ClotheslineMath.slipWidth,
                        ropeY: slipLineY + slipSag * 0.925))
                } else {
                    // Bare pin stays centered where the torn slip's pin was.
                    layout.emptyPinRects.append(pinRect(
                        slotX: x, slotWidth: ClotheslineMath.slipWidth,
                        ropeY: slipLineY + slipSag * 0.925))
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
            }
        }
        for frame in layout.pieceFrames {
            pieceViews[frame.id]?.frame = frame.frame
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
            slipViews[slip.id] = v
            addSubview(v)
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

    /// Applies precomputed frames to subviews. Pointer-dragged slips keep
    /// their pointer-driven position; everything else follows the layout.
    private func applyLayout(_ layout: YardLayout) {
        for frame in layout.pieceFrames {
            pieceViews[frame.id]?.frame = frame.frame
        }
        for slipFrame in layout.slipFrames {
            guard let v = slipViews[slipFrame.id],
                  flutterTimers[slipFrame.id] == nil,
                  !v.isDragging else { continue }
            v.setFrameOrigin(slipFrame.frame.origin)
        }
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
        // Extra local dip while a slip is mid-drag (prototype behavior:
        // rope follows 0.45 * pull, capped at +28pt).
        let maxPull = pulls.values.max() ?? 0
        let extraDip = min(28, 0.45 * maxPull)
        NSColor(calibratedWhite: 0.6, alpha: 1).setStroke()
        let W = bounds.width
        func rope(atY y: CGFloat, sag: CGFloat) {
            let a = ClotheslineMath.ropeCubicControlYOffset(sag: sag + extraDip)
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 0, y: y))
            path.curve(to: NSPoint(x: W, y: y),
                       controlPoint1: NSPoint(x: W / 3, y: y + a),
                       controlPoint2: NSPoint(x: 2 * W / 3, y: y + a))
            path.lineWidth = 1.5
            path.stroke()
        }
        let layout = computeLayout()
        rope(atY: layout.line1Y, sag: layout.sag1)
        if layoutMode == .portrait {
            rope(atY: layout.line2Y, sag: layout.sag2)
        }
        // Clothespins: wooden pins over every occupied slip top + bare
        // pins at empty slots where torn slips used to hang.
        for rect in layout.occupiedPinRects + layout.emptyPinRects {
            drawPin(rect)
        }
    }

    private func drawPin(_ rect: CGRect) {
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
    }

    // MARK: - Dwell-gated cluster (150ms in, 250ms out)

    public override func mouseEntered(with event: NSEvent) {
        collapseTimer?.invalidate()
        collapseTimer = nil
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
        guard engine.clusterExpanded, collapseTimer == nil else { return }
        collapseTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.collapseTimer = nil
                self?.engine.setClusterExpanded(false)
                self?.refresh()
            }
        }
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
    }

    private func frameTick() {
        let dt: CGFloat = 1.0 / 60.0
        let mode = layoutMode
        let e1 = equilibrium(forLine: 1, mode: mode)
        let e2 = equilibrium(forLine: 2, mode: mode)
        if rendersAtFullRate {
            engine.tick(dt: dt, equilibrium1: e1, equilibrium2: e2)
            applySway()
        } else {
            engine.settleInstantly(equilibrium1: e1, equilibrium2: e2)
        }
        applyLayout(computeLayout())
        needsDisplay = true
    }

    private func applySway() {
        let t = CGFloat(Date().timeIntervalSinceReferenceDate - startTime)
        let wind = currentEnvironment?.windSpeedKmh ?? ClotheslineMath.fallbackBreezeKmh
        let night = currentEnvironment?.solarPhase == .night
        // Amplitude scales gently with wind; night damps to ±0.8°, T=6.5s.
        let period: CGFloat = night ? 6.5 : max(2.5, 5 - CGFloat(wind) / 8)
        let pieceAmp: CGFloat = night ? 0.8 : min(2.2, 0.6 + CGFloat(wind) / 12)
        let slipAmp: CGFloat = night ? 0.8 : min(4.5, 1.5 + CGFloat(wind) / 6)
        let pieces = piecesProvider()
        for (i, piece) in pieces.enumerated() {
            let a = ClotheslineMath.swayAngle(time: t, phase: CGFloat(i) * 1.3, amplitudeDegrees: pieceAmp, period: period)
            pieceViews[piece.pieceID]?.frameRotation = a
        }
        for (i, id) in slipViews.keys.sorted(by: { "\($0)" < "\($1)" }).enumerated() {
            if flutterTimers[id] != nil { continue }
            let a = ClotheslineMath.swayAngle(time: t, phase: CGFloat(i) * 0.9, amplitudeDegrees: slipAmp, period: period)
            slipViews[id]?.frameRotation = a
        }
    }
}
