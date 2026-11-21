import AppKit

/// Menu-bar presence on the main display: live `[⊶ N]` micro-line glyph +
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

    private var statusItem: NSStatusItem?
    private var popover = NSPopover()
    private var quickField = NSTextField()
    private var miniLine = MiniLineView()
    private var listStack = NSStackView()
    private var breezeButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private var settingsPanel: NSPanel?

    public var onQuickAdd: (() -> Void)?
    public var onPauseToggled: ((Bool) -> Void)?

    public init(
        slipStore: TaskSlipStore,
        planStore: HolidayPlanStore,
        allPieces: [any CompanionPiece],
        pieces: @escaping () -> [any CompanionPiece],
        governor: OcclusionGovernor
    ) {
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
        // Live micro-silhouette: [⊶ N] ticks = hanging slips on the line.
        let n = slipStore.hangingSlips.count
        statusItem?.button?.title = "[⊶ \(n)]"
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
        miniLine.hangingCount = slipStore.hangingSlips.count
        miniLine.pieceCount = piecesProvider().count
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

    @objc private func submitQuickAdd() {
        let text = quickField.stringValue
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        slipStore.addTask(text)
        quickField.stringValue = ""
        rebuildPopover()
        onQuickAdd?()
    }

    @objc private func tearMini(_ sender: NSButton) {
        // Mini-slip tear-off (>24pt equivalent): immediate in the popover.
        let hanging = slipStore.hangingSlips.sorted(by: { $0.pinSlotIndex < $1.pinSlotIndex })
        let match = hanging.first { $0.id.hashValue == sender.tag }
        if let match { slipStore.tearOff(id: match.id) }
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

/// Lightweight 1D sag/recoil mirror for the popover (runs only while the
/// popover is shown, per `isPopoverSimulationActive`).
private final class MiniLineView: NSView {
    var hangingCount = 0
    var pieceCount = 0

    override func draw(_ dirtyRect: NSRect) {
        let sag = ClotheslineMath.equilibriumSag(
            bigPieceMassUnits: Array(repeating: 6.0, count: pieceCount),
            hangingSlipCount: hangingCount, precipitation: .clear)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 0, y: 10))
        path.curve(to: NSPoint(x: bounds.width, y: 10),
                   controlPoint1: NSPoint(x: bounds.width * 0.3, y: 10 + sag * 0.4),
                   controlPoint2: NSPoint(x: bounds.width * 0.7, y: 10 + sag * 0.4))
        NSColor.secondaryLabelColor.setStroke()
        path.lineWidth = 1
        path.stroke()
        // Mini pins.
        for i in 0..<(pieceCount * 2 + hangingCount) {
            let x = 12 + CGFloat(i) * (bounds.width - 24) / CGFloat(max(1, pieceCount * 2 + hangingCount))
            let pin = NSBezierPath(rect: NSRect(x: x, y: 8, width: 3, height: 10))
            NSColor.labelColor.setFill()
            pin.fill()
        }
    }
}
