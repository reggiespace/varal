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
        guard let screen else { return 1.0 }
        var windows: [CGRect] = []
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
            windows.append(CGRect(x: x, y: y, width: w, height: h))
        }
        let primaryHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height ?? screen.frame.height
        let yards = yardRects.map { r in
            CGRect(x: screen.frame.minX + r.minX,
                   y: primaryHeight - screen.frame.maxY + r.minY,
                   width: r.width, height: r.height)
        }
        let totalArea = yards.reduce(CGFloat.zero) { $0 + $1.area }
        guard totalArea > 0 else { return 1.0 }
        let coveredArea = yards.reduce(CGFloat.zero) { area, yard in
            area + unionArea(windows.map { $0.intersection(yard) })
        }
        return max(0, min(1, 1 - Double(coveredArea / totalArea)))
    }

    private static func unionArea(_ rects: [CGRect]) -> CGFloat {
        let valid = rects.filter { !$0.isNull && !$0.isEmpty }
        let xs = Array(Set(valid.flatMap { [$0.minX, $0.maxX] })).sorted()
        guard xs.count > 1 else { return 0 }
        var area: CGFloat = 0
        for i in 0..<(xs.count - 1) {
            let width = xs[i + 1] - xs[i]
            let intervals = valid.filter { $0.minX < xs[i + 1] && $0.maxX > xs[i] }
                .map { ($0.minY, $0.maxY) }.sorted { $0.0 < $1.0 }
            var covered: CGFloat = 0
            var start: CGFloat?
            var end: CGFloat = 0
            for interval in intervals {
                if let current = start, interval.0 > end {
                    covered += end - current
                    start = interval.0
                    end = interval.1
                } else if start == nil {
                    start = interval.0
                    end = interval.1
                } else {
                    end = max(end, interval.1)
                }
            }
            if let start { covered += end - start }
            area += width * covered
        }
        return area
    }
}

private extension CGRect {
    var area: CGFloat { width * height }
}
