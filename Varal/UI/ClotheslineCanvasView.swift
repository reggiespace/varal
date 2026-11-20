import AppKit

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
    private var slipViews: [UUID: TaskSlipView] = [:]
    var basketView = LaundryBasketView()
    private var pulls: [UUID: CGFloat] = [:]
    private var flutterTimers: [UUID: Timer] = [:]

    /// Governor-controlled render state (set by the app).
    public var rendersAtFullRate = true {
        didSet { rendersAtFullRate ? startLoop() : stopLoop() }
    }

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
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil
        )
        addTrackingArea(area)
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

    // MARK: - Refresh / layout

    /// Rebuilds piece + slip subviews and positions after any store change.
    public func refresh() {
        let mode = layoutMode
        let pieces = piecesProvider()
        let hanging = slipStore.hangingSlips.sorted { $0.pinSlotIndex < $1.pinSlotIndex }
        let W = bounds.width

        // Mount big-piece views (generic: no Atmos/GLW naming here).
        for piece in pieces {
            let v = mainView(of: piece)
            if v.superview !== self { addSubview(v) }
        }
        // Remove views for disabled pieces.
        let activeIDs = Set(pieces.map(\.pieceID))
        _ = activeIDs

        // Prune slip views for torn-off/deleted slips; add new ones.
        let hangingIDs = Set(hanging.map(\.id))
        for id in slipViews.keys where !hangingIDs.contains(id) {
            slipViews[id]?.removeFromSuperview()
            slipViews.removeValue(forKey: id)
        }
        for slip in hanging where slipViews[slip.id] == nil {
            let v = TaskSlipView(slip: slip)
            v.onPullChanged = { [weak self] id, pull in self?.pulls[id] = pull }
            v.onTearOff = { [weak self] id in self?.completeTearOff(id: id) }
            slipViews[slip.id] = v
            addSubview(v)
        }

        let sag1 = engine.sagLine1
        let expanded = engine.clusterExpanded
        let step = ClotheslineMath.clusterStep(
            slipCount: hanging.count, expanded: expanded,
            availableWidth: max(200, W - 2 * 190), portraitLine2: mode == .portrait)

        // Piece layout.
        let leading = pieces.filter { $0.preferredSide == .leading }
        let trailing = pieces.filter { $0.preferredSide == .trailing }
        var xLead: CGFloat = 24
        var xTrail: CGFloat = W - 24
        let pushOut: CGFloat = (mode == .landscape && expanded)
            ? max(0, (CGFloat(hanging.count) * step - CGFloat(hanging.count) * ClotheslineMath.shingledStep) / 2) : 0
        for piece in leading {
            let w = piece.sizeMetrics.width, h = piece.sizeMetrics.height
            mainView(of: piece).frame = NSRect(x: xLead - pushOut, y: line1Y, width: w, height: h)
            xLead += w + 16
        }
        for piece in trailing.reversed() {
            let w = piece.sizeMetrics.width, h = piece.sizeMetrics.height
            xTrail -= w
            mainView(of: piece).frame = NSRect(x: xTrail + pushOut, y: line1Y, width: w, height: h)
            xTrail -= 16
        }

        // Slip layout.
        let slipLineY = (mode == .portrait) ? line2Y : line1Y
        let totalW = hanging.isEmpty ? 0 : CGFloat(hanging.count - 1) * step + ClotheslineMath.slipWidth
        var x0 = (W - totalW) / 2
        if mode == .landscape {
            // Keep the cluster clear of the big cards.
            x0 = max(x0, xLead + 8)
            if x0 + totalW > xTrail - 8 { x0 = xTrail - 8 - totalW }
        }
        for (i, slip) in hanging.enumerated() {
            let v = slipViews[slip.id]
            let pull = pulls[slip.id] ?? 0
            let ropeDip = pull <= 18 ? 0.45 * pull : 0.45 * 18
            v?.frame = NSRect(
                x: x0 + CGFloat(i) * step,
                y: slipLineY + sag1 * 0.925 + ropeDip,
                width: ClotheslineMath.slipWidth, height: ClotheslineMath.slipHeight)
        }

        // Basket anchored bottom-right (full vertical drop for flutter).
        let bw = LaundryBasketView.basketSize.width
        let bh = LaundryBasketView.basketSize.height
        basketView.frame = NSRect(x: W - bw - 32, y: bounds.height - bh - 64 - 20, width: bw, height: bh)
        basketView.basketCount = slipStore.basketSlips.count
        basketView.hangingCount = hanging.count
        basketView.updateLabels()

        publishHitRects(pieces: pieces, hangingCount: hanging.count)
        needsDisplay = true
    }

    private func publishHitRects(pieces: [any CompanionPiece], hangingCount: Int) {
        var rects: [CGRect] = pieces.map { mainView(of: $0).frame }
        // Small-slip cluster zone (dwell-gated expansion reads this too).
        if hangingCount > 0 {
            let xs = slipViews.values.map(\.frame.origin.x)
            let minX = (xs.min() ?? 0) - 8
            let maxX = (xs.max() ?? 0) + ClotheslineMath.slipWidth + 8
            let y = (layoutMode == .portrait ? line2Y : line1Y) - 24
            rects.append(CGRect(x: minX, y: y, width: max(60, maxX - minX), height: 200))
        }
        rects.append(basketView.frame.insetBy(dx: -16, dy: -24))
        onHitRectsChanged?(rects)
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        refresh()
    }

    // MARK: - Rope drawing

    public override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.6, alpha: 1).setStroke()
        let W = bounds.width
        func rope(atY y: CGFloat, sag: CGFloat) {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 0, y: y))
            path.curve(to: NSPoint(x: W, y: y),
                       controlPoint1: NSPoint(x: W * 0.25, y: y + ClotheslineMath.controlPointYOffset(sag: sag) * 0.55),
                       controlPoint2: NSPoint(x: W * 0.75, y: y + ClotheslineMath.controlPointYOffset(sag: sag) * 0.55))
            path.lineWidth = 1.5
            path.stroke()
        }
        rope(atY: line1Y, sag: engine.sagLine1)
        if layoutMode == .portrait {
            rope(atY: line2Y, sag: engine.sagLine2)
        }
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
        slipStore.tearOff(id: id)
        pulls.removeValue(forKey: id)
        engine.tick(dt: 1.0 / 60.0, equilibrium1: equilibrium(forLine: 1, mode: layoutMode), equilibrium2: equilibrium(forLine: 2, mode: layoutMode))
        flyToBasket(view: view, id: id)
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

    private func undoTopSlip() {
        guard let top = slipStore.basketSlips.last else { return }
        slipStore.undoToLine(id: top.id)
        refresh()
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
        refreshPositionsOnly()
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
            mainView(of: piece).frameRotation = a
        }
        for (i, id) in slipViews.keys.sorted(by: { "\($0)" < "\($1)" }).enumerated() {
            if flutterTimers[id] != nil { continue }
            let a = ClotheslineMath.swayAngle(time: t, phase: CGFloat(i) * 0.9, amplitudeDegrees: slipAmp, period: period)
            slipViews[id]?.frameRotation = a
        }
    }

    /// Cheap per-frame position update without rebuilding subviews.
    private func refreshPositionsOnly() {
        let mode = layoutMode
        let hanging = slipStore.hangingSlips.sorted { $0.pinSlotIndex < $1.pinSlotIndex }
        let sag1 = engine.sagLine1
        let expanded = engine.clusterExpanded
        let W = bounds.width
        let step = ClotheslineMath.clusterStep(
            slipCount: hanging.count, expanded: expanded,
            availableWidth: max(200, W - 2 * 190), portraitLine2: mode == .portrait)
        let totalW = hanging.isEmpty ? 0 : CGFloat(hanging.count - 1) * step + ClotheslineMath.slipWidth
        let x0 = (W - totalW) / 2
        let slipLineY = (mode == .portrait) ? line2Y : line1Y
        for (i, slip) in hanging.enumerated() {
            guard let v = slipViews[slip.id], flutterTimers[slip.id] == nil else { continue }
            let pull = pulls[slip.id] ?? 0
            let ropeDip = pull <= 18 ? 0.45 * pull : 0.45 * 18
            v.setFrameOrigin(NSPoint(
                x: x0 + CGFloat(i) * step,
                y: slipLineY + sag1 * 0.925 + ropeDip))
        }
    }
}
