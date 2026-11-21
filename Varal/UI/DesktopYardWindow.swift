import AppKit

/// Full-screen transparent desktop window on the single user-selected display.
/// Window level: `CGWindowLevelForKey(.desktopIconWindow)`, ordered directly
/// above the Finder desktop window (correction v1-app2 C11) — strictly
/// behind every standard application window.
///
/// Hit-testing: `ignoresMouseEvents = true` by default so wallpaper clicks,
/// right-clicks, and rubber-band marquee pass through to Finder. A passive
/// global mouse monitor flips it to `false` only while the cursor is inside
/// an active hit polygon AND uncovered by a foreground app window.
@MainActor
public final class DesktopYardWindow: NSWindow {
    public static let selectedScreenKey = "selectedScreenDisplayID"

    public var hitTestPolygons: [CGRect] = []
    private nonisolated(unsafe) var monitor: Any?

    public var selectedScreen: NSScreen {
        get {
            let wanted = UserDefaults.standard.object(forKey: Self.selectedScreenKey) as? UInt32
            if let wanted {
                if let match = NSScreen.screens.first(where: { $0.displayID == CGDirectDisplayID(wanted) }) {
                    return match
                }
            }
            return NSScreen.main ?? NSScreen.screens[0]
        }
    }

    public init(contentView: NSView) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.contentView = contentView
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)))
        ignoresMouseEvents = true
        placeOnSelectedScreen()
        startHitTestMonitor()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    public func placeOnSelectedScreen() {
        let screen = selectedScreen
        setFrame(screen.frame, display: true)
        contentView?.frame = NSRect(origin: .zero, size: screen.frame.size)
        contentView?.needsLayout = true
        if isVisible {
            orderAboveFinderDesktop()
        }
    }

    /// Correction v1-app2 C11: the spec's `desktopIconWindow - 1` level puts
    /// the yard below the Finder desktop window, which then captures every
    /// bare-desktop click — nothing (real or synthetic) can ever drag a
    /// slip. The yard instead sits AT the desktop-icon level and orders
    /// itself directly above the Finder desktop window: transparent regions
    /// still pass clicks through to Finder (icons stay clickable), opaque
    /// pieces receive drags, and every standard app window (`>= .normal`)
    /// continues to cover the yard. The Finder desktop window is resolved
    /// dynamically (never a hardcoded id).
    public func orderAboveFinderDesktop() {
        guard let desktopID = Self.finderDesktopWindowNumber(on: selectedScreen) else { return }
        order(.above, relativeTo: desktopID)
    }

    private static func finderDesktopWindowNumber(on screen: NSScreen) -> Int? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], CGWindowID(0)) as? [[String: Any]] else {
            return nil
        }
        let desktopLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == desktopLevel,
                  (info[kCGWindowOwnerName as String] as? String) == "Finder",
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let x = boundsDict["X"] as? CGFloat,
                  let y = boundsDict["Y"] as? CGFloat,
                  let w = boundsDict["Width"] as? CGFloat,
                  let h = boundsDict["Height"] as? CGFloat,
                  CGRect(x: x, y: y, width: w, height: h).intersects(screen.frame),
                  let id = info[kCGWindowNumber as String] as? Int
            else { continue }
            return id
        }
        return nil
    }

    @objc private func screensChanged() {
        // Fallback to NSScreen.main on disconnect; back to the selected
        // screen if it reconnects (selectedScreen getter handles both).
        placeOnSelectedScreen()
    }

    // MARK: - Dynamic hit-test mask

    private func startHitTestMonitor() {
        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged]
        ) { [weak self] event in
            // The global monitor fires on the main thread.
            MainActor.assumeIsolated { self?.updateMouseTransparency(for: event) }
        }
    }

    private func updateMouseTransparency(for event: NSEvent) {
        let mouse = NSEvent.mouseLocation // global bottom-left origin
        // Canvas polygons use top-left origin relative to the selected
        // screen; convert to global bottom-left space for the hit test.
        let origin = selectedScreen.frame.origin
        let screenTop = selectedScreen.frame.maxY
        let inside = hitTestPolygons.contains { polygon in
            let global = CGRect(
                x: origin.x + polygon.origin.x,
                y: screenTop - polygon.origin.y - polygon.height,
                width: polygon.width, height: polygon.height
            )
            return global.contains(mouse)
        }
        guard inside else {
            if !ignoresMouseEvents { ignoresMouseEvents = true }
            return
        }
        // Fast path: the yard itself is topmost at this point.
        let top = NSWindow.windowNumber(at: mouse, belowWindowWithWindowNumber: 0)
        if top == windowNumber {
            if ignoresMouseEvents { ignoresMouseEvents = false }
            return
        }
        // Slow path (only while hovering yard elements): the point counts
        // as covered only when a standard application window sits above it
        // (`normalWindow <= layer < dockWindow`). The Finder desktop layer
        // the yard intentionally lives under never counts as cover, nor does
        // system chrome at/above the dock level such as the Dock's
        // fullscreen click-catcher (correction v1-app2 C10: comparing against
        // our own window number kept the yard permanently transparent, so
        // nothing was draggable).
        let covered = isCoveredByAppWindow(at: mouse)
        ignoresMouseEvents = covered
    }

    /// Coverage decision over the front-to-back layer list of opaque windows
    /// containing the point (pure seam for tests). Covered only by standard
    /// application windows (`normal <= layer < dock`): the Finder desktop
    /// layer the yard lives under — and system chrome above the dock level
    /// such as the Dock's fullscreen click-catcher — never count as cover.
    public static func isCoveredByLayers(_ layers: [Int]) -> Bool {
        guard let top = layers.first else { return false }
        return top >= Int(CGWindowLevelForKey(.normalWindow))
            && top < Int(CGWindowLevelForKey(.dockWindow))
    }

    /// Front-to-back scan for the first opaque window at `point`, applying
    /// the `isCoveredByLayers` decision to its layer.
    private func isCoveredByAppWindow(at point: NSPoint) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], CGWindowID(0)) as? [[String: Any]] else {
            return true // Fail closed when the WindowServer cannot answer.
        }
        for info in list {
            if (info[kCGWindowNumber as String] as? Int) == windowNumber { continue } // never self-cover
            guard let b = info[kCGWindowBounds as String] as? [String: Any],
                  let x = b["X"] as? CGFloat,
                  let y = b["Y"] as? CGFloat,
                  let w = b["Width"] as? CGFloat,
                  let h = b["Height"] as? CGFloat,
                  CGRect(x: x, y: y, width: w, height: h).contains(point)
            else { continue }
            let alpha = info[kCGWindowAlpha as String] as? Double ?? 1.0
            guard alpha > 0.5 else { continue }
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            return Self.isCoveredByLayers([layer])
        }
        return false
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
