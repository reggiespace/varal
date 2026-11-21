import AppKit
import QuartzCore

/// Single 1-pin immutable task slip (104×126pt). Handles the 3-phase
/// downward drag gesture: elastic (0–18pt), perforation (18–48pt),
/// snap + 850ms wind-biased falling-leaf flutter (>48pt).
///
/// The slip follows the pointer during the drag (correction v1-app2,
/// matching the wireframe prototype's pointer-captured drag); the canvas
/// adds the matching local rope dip. Paper and ink adapt to the effective
/// appearance (Board 4 night palette in Dark Mode) so task text stays
/// legible instead of rendering white-on-white.
@MainActor
public final class TaskSlipView: NSView {
    public static let slipSize = NSSize(width: 104, height: 126)

    public let slipID: UUID
    private let timeLabel: String
    private let title: String
    private let weathered: Bool
    private var pull: CGFloat = 0
    private var dragStart: NSPoint = .zero
    private var dragStartOrigin: NSPoint = .zero
    private(set) public var isDragging = false

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

    // MARK: - Adaptive paper (pure seam for tests)

    public struct PaperColors: Equatable {
        public let paper: NSColor
        public let border: NSColor
        public let ink: NSColor
        /// Moonlight top-edge rim, drawn only in Dark Mode (Board 4).
        public let rim: NSColor?
    }

    public static func paperColors(dark: Bool, weathered: Bool) -> PaperColors {
        if dark {
            return PaperColors(
                paper: NSColor(calibratedRed: 0x2A / 255.0, green: 0x2A / 255.0, blue: 0x2E / 255.0, alpha: 1),
                border: NSColor(calibratedWhite: 0.45, alpha: 1),
                ink: NSColor(calibratedWhite: 0.78, alpha: 1),
                rim: NSColor(calibratedWhite: 0.8, alpha: 1)
            )
        }
        return PaperColors(
            paper: weathered ? NSColor(calibratedWhite: 0.93, alpha: 1) : NSColor.white,
            border: NSColor(calibratedWhite: 0.75, alpha: 1),
            ink: NSColor.labelColor,
            rim: nil
        )
    }

    private var isDark: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    public override func draw(_ dirtyRect: NSRect) {
        let colors = Self.paperColors(dark: isDark, weathered: weathered)
        let paper = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: weathered ? 7 : 3, yRadius: weathered ? 7 : 3)
        if pull > 48 {
            // Phase C: detached look — full serrated top edge + soft shadow.
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowBlurRadius = 8
            shadow.shadowOffset = NSSize(width: 0, height: -6)
            shadow.shadowColor = NSColor(white: 0, alpha: 0.3)
            shadow.set()
            colors.paper.setFill()
            paper.fill()
            NSGraphicsContext.restoreGraphicsState()
        } else {
            colors.paper.setFill()
            paper.fill()
        }
        colors.border.setStroke()
        paper.lineWidth = weathered ? 1.5 : 1
        paper.stroke()

        // Moonlight rim along the top edge in Dark Mode (Board 4).
        if let rim = colors.rim {
            let rimPath = NSBezierPath()
            rimPath.move(to: NSPoint(x: 6, y: bounds.height - 4))
            rimPath.line(to: NSPoint(x: bounds.width - 6, y: bounds.height - 4))
            rim.setStroke()
            rimPath.lineWidth = 1
            rimPath.stroke()
        }

        // Serrated perforation line grows across the top during Phase B,
        // and spans the full width past the 48pt snap threshold.
        if pull > 18 {
            let progress = pull > 48 ? 1 : min(1, (pull - 18) / 30)
            let line = NSBezierPath()
            let y = bounds.height - 12
            line.move(to: NSPoint(x: 6, y: y))
            line.line(to: NSPoint(x: 6 + (bounds.width - 12) * progress, y: y))
            (isDark ? NSColor.lightGray : NSColor.darkGray).setStroke()
            line.lineWidth = 1
            line.setLineDash([4, 3], count: 2, phase: 0)
            line.stroke()
        }

        let timeAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: colors.ink,
        ]
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: colors.ink,
        ]
        (timeLabel as NSString).draw(at: NSPoint(x: 8, y: bounds.height - 30), withAttributes: timeAttrs)
        let titleRect = NSRect(x: 8, y: 8, width: bounds.width - 16, height: bounds.height - 44)
        (title as NSString).draw(in: titleRect, withAttributes: titleAttrs)
    }

    // MARK: - Drag gesture (pointer-following)

    public override func mouseDown(with event: NSEvent) {
        dragStart = event.locationInWindow
        dragStartOrigin = frame.origin
        isDragging = true
    }

    public override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        let dy = dragStart.y - event.locationInWindow.y // downward positive
        pull = max(0, dy)
        // The slip itself follows the pointer; the canvas adds the local
        // rope dip (0.45 * pull) to the rope curve while dragging.
        let flipped = superview?.isFlipped ?? true
        setFrameOrigin(NSPoint(
            x: dragStartOrigin.x,
            y: dragStartOrigin.y + (flipped ? pull : -pull)))
        // Phase B: tilt 0° -> 10° (frameRotation is in degrees).
        let tilt: CGFloat = pull <= 18 ? 0 : min(10, 10 * (pull - 18) / 30)
        frameRotation = tilt
        needsDisplay = true
        onPullChanged?(slipID, pull)
    }

    public override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        if ClotheslineMath.tearPhase(pull: pull) == .snap {
            onTearOff?(slipID)
        } else {
            // Release in A/B springs back without completing; the canvas
            // re-seats the slip on its pin.
            pull = 0
            frameRotation = 0
            needsDisplay = true
            onPullChanged?(slipID, 0)
        }
        pull = 0
        needsDisplay = true
    }
}
