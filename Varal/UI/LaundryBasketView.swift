import AppKit

/// Bottom-right laundry basket (`cesto`, 112×64pt). Renders stacked
/// completed slips + the day-complete caption, handles drag-up undo
/// (>60pt toward the line) and the manual [Limpar cesto] deletion action.
@MainActor
public final class LaundryBasketView: NSView {
    public static let basketSize = NSSize(width: 112, height: 64)

    public var basketCount: Int = 0 { didSet { needsDisplay = true } }
    public var hangingCount: Int = 0 { didSet { needsDisplay = true } }
    public var onEmptyBasket: (() -> Void)?
    public var onUndoTop: (() -> Void)?

    private let clearButton = NSButton(title: "", target: nil, action: nil)
    private var hoverPeek = false

    public init() {
        super.init(frame: NSRect(origin: .zero, size: Self.basketSize))
        wantsLayer = true
        clearButton.bezelStyle = .inline
        clearButton.isBordered = false
        clearButton.target = self
        clearButton.action = #selector(emptyBasket)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(clearButton)
        NSLayoutConstraint.activate([
            clearButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            clearButton.topAnchor.constraint(equalTo: topAnchor, constant: -22),
        ])
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        updateLabels()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    public func updateLabels() {
        let locale = AppLocale.current()
        clearButton.title = "[\(UIStrings.emptyBasket(locale: locale))]"
    }

    public override func draw(_ dirtyRect: NSRect) {
        // Woven basket trapezoid.
        let basket = NSBezierPath()
        basket.move(to: NSPoint(x: 8, y: 12))
        basket.line(to: NSPoint(x: bounds.width - 8, y: 12))
        basket.line(to: NSPoint(x: bounds.width - 16, y: bounds.height - 8))
        basket.line(to: NSPoint(x: 16, y: bounds.height - 8))
        basket.close()
        NSColor(calibratedWhite: 0.55, alpha: 1).setFill()
        basket.fill()

        // Stacked completed slips above the rim.
        for i in 0..<min(basketCount, 4) {
            let slip = NSBezierPath(rect: NSRect(x: 22 + CGFloat(i) * 8, y: bounds.height - 18 - CGFloat(i) * 6, width: 60, height: 16))
            NSColor.white.setFill()
            slip.fill()
            NSColor(calibratedWhite: 0.7, alpha: 1).setStroke()
            slip.stroke()
        }

        // Calm caption when everything is torn off ( Basket empty state shows count ).
        let caption: String
        let locale = AppLocale.current()
        if hangingCount == 0 && basketCount > 0 {
            caption = UIStrings.dayCompleteCaption(doneCount: basketCount, locale: locale)
        } else {
            caption = "cesto (\(basketCount))"
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let size = (caption as NSString).size(withAttributes: attrs)
        (caption as NSString).draw(
            at: NSPoint(x: (bounds.width - size.width) / 2, y: -16),
            withAttributes: attrs
        )
    }

    public override func mouseEntered(with event: NSEvent) {
        // Hover raises the top edges of completed slips like file tabs.
        hoverPeek = true
        needsDisplay = true
    }

    public override func mouseExited(with event: NSEvent) {
        hoverPeek = false
        needsDisplay = true
    }

    public override func mouseDown(with event: NSEvent) {
        // Click = undo top slip (accessibility path); drag-up >60pt also
        // handled by the canvas via onUndoTop.
        onUndoTop?()
    }

    @objc private func emptyBasket() {
        onEmptyBasket?()
    }
}
