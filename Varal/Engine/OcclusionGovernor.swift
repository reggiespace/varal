import AppKit

/// Occlusion, Power & Accessibility Governor (spec §2.6).
///
/// Evaluated strictly on the user's chosen display (`selectedScreen`).
/// The pure `evaluate(...)` core is unit-tested; the `OcclusionGovernor`
/// class wires it to NSWorkspace notifications + a 3.0s coalesced timer.
///
///   isMotionAllowed = !paused && !reduceMotion && !lowPower
///   isDesktopCanvasRenderActive = motion && !fullscreen && visible >= 0.15
///   isPopoverSimulationActive   = motion && popoverShown
public enum GovernorCore: Sendable {
    public struct Decision: Equatable, Sendable {
        public let isMotionAllowed: Bool
        public let isDesktopCanvasRenderActive: Bool
        public let isPopoverSimulationActive: Bool
    }

    public static func evaluate(
        isUserBreezePaused: Bool,
        reduceMotion: Bool,
        lowPowerMode: Bool,
        fullscreenOnSelectedDisplay: Bool,
        visibleFraction: Double,
        popoverShown: Bool
    ) -> Decision {
        let motion = !isUserBreezePaused && !reduceMotion && !lowPowerMode
        return Decision(
            isMotionAllowed: motion,
            isDesktopCanvasRenderActive: motion && !fullscreenOnSelectedDisplay && visibleFraction >= 0.15,
            isPopoverSimulationActive: motion && popoverShown
        )
    }

    /// `visibleFraction >= 0.15` ⇔ occluded by at most 85%.
    public static func isOccluded(visibleFraction: Double) -> Bool {
        visibleFraction < 0.15
    }
}

public final class OcclusionGovernor {
    public var isUserBreezePaused = false {
        didSet { refresh(liveInputs: liveInputs) }
    }
    public var isPopoverShown = false {
        didSet { refresh(liveInputs: liveInputs) }
    }

    public private(set) var decision = GovernorCore.Decision(
        isMotionAllowed: true,
        isDesktopCanvasRenderActive: true,
        isPopoverSimulationActive: false
    )

    public var onChange: ((GovernorCore.Decision) -> Void)?

    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private weak var window: NSWindow?

    /// Test seam: live platform inputs. Production reads the real APIs.
    public var liveInputs: () -> (fullscreen: Bool, visible: Double) = { (false, 1.0) }

    public init(window: NSWindow? = nil) {
        self.window = window
    }

    public func start() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.refreshLive() })
        observers.append(center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.refreshLive() })
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.refreshLive()
        }
        refreshLive()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        let center = NSWorkspace.shared.notificationCenter
        for o in observers { center.removeObserver(o) }
        observers.removeAll()
    }

    public func refreshLive() {
        refresh(liveInputs: liveInputs)
    }

    public func refresh(liveInputs: () -> (fullscreen: Bool, visible: Double)) {
        let live = liveInputs()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let next = GovernorCore.evaluate(
            isUserBreezePaused: isUserBreezePaused,
            reduceMotion: reduceMotion,
            lowPowerMode: lowPower,
            fullscreenOnSelectedDisplay: live.fullscreen,
            visibleFraction: live.visible,
            popoverShown: isPopoverShown
        )
        if next != decision {
            decision = next
            onChange?(next)
        }
    }

    // MARK: - Window coverage on the chosen display

    /// Fraction of the clothesline+basket rects on `screen` not covered by
    /// opaque standard windows above our desktop window. Coalesced 3.0s
    /// polling keeps WindowServer IPC cheap.
    public static func visibleFraction(
        yardRects: [CGRect],
        on screen: NSScreen?,
        desktopWindowNumber: Int
    ) -> Double {
        guard !yardRects.isEmpty else { return 1.0 }
        let options: CGWindowListOption = [.optionOnScreenAboveWindow]
        guard let list = CGWindowListCopyWindowInfo(options, CGWindowID(desktopWindowNumber)) as? [[String: Any]] else {
            return 1.0
        }
        var coveredArea: CGFloat = 0
        var totalArea: CGFloat = 0
        let yardBounds = yardRects.reduce(CGRect.null) { $0.union($1) }
        for info in list {
            guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == Int(CGWindowLevelForKey(.normalWindow)),
                  let alpha = info[kCGWindowAlpha as String] as? Double, alpha > 0.9,
                  let x = boundsDict["X"] as? CGFloat,
                  let y = boundsDict["Y"] as? CGFloat,
                  let w = boundsDict["Width"] as? CGFloat,
                  let h = boundsDict["Height"] as? CGFloat
            else { continue }
            // CGWindow coordinates are bottom-left origin; yardRects are in
            // screen coordinates — intersect in the shared global space after
            // flipping yard rects via the screen height.
            if let screen = screen {
                let flipped = yardRects.map {
                    CGRect(x: $0.origin.x,
                           y: screen.frame.height - $0.origin.y - $0.height,
                           width: $0.width, height: $0.height)
                }
                let winRect = CGRect(x: x, y: y, width: w, height: h)
                for r in flipped {
                    coveredArea += r.intersection(winRect).area
                    totalArea += r.area
                }
            } else {
                _ = yardBounds
            }
        }
        guard totalArea > 0 else { return 1.0 }
        return max(0, min(1, 1 - Double(coveredArea / totalArea)))
    }
}

private extension CGRect {
    var area: CGFloat { width * height }
}
