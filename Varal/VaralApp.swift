import AppKit
import VaralKit

/// Varal entry point. Menu-bar-anchored (`LSUIElement = true`): owns the
/// single `DesktopYardWindow` on the chosen display + the `NSStatusItem`
/// popover on the main display, and routes `varal://weekend` URLs.
@MainActor
@main
final class VaralApp: NSObject, NSApplicationDelegate {
    private var yardWindow: DesktopYardWindow?
    private var canvas: ClotheslineCanvasView?
    private var menuBar: MenuBarController?
    private var governor: OcclusionGovernor?

    private var slipStore = TaskSlipStore()
    private var planStore: HolidayPlanStore!
    private var atmosPiece: AtmosPiece!
    private var glwPiece: GetLongWeekendPiece!
    private var allPieces: [any CompanionPiece] = []
    private var rolloverCheck = Date()
    private var rolloverTimer: Timer?

    static func main() {
        let app = NSApplication.shared
        let delegate = VaralApp()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        planStore = HolidayPlanStore(slipStore: slipStore)
        atmosPiece = AtmosPiece()
        atmosPiece.setEnabled(enabledPieceIDs().contains(atmosPiece.pieceID))
        glwPiece = GetLongWeekendPiece(planStore: planStore)
        allPieces = [atmosPiece, glwPiece]

        // Sync any T-7d reminders that became due while away.
        planStore.syncReminderSlips(today: HolidayPlanStore.todayString())

        let canvas = ClotheslineCanvasView(
            slipStore: slipStore,
            planStore: planStore,
            pieces: { [weak self] in self?.activePieces() ?? [] },
            environment: { [weak self] in
                guard let self, self.enabledPieceIDs().contains(self.atmosPiece.pieceID) else { return nil }
                return self.atmosPiece.environmentalBroadcast
            }
        )
        self.canvas = canvas

        let yard = DesktopYardWindow(contentView: canvas)
        canvas.onHitRectsChanged = { [weak yard] rects in yard?.hitTestPolygons = rects }
        self.yardWindow = yard

        let governor = OcclusionGovernor(window: yard)
        governor.liveInputs = { [weak self, weak yard] in
            // Evaluated on the main thread by the governor's timer/observers.
            MainActor.assumeIsolated {
                guard let self, let yard else { return (false, 1.0) }
                let fullscreen = self.isFullscreenOnSelectedScreen()
                let visible = OcclusionGovernor.visibleFraction(
                    yardRects: yard.hitTestPolygons,
                    on: yard.selectedScreen,
                    desktopWindowNumber: yard.windowNumber)
                return (fullscreen, visible)
            }
        }
        governor.isUserBreezePaused = UserDefaults.standard.bool(forKey: MenuBarController.pauseBreezeKey)
        governor.onChange = { [weak self] decision in
            // Governor fires on the main thread; hop back to the actor.
            Task { @MainActor [weak self] in self?.applyGovernor(decision) }
        }
        self.governor = governor
        governor.start()

        let menuBar = MenuBarController(
            slipStore: slipStore,
            planStore: planStore,
            allPieces: allPieces,
            pieces: { [weak self] in self?.activePieces() ?? [] },
            governor: governor
        )
        menuBar.onQuickAdd = { [weak canvas, weak menuBar] in canvas?.refresh(); menuBar?.refreshGlyph() }
        menuBar.onPauseToggled = { [weak self] _ in
            self?.governor?.refreshLive()
            self?.canvas?.refresh()
        }
        menuBar.canPlacePiece = { [weak canvas] id, slot in canvas?.canPlacePiece(id, at: slot) ?? true }
        menuBar.onLineRearranged = { [weak canvas] in canvas?.refresh() }
        canvas.onLineRearranged = { [weak menuBar] in menuBar?.lineRearranged() }
        menuBar.install()
        self.menuBar = menuBar

        NotificationCenter.default.addObserver(
            self, selector: #selector(piecesChanged),
            name: .varalPiecesChanged, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(displayChanged),
            name: .varalDisplayChanged, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification, object: nil)

        rolloverTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkRollover() }
        }
        // Opening via varal://weekend while already running.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL))

        yard.orderFrontRegardless()
        yard.orderAboveFinderDesktop()
        canvas.refresh()
        applyGovernor(governor.decision)
    }

    // MARK: - Pieces

    private func activePieces() -> [any CompanionPiece] {
        CompanionPieces.activePieces(from: allPieces, enabledIDs: Array(enabledPieceIDs()))
    }

    private func enabledPieceIDs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: MenuBarController.enabledPiecesKey)
            ?? MenuBarController.defaultEnabledPieces)
    }

    @objc private func piecesChanged() {
        atmosPiece.setEnabled(enabledPieceIDs().contains(atmosPiece.pieceID))
        glwPiece.render()
        canvas?.refresh()
    }

    @objc private func displayChanged() {
        yardWindow?.placeOnSelectedScreen()
        canvas?.refresh()
        governor?.refreshLive()
    }

    // MARK: - Governor application

    private func applyGovernor(_ decision: GovernorCore.Decision) {
        canvas?.isMotionAllowed = decision.isMotionAllowed
        if decision.isDesktopCanvasRenderActive {
            canvas?.rendersAtFullRate = true
            atmosPiece.setSuspended(false)
        } else {
            canvas?.rendersAtFullRate = false
            atmosPiece.setSuspended(true)
        }
        _ = decision.isPopoverSimulationActive
    }

    private func isFullscreenOnSelectedScreen() -> Bool {
        guard let yard = yardWindow else { return false }
        let screenFrame = yard.selectedScreen.frame
        let options: CGWindowListOption = [.optionOnScreenOnly]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        for info in list {
            guard let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == Int(CGWindowLevelForKey(.normalWindow)),
                  let w = bounds["Width"] as? CGFloat,
                  let h = bounds["Height"] as? CGFloat,
                  let x = bounds["X"] as? CGFloat,
                  let y = bounds["Y"] as? CGFloat
            else { continue }
            let r = CGRect(x: x, y: y, width: w, height: h)
            let primaryHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height ?? screenFrame.height
            let screenCGFrame = CGRect(
                x: screenFrame.minX,
                y: primaryHeight - screenFrame.maxY,
                width: screenFrame.width,
                height: screenFrame.height)
            // Fullscreen space on the chosen display: an opaque normal window
            // covering (nearly) the whole screen.
            if r.width >= screenCGFrame.width - 2, r.height >= screenCGFrame.height - 2,
               abs(r.minX - screenCGFrame.minX) < 4,
               abs(r.minY - screenCGFrame.minY) < 4 {
                return true
            }
        }
        return false
    }

    // MARK: - Rollover

    private func checkRollover() {
        let now = Date()
        if RolloverScheduler.shouldRoll(lastCheck: rolloverCheck, now: now) {
            RolloverScheduler.performRollover(on: slipStore)
            planStore.syncReminderSlips(today: HolidayPlanStore.todayString(), now: now)
            glwPiece.render()
            canvas?.refresh()
            menuBar?.refreshGlyph()
        }
        rolloverCheck = now
    }

    @objc private func didWake() {
        checkRollover()
        governor?.refreshLive()
    }

    // MARK: - URL scheme

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { handleVaralURL(url) }
    }

    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        if let s = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
           let url = URL(string: s) {
            handleVaralURL(url)
        }
    }

    private func handleVaralURL(_ url: URL) {
        guard let parsed = URLSchemeRouter.parse(url) else { return }
        planStore.applyWeekendPlan(parsed, today: HolidayPlanStore.todayString())
        glwPiece.render()
        canvas?.refresh()
        menuBar?.refreshGlyph()
    }
}
