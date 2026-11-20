import AppKit
import QuartzCore

/// Single 1-pin immutable task slip (104×126pt). Handles the 3-phase
/// downward drag gesture: elastic (0–18pt), perforation (18–48pt),
/// snap + 850ms wind-biased falling-leaf flutter (>48pt).
@MainActor
public final class TaskSlipView: NSView {
    public static let slipSize = NSSize(width: 104, height: 126)

    public let slipID: UUID
    private let timeLabel: String
    private let title: String
    private let weathered: Bool
    private var pull: CGFloat = 0
    private var dragStart: NSPoint = .zero
    private var dragging = false

    /// Phase C completion: slip detached at view-space point.
    public var onTearOff: ((UUID) -> Void)?
    public var onPullChanged: ((UUID, CGFloat) -> Void)?

    public init(slip: TaskSlip) {
        self.slipID = slip.id
        self.timeLabel = slip.timeLabel
        self.title = slip.title
        self.weathered = slip.weatheredDays >= 1
        super.init(frame: NSRect(origin: .zero, size: Self.slipSize))
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    public override func draw(_ dirtyRect: NSRect) {
        // Paper body with deckled/weathered edge when weatheredDays >= 1.
        let paper = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: weathered ? 7 : 3, yRadius: weathered ? 7 : 3)
        (weathered ? NSColor(calibratedWhite: 0.93, alpha: 1) : NSColor.white).setFill()
        paper.fill()
        NSColor(calibratedWhite: 0.75, alpha: 1).setStroke()
        paper.lineWidth = weathered ? 1.5 : 1
        paper.stroke()

        // Serrated perforation line grows across the top during Phase B.
        if pull > 18 {
            let progress = min(1, (pull - 18) / 30)
            let line = NSBezierPath()
            let y = bounds.height - 12
            line.move(to: NSPoint(x: 6, y: y))
            line.line(to: NSPoint(x: 6 + (bounds.width - 12) * progress, y: y))
            NSColor.darkGray.setStroke()
            line.lineWidth = 1
            line.setLineDash([4, 3], count: 2, phase: 0)
            line.stroke()
        }

        let timeAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.labelColor,
        ]
        (timeLabel as NSString).draw(at: NSPoint(x: 8, y: bounds.height - 30), withAttributes: timeAttrs)
        let titleRect = NSRect(x: 8, y: 8, width: bounds.width - 16, height: bounds.height - 44)
        (title as NSString).draw(in: titleRect, withAttributes: titleAttrs)
    }

    // MARK: - Drag gesture

    public override func mouseDown(with event: NSEvent) {
        dragStart = event.locationInWindow
        dragging = true
    }

    public override func mouseDragged(with event: NSEvent) {
        guard dragging else { return }
        let dy = dragStart.y - event.locationInWindow.y // downward positive in flipped space
        pull = max(0, dy)
        // Phase A: local rope dip follows 0.45 * pull (canvas reads pull).
        // Phase B: tilt 0° -> 10° (frameRotation is in degrees).
        let tilt: CGFloat = pull <= 18 ? 0 : min(10, 10 * (pull - 18) / 30)
        frameRotation = tilt
        needsDisplay = true
        onPullChanged?(slipID, pull)
    }

    public override func mouseUp(with event: NSEvent) {
        guard dragging else { return }
        dragging = false
        if ClotheslineMath.tearPhase(pull: pull) == .snap {
            onTearOff?(slipID)
        } else {
            // Release in A/B springs back without completing.
            pull = 0
            frameRotation = 0
            needsDisplay = true
            onPullChanged?(slipID, 0)
        }
        pull = 0
    }
}
