import AppKit

/// Menu-bar presence on the main display: live clothesline glyph with slip count +
/// `NSPopover` with the mini clothesline mirror, quick-add input, mini-slip
/// tear-off, Pause Breeze toggle, and Settings (display picker + pieces).
@MainActor
public final class MenuBarController {
    public static let enabledPiecesKey = "enabledCompanionPieceIDs"
    public static let pauseBreezeKey = "pauseBreeze"
    public static let defaultEnabledPieces = ["atmos", "get-long-weekend"]

    private let slipStore: TaskSlipStore
    private let planStore: HolidayPlanStore
    private let piecesProvider: () -> [any CompanionPiece]
    private let allPieces: [any CompanionPiece]
    private let governor: OcclusionGovernor
    private let pieceOrder: PieceOrderStore

    private var statusItem: NSStatusItem?
    private var popover = NSPopover()
    private var quickField = NSTextField()
    private var miniLine = MiniLineView()
    private var listStack = NSStackView()
    private var breezeButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private var settingsPanel: NSPanel?

    public var onQuickAdd: (() -> Void)?
    /// Whether a big piece fits in a slot on the real yard (gap rule + 24pt
    /// edge margins). Set by the app from the desktop canvas.
    public var canPlacePiece: ((String, PieceArrangement.Slot) -> Bool)?
    /// A mirror slide committed a new order: refresh the desktop line.
    public var onLineRearranged: (() -> Void)?
    public var onPauseToggled: ((Bool) -> Void)?

    public init(
        slipStore: TaskSlipStore,
        planStore: HolidayPlanStore,
        allPieces: [any CompanionPiece],
        pieces: @escaping () -> [any CompanionPiece],
        governor: OcclusionGovernor,
        pieceOrder: PieceOrderStore = PieceOrderStore()
    ) {
        self.pieceOrder = pieceOrder
        self.slipStore = slipStore
        self.planStore = planStore
        self.allPieces = allPieces
        self.piecesProvider = pieces
        self.governor = governor
        if UserDefaults.standard.array(forKey: Self.enabledPiecesKey) == nil {
            UserDefaults.standard.set(Self.defaultEnabledPieces, forKey: Self.enabledPiecesKey)
        }
    }

    public func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        statusItem = item
        refreshGlyph()

        popover.behavior = .transient
        popover.contentViewController = makePopoverContent()
    }

    public func refreshGlyph() {
        guard let button = statusItem?.button else { return }
        let n = slipStore.hangingSlips.count
        if let image = NSImage(named: NSImage.Name("MenuBarIconTemplate")) {
            image.isTemplate = true
            image.size = NSSize(width: 14, height: 16)
            button.image = image
            button.imagePosition = .imageLeading
            button.title = "\(n)"
            button.setAccessibilityLabel("Varal, \(n) slips")
        } else {
            button.image = nil
            button.title = "[⊶ \(n)]"
            button.setAccessibilityLabel(nil)
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            governor.isPopoverShown = false
        } else {
            rebuildPopover()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            governor.isPopoverShown = true
        }
    }

    // MARK: - Popover content (260×310 mini mirror)

    private func makePopoverContent() -> NSViewController {
        let vc = NSViewController()
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 310))
        vc.view = root

        miniLine.frame = NSRect(x: 10, y: 240, width: 240, height: 60)
        miniLine.onPieceMoved = { [weak self] id, slot in
            guard let self else { return false }
            guard self.canPlacePiece?(id, slot) ?? true else { return false }
            let current = self.currentArrangement()
            let next = current.moving(id, to: slot)
            if next != current { self.pieceOrder.save(next) }
            self.rebuildPopover()
            self.onLineRearranged?()
            return true
        }
        miniLine.onSlipMoved = { [weak self] id, position in
            guard let self else { return }
            self.slipStore.reorderHanging(id: id, toPosition: position)
            self.rebuildPopover()
            self.onLineRearranged?()
        }
        miniLine.canPlacePiece = { [weak self] id, slot in self?.canPlacePiece?(id, slot) ?? true }
        root.addSubview(miniLine)

        quickField.frame = NSRect(x: 10, y: 208, width: 240, height: 24)
        let locale = AppLocale.current()
        quickField.placeholderString = locale == .pt ? "+ Fixar tarefa… (17:30 …)" : "+ Pin task… (17:30 …)"
        quickField.target = self
        quickField.action = #selector(submitQuickAdd)
        root.addSubview(quickField)

        let scroll = NSScrollView(frame: NSRect(x: 10, y: 78, width: 240, height: 122))
        scroll.hasVerticalScroller = true
        listStack.orientation = .vertical
        listStack.spacing = 2
        listStack.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = listStack
        root.addSubview(scroll)

        let basketLabel = NSTextField(labelWithString: "")
        basketLabel.frame = NSRect(x: 10, y: 56, width: 150, height: 16)
        basketLabel.tag = 99
        root.addSubview(basketLabel)

        breezeButton = NSButton(checkboxWithTitle: locale == .pt ? "Pausar brisa" : "Pause Breeze", target: self, action: #selector(toggleBreeze))
        breezeButton.frame = NSRect(x: 10, y: 32, width: 150, height: 18)
        breezeButton.state = UserDefaults.standard.bool(forKey: Self.pauseBreezeKey) ? .on : .off
        root.addSubview(breezeButton)

        let settingsButton = NSButton(title: "⚙", target: self, action: #selector(openSettings))
        settingsButton.frame = NSRect(x: 222, y: 28, width: 28, height: 24)
        settingsButton.bezelStyle = .rounded
        root.addSubview(settingsButton)

        rebuildPopover()
        return vc
    }

    private func rebuildPopover() {
        guard let root = popover.contentViewController?.view else { return }
        let arrangement = currentArrangement()
        miniLine.leading = arrangement.leading
        miniLine.trailing = arrangement.trailing
        miniLine.slips = slipStore.hangingSlips.sorted { $0.pinSlotIndex < $1.pinSlotIndex }.map(\.id)
        miniLine.needsDisplay = true

        listStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for slip in slipStore.hangingSlips.sorted(by: { $0.pinSlotIndex < $1.pinSlotIndex }) {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 4
            let label = NSTextField(labelWithString: "[⊶] \(slip.timeLabel) \(slip.title)")
            label.font = .systemFont(ofSize: 11)
            let tear = NSButton(title: "↓", target: self, action: #selector(tearMini(_:)))
            tear.tag = slip.id.hashValue
            tear.bezelStyle = .smallSquare
            row.addArrangedSubview(label)
            row.addArrangedSubview(tear)
            listStack.addArrangedSubview(row)
        }
        if let basketLabel = root.viewWithTag(99) as? NSTextField {
            basketLabel.stringValue = UIStrings.basketCountLabel(count: slipStore.basketSlips.count, locale: localeOfPopover())
        }
        refreshGlyph()
    }

    private func localeOfPopover() -> AppLocale { AppLocale.current() }

    private func currentArrangement() -> PieceArrangement {
        pieceOrder.resolve(active: piecesProvider().map { (id: $0.pieceID, side: $0.preferredSide) })
    }

    /// Re-reads the line after a desktop drag committed a new order.
    public func lineRearranged() {
        if popover.isShown { rebuildPopover() }
    }

    @objc private func submitQuickAdd() {
        let text = quickField.stringValue
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard slipStore.addTask(text) != nil else { return }
        quickField.stringValue = ""
        rebuildPopover()
        onQuickAdd?()
    }

    @objc private func tearMini(_ sender: NSButton) {
        // Mini-slip tear-off (>24pt equivalent): immediate in the popover.
        let hanging = slipStore.hangingSlips.sorted(by: { $0.pinSlotIndex < $1.pinSlotIndex })
        let match = hanging.first { $0.id.hashValue == sender.tag }
        guard let match, slipStore.tearOff(id: match.id) else { return }
        rebuildPopover()
        onQuickAdd?()
    }

    @objc private func toggleBreeze() {
        let paused = breezeButton.state == .on
        UserDefaults.standard.set(paused, forKey: Self.pauseBreezeKey)
        governor.isUserBreezePaused = paused
        onPauseToggled?(paused)
    }

    // MARK: - Settings (display picker + piece toggles)

    @objc private func openSettings() {
        if settingsPanel == nil {
            let locale = AppLocale.current()
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 220),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false)
            panel.title = UIStrings.settingsTitle(locale: locale)
            let root = NSStackView(frame: NSRect(x: 16, y: 16, width: 288, height: 188))
            root.orientation = .vertical
            root.spacing = 8

            let displayLabel = NSTextField(labelWithString: UIStrings.displayPickerLabel(locale: locale))
            root.addArrangedSubview(displayLabel)
            let popup = NSPopUpButton()
            popup.tag = 101
            for (i, screen) in NSScreen.screens.enumerated() {
                popup.addItem(withTitle: "\(screen.localizedName) (\(i))")
                popup.lastItem?.tag = Int(screen.displayID)
            }
            let current = UserDefaults.standard.object(forKey: DesktopYardWindow.selectedScreenKey) as? UInt32 ?? 0
            popup.selectItem(withTag: Int(current))
            popup.target = self
            popup.action = #selector(displayChosen(_:))
            root.addArrangedSubview(popup)

            let piecesLabel = NSTextField(labelWithString: UIStrings.companionPiecesLabel(locale: locale))
            root.addArrangedSubview(piecesLabel)
            let enabled = Set(UserDefaults.standard.stringArray(forKey: Self.enabledPiecesKey) ?? Self.defaultEnabledPieces)
            for piece in allPieces {
                let box = NSButton(checkboxWithTitle: piece.displayName, target: self, action: #selector(pieceToggled(_:)))
                box.identifier = NSUserInterfaceItemIdentifier(piece.pieceID)
                box.state = enabled.contains(piece.pieceID) ? .on : .off
                root.addArrangedSubview(box)
            }

            panel.contentView?.addSubview(root)
            settingsPanel = panel
        }
        settingsPanel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func displayChosen(_ sender: NSPopUpButton) {
        UserDefaults.standard.set(UInt32(sender.selectedTag()), forKey: DesktopYardWindow.selectedScreenKey)
        NotificationCenter.default.post(name: .varalDisplayChanged, object: nil)
    }

    @objc private func pieceToggled(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        var enabled = Set(UserDefaults.standard.stringArray(forKey: Self.enabledPiecesKey) ?? Self.defaultEnabledPieces)
        if sender.state == .on { enabled.insert(id) } else { enabled.remove(id) }
        UserDefaults.standard.set(Array(enabled), forKey: Self.enabledPiecesKey)
        NotificationCenter.default.post(name: .varalPiecesChanged, object: nil)
    }
}

public extension Notification.Name {
    static let varalPiecesChanged = Notification.Name("ca.reggiespace.varal.piecesChanged")
    static let varalDisplayChanged = Notification.Name("ca.reggiespace.varal.displayChanged")
}

/// Lightweight mirror of the line for the popover: big pieces, the slip
/// cluster and the same horizontal slide as the desktop (Option A). Tearing
/// stays on the per-slip button; a drag here only reorders.
final class MiniLineView: NSView {
    var leading: [String] = []
    var trailing: [String] = []
    var slips: [UUID] = []
    var onPieceMoved: ((String, PieceArrangement.Slot) -> Bool)?
    var onSlipMoved: ((UUID, Int) -> Void)?
    var canPlacePiece: ((String, PieceArrangement.Slot) -> Bool)?

    enum Item: Equatable {
        case piece(String)
        case slip(UUID)
    }

    static let pieceSize = NSSize(width: 26, height: 18)
    static let slipSize = NSSize(width: 12, height: 16)
    static let slipStep: CGFloat = 14
    static let gap: CGFloat = 8
    static let spacing: CGFloat = 4
    static let ropeY: CGFloat = 14

    private var dragItem: Item?
    private var pressItem: Item?
    private var startX: CGFloat = 0
    private var startY: CGFloat = 0
    private var dx: CGFloat = 0
    private var pieceTarget: PieceArrangement.Slot?
    private var slipTarget: Int?
    private var blocked = false

    override var isFlipped: Bool { true }

    private var arrangement: PieceArrangement { PieceArrangement(leading: leading, trailing: trailing) }

    /// Frames for an arrangement + slip order (live preview while dragging).
    func frames(arrangement: PieceArrangement, slips: [UUID]) -> [(Item, CGRect)] {
        let W = bounds.width
        let cw = slips.isEmpty ? 0 : Self.slipSize.width + Self.slipStep * CGFloat(slips.count - 1)
        let leadW = CGFloat(arrangement.leading.count) * (Self.pieceSize.width + Self.spacing) - (arrangement.leading.isEmpty ? 0 : Self.spacing)
        let cl = W / 2 - cw / 2
        var out: [(Item, CGRect)] = []
        var x = cl - (arrangement.leading.isEmpty ? 0 : Self.gap) - leadW
        for id in arrangement.leading {
            out.append((.piece(id), CGRect(x: x, y: Self.ropeY - 2, width: Self.pieceSize.width, height: Self.pieceSize.height)))
            x += Self.pieceSize.width + Self.spacing
        }
        for (i, id) in slips.enumerated() {
            out.append((.slip(id), CGRect(x: cl + CGFloat(i) * Self.slipStep, y: Self.ropeY - 2, width: Self.slipSize.width, height: Self.slipSize.height)))
        }
        x = cl + cw + (arrangement.trailing.isEmpty ? 0 : Self.gap)
        for id in arrangement.trailing {
            out.append((.piece(id), CGRect(x: x, y: Self.ropeY - 2, width: Self.pieceSize.width, height: Self.pieceSize.height)))
            x += Self.pieceSize.width + Self.spacing
        }
        return out
    }

    private func previewFrames() -> [(Item, CGRect)] {
        var arr = arrangement
        var order = slips
        if !blocked {
            if case .piece(let id)? = dragItem, let t = pieceTarget { arr = arr.moving(id, to: t) }
            if case .slip(let id)? = dragItem, let t = slipTarget, let from = order.firstIndex(of: id) {
                order.remove(at: from)
                order.insert(id, at: min(t, order.count))
            }
        }
        var result = frames(arrangement: arr, slips: order)
        if let dragItem, let home = frames(arrangement: arrangement, slips: slips).first(where: { $0.0 == dragItem })?.1,
           let i = result.firstIndex(where: { $0.0 == dragItem }) {
            var x = home.minX + dx
            if case .slip = dragItem {
                let slipXs = frames(arrangement: arrangement, slips: slips).filter {
                    if case .slip = $0.0 { return true } else { return false }
                }.map(\.1.minX)
                if let lo = slipXs.min(), let hi = slipXs.max() {
                    x = LineDrag.rubberBanded(x, minX: lo, maxX: hi).x
                }
            }
            result[i].1 = CGRect(x: x, y: home.minY - 2, width: home.width, height: home.height)
        }
        return result
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        pressItem = frames(arrangement: arrangement, slips: slips).first { $0.1.contains(p) }?.0
        startX = p.x
        startY = p.y
        dx = 0
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if dragItem == nil {
            guard let pressItem else { return }
            let dx = p.x - startX
            let dy = p.y - startY
            switch pressItem {
            case .piece:
                guard LineDrag.menuSlideStarts(isPiece: true, dx: dx, dy: dy) else { return }
            case .slip:
                guard LineDrag.menuSlideStarts(isPiece: false, dx: dx, dy: dy) else { return }
            }
            dragItem = pressItem
        }
        dx = p.x - startX
        retarget()
        needsDisplay = true
    }

    private func retarget() {
        guard let dragItem else { return }
        let rest = frames(arrangement: arrangement, slips: slips)
        guard let home = rest.first(where: { $0.0 == dragItem })?.1 else { return }
        let x = home.minX + dx
        switch dragItem {
        case .piece(let id):
            let preview = previewFrames().filter { $0.0 != dragItem }
            let slipXs = rest.compactMap { item, f -> CGFloat? in if case .slip = item { return f.midX } else { return nil } }
            let divider = slipXs.isEmpty ? bounds.width / 2 : (slipXs.min()! + slipXs.max()!) / 2
            var previewArr = arrangement
            if !blocked, let t = pieceTarget { previewArr = arrangement.moving(id, to: t) }
            let leadSet = Set(previewArr.leading)
            let lc = preview.compactMap { item, f -> CGFloat? in
                if case .piece(let other) = item, leadSet.contains(other) { return f.midX }
                return nil
            }
            let tc = preview.compactMap { item, f -> CGFloat? in
                if case .piece(let other) = item, !leadSet.contains(other) { return f.midX }
                return nil
            }
            let target = LineDrag.pieceTarget(
                centerX: x + home.width / 2, dividerX: divider,
                remainingLeadingCenters: lc, remainingTrailingCenters: tc)
            blocked = !(canPlacePiece?(id, target) ?? true)
            if !blocked { pieceTarget = target }
        case .slip:
            let slipXs = rest.compactMap { item, f -> CGFloat? in if case .slip = item { return f.minX } else { return nil } }
            guard let lo = slipXs.min(), let hi = slipXs.max() else { return }
            blocked = LineDrag.rubberBanded(x, minX: lo, maxX: hi).blocked
            if !blocked { slipTarget = LineDrag.slipTargetPosition(x: x, occupiedOrigins: slipXs) }
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragItem = nil; pressItem = nil; pieceTarget = nil; slipTarget = nil; blocked = false; dx = 0
            needsDisplay = true
        }
        guard let dragItem, !blocked else { return }
        switch dragItem {
        case .piece(let id):
            if let t = pieceTarget { _ = onPieceMoved?(id, t) }
        case .slip(let id):
            if let t = slipTarget, slips.firstIndex(of: id) != t { onSlipMoved?(id, t) }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let sag = ClotheslineMath.equilibriumSag(
            bigPieceMassUnits: Array(repeating: 6.0, count: leading.count + trailing.count),
            hangingSlipCount: slips.count, precipitation: .clear)
        let y = Self.ropeY
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 0, y: y))
        path.curve(to: NSPoint(x: bounds.width, y: y),
                   controlPoint1: NSPoint(x: bounds.width * 0.3, y: y + sag * 0.15),
                   controlPoint2: NSPoint(x: bounds.width * 0.7, y: y + sag * 0.15))
        NSColor.secondaryLabelColor.setStroke()
        path.lineWidth = 1
        path.stroke()
        for (item, frame) in previewFrames() {
            let isDragged = item == dragItem
            let shape = NSBezierPath(roundedRect: frame, xRadius: 2, yRadius: 2)
            switch item {
            case .piece:
                NSColor.labelColor.withAlphaComponent(0.55).setFill()
            case .slip:
                NSColor.textBackgroundColor.setFill()
            }
            shape.fill()
            if isDragged && blocked {
                NSColor(calibratedRed: 0xC2 / 255.0, green: 0x41 / 255.0, blue: 0x0C / 255.0, alpha: 1).setStroke()
                shape.lineWidth = 1.5
            } else {
                NSColor.secondaryLabelColor.setStroke()
                shape.lineWidth = 0.75
            }
            shape.stroke()
            // Pin straddling the rope.
            NSColor.labelColor.setFill()
            NSBezierPath(rect: NSRect(x: frame.midX - 1.5, y: frame.minY - 4, width: 3, height: 7)).fill()
        }
    }
}
