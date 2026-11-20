import AppKit

/// Full-screen transparent desktop window on the single user-selected display.
/// Window level: `CGWindowLevelForKey(.desktopIconWindow) - 1` — strictly
/// behind Finder desktop icons and every app window.
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
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)
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
        // Lightweight single-point z-order query: accept events only when no
        // standard application window covers this exact cursor coordinate.
        // Our desktop window sits below .normalWindow, so if the topmost
        // window at this point is ours, the point is uncovered.
        let top = NSWindow.windowNumber(at: mouse, belowWindowWithWindowNumber: 0)
        ignoresMouseEvents = (top != windowNumber)
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
