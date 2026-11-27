import AppKit
import Foundation
import Testing
@testable import VaralKit

/// Option A, "slide on the rope" (design 2026-11-23, Phase 2).
@MainActor
private final class DragStubPiece: NSObject, CompanionPiece {
    let pieceID: String
    nonisolated var id: String { pieceID }
    let displayName: String
    let sizeMetrics = PieceSizeMetrics()
    let pinCount = 2
    let preferredSide: PieceAnchorSide
    var environmentalBroadcast: EnvironmentSnapshot? { nil }
    private let view = NSView()
    @MainActor var pieceView: NSView { view }
    init(pieceID: String, side: PieceAnchorSide) {
        self.pieceID = pieceID; self.displayName = pieceID; self.preferredSide = side
    }
}

@MainActor
private func makeLine(
    width: CGFloat = 1920, height: CGFloat = 1080, slipCount: Int = 4
) -> (ClotheslineCanvasView, TaskSlipStore, PieceOrderStore) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = TaskSlipStore(fileURL: dir.appendingPathComponent("slips.json"))
    for i in 0..<slipCount {
        store.pin(TaskSlip(
            timeLabel: String(format: "%02d:00", 9 + i),
            title: "Task \(i)", createdAt: Date(), pinSlotIndex: i))
    }
    let plans = HolidayPlanStore(fileURL: dir.appendingPathComponent("plans.json"), slipStore: store)
    let order = isolatedPieceOrder()
    let pieces: [any CompanionPiece] = [
        DragStubPiece(pieceID: "atmos", side: .leading),
        DragStubPiece(pieceID: "get-long-weekend", side: .trailing),
    ]
    let canvas = ClotheslineCanvasView(
        slipStore: store, planStore: plans, pieceOrder: order,
        pieces: { pieces }, environment: { nil })
    canvas.frame = NSRect(x: 0, y: 0, width: width, height: height)
    canvas.refresh()
    return (canvas, store, order)
}

private func mouse(_ type: NSEvent.EventType, _ p: NSPoint) -> NSEvent {
    NSEvent.mouseEvent(
        with: type, location: p, modifierFlags: [],
        timestamp: 0, windowNumber: 0, context: nil,
        eventNumber: 0, clickCount: 1, pressure: 1)!
}

@Suite("LineDrag")
@MainActor
struct LineDragTests {
    // MARK: - Intent (first 6pt)

    @Test("intent: sideways slides, downward tears, upward is inert")
    func intentClassification() {
        #expect(LineDrag.classifySlipIntent(dx: 3, dy: 2) == .undecided)
        #expect(LineDrag.classifySlipIntent(dx: 6, dy: 0) == .slide)
        #expect(LineDrag.classifySlipIntent(dx: -8, dy: 4) == .slide)   // exactly 2:1
        #expect(LineDrag.classifySlipIntent(dx: 8, dy: 4.1) == .tear)
        #expect(LineDrag.classifySlipIntent(dx: 0, dy: 6) == .tear)
        #expect(LineDrag.classifySlipIntent(dx: 1, dy: -7) == .none)
        #expect(LineDrag.pieceSlideStarts(dx: 0, dy: 5.9) == false)
        #expect(LineDrag.pieceSlideStarts(dx: 4, dy: 4.5) == true)
    }

    @Test("a sideways slip drag slides and never tears, however far it goes")
    func sidewaysNeverTears() {
        let view = TaskSlipView(slip: TaskSlip(timeLabel: "09:30", title: "Gym", createdAt: Date(), pinSlotIndex: 0))
        view.frame = NSRect(x: 10, y: 20, width: 104, height: 126)
        var began = 0, moved: [CGFloat] = [], ended = 0, torn = 0, pulls = 0
        view.onSlideBegan = { _, _, _ in began += 1 }
        view.onSlideMoved = { _, x, _ in moved.append(x) }
        view.onSlideEnded = { _, _ in ended += 1 }
        view.onTearOff = { _ in torn += 1 }
        view.onPullChanged = { _, _ in pulls += 1 }
        view.mouseDown(with: mouse(.leftMouseDown, NSPoint(x: 50, y: 80)))
        view.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: 58, y: 79)))
        // Later the pointer drops far below the 48pt tear line: still a slide.
        view.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: 120, y: 10)))
        view.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: 120, y: 10)))
        #expect(began == 1)
        #expect(moved == [58, 120])
        #expect(ended == 1)
        #expect(torn == 0)
        #expect(pulls == 0)
        #expect(abs(view.frame.origin.y - 20) < 0.001) // the slip didn't move itself
    }

    @Test("an upward first move is inert: no slide, no tear")
    func upwardInert() {
        let view = TaskSlipView(slip: TaskSlip(timeLabel: "09:30", title: "Gym", createdAt: Date(), pinSlotIndex: 0))
        view.frame = NSRect(x: 10, y: 20, width: 104, height: 126)
        var events = 0
        view.onSlideBegan = { _, _, _ in events += 1 }
        view.onTearOff = { _ in events += 1 }
        view.mouseDown(with: mouse(.leftMouseDown, NSPoint(x: 50, y: 80)))
        view.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: 51, y: 90)))
        view.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: 51, y: 10)))
        view.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: 51, y: 10)))
        #expect(events == 0)
    }

    // MARK: - Pure rules

    @Test("rubber band follows at 30% past the legal span")
    func rubberBand() {
        let inside = LineDrag.rubberBanded(150, minX: 100, maxX: 200)
        #expect(inside.x == 150 && !inside.blocked)
        let left = LineDrag.rubberBanded(0, minX: 100, maxX: 200)
        #expect(abs(left.x - 70) < 0.001 && left.blocked)
        let right = LineDrag.rubberBanded(300, minX: 100, maxX: 200)
        #expect(abs(right.x - 230) < 0.001 && right.blocked)
    }

    @Test("reorder permutes occupied slots only; empty pins keep theirs")
    func reorderSkipsEmptyPins() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        // Slot 2 is an empty pin (torn slip in the basket).
        let occupied = [(id: a, slot: 0), (id: b, slot: 1), (id: c, slot: 3), (id: d, slot: 4)]
        let moved = LineDrag.reorderedSlots(occupied: occupied, moving: b, toPosition: 3)
        #expect(moved == [a: 0, c: 1, d: 3, b: 4])
        #expect(!moved.values.contains(2))
    }

    @Test("piece target: crossing the divider switches side")
    func pieceTargetSides() {
        #expect(LineDrag.pieceTarget(centerX: 100, dividerX: 500, remainingLeadingCenters: [200], remainingTrailingCenters: [800]) == .leading(0))
        #expect(LineDrag.pieceTarget(centerX: 300, dividerX: 500, remainingLeadingCenters: [200], remainingTrailingCenters: [800]) == .leading(1))
        #expect(LineDrag.pieceTarget(centerX: 520, dividerX: 500, remainingLeadingCenters: [200], remainingTrailingCenters: [800]) == .trailing(0))
        #expect(LineDrag.pieceTarget(centerX: 900, dividerX: 500, remainingLeadingCenters: [], remainingTrailingCenters: [800]) == .trailing(1))
    }

    @Test("a slot that would push a stack off-screen is blocked")
    func pieceBlockedOffScreen() {
        #expect(LineDrag.pieceArrangementFits(displayWidth: 1920, clusterWidth: 300, leadingWidths: [170], trailingWidths: [170]))
        // Three pieces on one side leave 1000 − 48 − 542 − 32 = 378pt for the cluster.
        #expect(LineDrag.pieceArrangementFits(displayWidth: 1000, clusterWidth: 378, leadingWidths: [170, 170, 170], trailingWidths: []))
        #expect(!LineDrag.pieceArrangementFits(displayWidth: 1000, clusterWidth: 400, leadingWidths: [170, 170, 170], trailingWidths: []))
    }

    @Test("weight dip: 4pt under the piece, fading with distance")
    func dipShape() {
        let dip = YardGeometry.Dip(centerX: 500)
        #expect(abs(dip.depth(at: 500) - 4) < 0.001)
        #expect(dip.depth(at: 528) < 2.5)
        #expect(dip.depth(at: 640) < 0.01)
    }

    // MARK: - Arrangement + persistence

    @Test("arrangement: preferredSide seeds first run; stored order wins after")
    func arrangementResolve() {
        let active: [(id: String, side: PieceAnchorSide)] = [("atmos", .leading), ("get-long-weekend", .trailing)]
        #expect(PieceArrangement.resolve(active: active, stored: nil) == PieceArrangement(leading: ["atmos"], trailing: ["get-long-weekend"]))
        let stored = PieceArrangement(leading: [], trailing: ["atmos", "get-long-weekend"])
        #expect(PieceArrangement.resolve(active: active, stored: stored) == stored)
        // Disabled pieces drop out; a newly enabled one lands on its side.
        let next = PieceArrangement.resolve(
            active: [("get-long-weekend", .trailing), ("gastric-iq", .leading)], stored: stored)
        #expect(next == PieceArrangement(leading: ["gastric-iq"], trailing: ["get-long-weekend"]))
    }

    @Test("pieceOrder round-trips through UserDefaults")
    func pieceOrderRoundTrip() {
        let store = isolatedPieceOrder()
        #expect(store.stored == nil)
        store.save(PieceArrangement(leading: ["b"], trailing: ["a"]))
        #expect(store.stored == PieceArrangement(leading: ["b"], trailing: ["a"]))
    }

    @Test("slip reorder persists to slips.json and keeps the basket slip's pin")
    func storeReorder() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("slips.json")
        let store = TaskSlipStore(fileURL: url)
        let slips = (0..<4).map { TaskSlip(timeLabel: "09:00", title: "T\($0)", createdAt: Date(), pinSlotIndex: $0) }
        slips.forEach { store.pin($0) }
        store.tearOff(id: slips[2].id) // empty pin at slot 2
        #expect(store.reorderHanging(id: slips[0].id, toPosition: 2))
        let reloaded = TaskSlipStore(fileURL: url)
        let slot = { (i: Int) in reloaded.slips.first { $0.id == slips[i].id }!.pinSlotIndex }
        #expect(slot(1) == 0)
        #expect(slot(3) == 1)
        #expect(slot(0) == 3)
        #expect(slot(2) == 2) // basket slip keeps its pin for undo
    }

    // MARK: - Canvas sessions

    @Test("sliding Atmos past the cluster centre re-hangs it trailing, G rule kept")
    func pieceSlideAcrossCluster() {
        let (canvas, _, order) = makeLine()
        let rest = canvas.computeLayout()
        let atmos = rest.pieceFrames.first { $0.id == "atmos" }!.frame
        let divider = rest.pieceDividerX
        canvas.beginPieceSlide(id: "atmos", windowX: 0)
        #expect(canvas.isDragSessionActive)
        // Lifted 4pt while sliding, riding the rope (dip under it).
        let lifted = canvas.computeLayout()
        #expect(lifted.dip != nil)
        canvas.updateSlide(windowX: divider - atmos.midX + 40, time: 0.1)
        let preview = canvas.computeLayout()
        #expect(preview.arrangement == PieceArrangement(leading: [], trailing: ["atmos", "get-long-weekend"]))
        canvas.finishSlide(commit: true)
        #expect(!canvas.isDragSessionActive)
        #expect(order.stored == PieceArrangement(leading: [], trailing: ["atmos", "get-long-weekend"]))
        let after = canvas.computeLayout()
        let a = after.pieceFrames.first { $0.id == "atmos" }!.frame
        let g = after.pieceFrames.first { $0.id == "get-long-weekend" }!.frame
        let clusterMax = after.slipFrames.map(\.frame.maxX).max()!
        #expect(abs((a.minX - clusterMax) - YardGeometry.clusterGap) < 0.001)
        #expect(abs((g.minX - a.maxX) - YardGeometry.stackSpacing) < 0.001)
    }

    @Test("Esc / lost pointer: the piece goes home and nothing changes")
    func pieceSlideCancel() {
        let (canvas, _, order) = makeLine()
        let before = canvas.computeLayout().pieceFrames.map(\.frame.minX)
        canvas.beginPieceSlide(id: "atmos", windowX: 0)
        canvas.updateSlide(windowX: 900, time: 0.1)
        #expect(canvas.computeLayout().arrangement.trailing.contains("atmos")) // live preview moved
        canvas.cancelSlide()
        #expect(order.stored == nil)
        // Home x straight away; the 4pt lift then settles on the pin-on spring.
        #expect(canvas.computeLayout().pieceFrames.map(\.frame.minX) == before)
    }

    @Test("slip reorder: neighbours step one slot toward the vacated one")
    func slipSlideReorders() {
        let (canvas, store, _) = makeLine()
        canvas.setClusterExpanded(true)
        let rest = canvas.computeLayout()
        let ordered = rest.slipFrames.sorted { $0.slot < $1.slot }
        let moving = ordered[1]
        let dx = ordered[3].frame.minX - moving.frame.minX
        canvas.beginSlipSlide(id: moving.id, windowX: 0)
        canvas.updateSlide(windowX: dx, time: 0.1)
        let preview = canvas.computeLayout()
        // Slips 2 and 3 have yielded one slot left in the preview.
        let previewSlot = Dictionary(uniqueKeysWithValues: preview.slipFrames.map { ($0.id, $0.slot) })
        #expect(previewSlot[ordered[2].id] == 1)
        #expect(previewSlot[ordered[3].id] == 2)
        canvas.finishSlide(commit: true)
        let slots = Dictionary(uniqueKeysWithValues: store.hangingSlips.map { ($0.id, $0.pinSlotIndex) })
        #expect(slots[moving.id] == 3)
        #expect(slots[ordered[2].id] == 1)
        #expect(slots[ordered[3].id] == 2)
        #expect(store.basketSlips.isEmpty) // a slide never completes a task
    }

    @Test("blocked: a slip past the cluster edge rubber-bands and returns with no change")
    func slipBlockedPastEdge() {
        let (canvas, store, _) = makeLine()
        canvas.setClusterExpanded(true)
        let rest = canvas.computeLayout()
        let ordered = rest.slipFrames.sorted { $0.slot < $1.slot }
        let last = ordered[3]
        let firstX = ordered[0].frame.minX
        let overshoot: CGFloat = 200
        canvas.beginSlipSlide(id: last.id, windowX: 0)
        canvas.updateSlide(windowX: (firstX - last.frame.minX) - overshoot, time: 0.1)
        let preview = canvas.computeLayout()
        let dragged = preview.slipFrames.first { $0.id == last.id }!.frame
        #expect(abs(dragged.minX - (firstX - overshoot * LineDrag.rubberBand)) < 0.001)
        // Blocked: no neighbour moved.
        for f in preview.slipFrames where f.id != last.id {
            #expect(f.frame == rest.slipFrames.first { $0.id == f.id }!.frame)
        }
        let before = store.hangingSlips.map(\.pinSlotIndex)
        canvas.finishSlide(commit: true)
        #expect(store.hangingSlips.map(\.pinSlotIndex) == before)
    }
}

// MARK: - Regression: Piece view and WKWebView sizing (C12/C13 + AppKit layout)

@Suite("PieceViewSizing")
@MainActor
struct PieceViewSizingTests {
    @MainActor
    private struct TestRig {
        let window: NSWindow
        let canvas: ClotheslineCanvasView
        let slipStore: TaskSlipStore
        let planStore: HolidayPlanStore
        let pieceOrder: PieceOrderStore
        let atmos: AtmosPiece
        let glw: GetLongWeekendPiece
        let menuBar: MenuBarController
        let tempDir: URL

        func cleanup() {
            atmos.setEnabled(false)
            window.orderOut(nil)
            window.contentView = nil
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    private func makeRig(
        width: CGFloat = 1920,
        height: CGFloat = 1080,
        slipCount: Int = 4
    ) -> TestRig {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("varal-piece-sizing-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let slipStore = TaskSlipStore(fileURL: tempDir.appendingPathComponent("slips.json"))
        let now = Date()
        for i in 0..<slipCount {
            slipStore.pin(TaskSlip(
                timeLabel: String(format: "%02d:00", 9 + i),
                title: "Task \(i)",
                createdAt: now,
                pinSlotIndex: i
            ))
        }

        let planStore = HolidayPlanStore(fileURL: tempDir.appendingPathComponent("plans.json"), slipStore: slipStore)
        let pieceOrder = isolatedPieceOrder()

        let atmos = AtmosPiece()
        atmos.setEnabled(true)
        let glw = GetLongWeekendPiece(planStore: planStore)
        let pieces: [any CompanionPiece] = [atmos, glw]

        let canvas = ClotheslineCanvasView(
            slipStore: slipStore,
            planStore: planStore,
            pieceOrder: pieceOrder,
            pieces: { pieces },
            environment: { nil }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = canvas
        canvas.frame = NSRect(x: 0, y: 0, width: width, height: height)

        let menuBar = MenuBarController(
            slipStore: slipStore,
            planStore: planStore,
            allPieces: pieces,
            pieces: { pieces },
            governor: OcclusionGovernor()
        )
        canvas.onLineRearranged = { [weak menuBar] in menuBar?.lineRearranged() }

        canvas.refresh()
        window.layoutIfNeeded()
        canvas.layoutSubtreeIfNeeded()

        return TestRig(
            window: window,
            canvas: canvas,
            slipStore: slipStore,
            planStore: planStore,
            pieceOrder: pieceOrder,
            atmos: atmos,
            glw: glw,
            menuBar: menuBar,
            tempDir: tempDir
        )
    }

    @Test("piece containers and Atmos WKWebView have layout non-zero size through full lifecycle")
    func pieceViewAndWebViewSizingLifecycle() {
        let rig = makeRig(width: 1920, height: 1080)
        defer { rig.cleanup() }

        func assertPieceSizes(message: String) {
            let layout = rig.canvas.computeLayout()

            // 1. Atmos piece container and WKWebView sizing
            guard let atmosFrame = layout.pieceFrames.first(where: { $0.id == rig.atmos.pieceID }) else {
                Issue.record("Missing Atmos frame in layout (\(message))")
                return
            }
            #expect(atmosFrame.frame.width > 0, "Atmos layout width must be > 0 (\(message))")
            #expect(atmosFrame.frame.height > 0, "Atmos layout height must be > 0 (\(message))")

            let atmosView = rig.atmos.pieceView
            #expect(atmosView.frame.size.width == atmosFrame.frame.width, "Atmos view width mismatch (\(message))")
            #expect(atmosView.frame.size.height == atmosFrame.frame.height, "Atmos view height mismatch (\(message))")
            #expect(atmosView.frame.width > 0, "Atmos view width must be > 0 (\(message))")
            #expect(atmosView.frame.height > 0, "Atmos view height must be > 0 (\(message))")

            let webView = atmosView.subviews.first { $0.className.contains("WebView") }
            #expect(webView != nil, "Atmos WKWebView must be mounted (\(message))")
            if let webView {
                #expect(webView.frame.size.width == atmosFrame.frame.width, "Atmos WKWebView width mismatch (\(message))")
                #expect(webView.frame.size.height == atmosFrame.frame.height, "Atmos WKWebView height mismatch (\(message))")
                #expect(webView.frame.width > 0, "Atmos WKWebView width must be > 0 (\(message))")
                #expect(webView.frame.height > 0, "Atmos WKWebView height must be > 0 (\(message))")
            }

            // 2. Get Long Weekend piece container sizing
            guard let glwFrame = layout.pieceFrames.first(where: { $0.id == rig.glw.pieceID }) else {
                Issue.record("Missing GLW frame in layout (\(message))")
                return
            }
            #expect(glwFrame.frame.width > 0, "GLW layout width must be > 0 (\(message))")
            #expect(glwFrame.frame.height > 0, "GLW layout height must be > 0 (\(message))")

            let glwView = rig.glw.pieceView
            #expect(glwView.frame.size.width == glwFrame.frame.width, "GLW view width mismatch (\(message))")
            #expect(glwView.frame.size.height == glwFrame.frame.height, "GLW view height mismatch (\(message))")
            #expect(glwView.frame.width > 0, "GLW view width must be > 0 (\(message))")
            #expect(glwView.frame.height > 0, "GLW view height must be > 0 (\(message))")
        }

        // Phase 1: Initial layout
        assertPieceSizes(message: "Initial layout")

        // Phase 2: Relayout
        rig.canvas.refresh()
        rig.window.layoutIfNeeded()
        rig.canvas.layoutSubtreeIfNeeded()
        assertPieceSizes(message: "After relayout")

        // Phase 3: Size change (e.g. ultrawide 3440x1440)
        rig.window.setContentSize(NSSize(width: 3440, height: 1440))
        rig.canvas.frame = NSRect(x: 0, y: 0, width: 3440, height: 1440)
        rig.canvas.refresh()
        rig.window.layoutIfNeeded()
        rig.canvas.layoutSubtreeIfNeeded()
        assertPieceSizes(message: "After size change to 3440x1440")

        // Size change to portrait 1080x1920
        rig.window.setContentSize(NSSize(width: 1080, height: 1920))
        rig.canvas.frame = NSRect(x: 0, y: 0, width: 1080, height: 1920)
        rig.canvas.refresh()
        rig.window.layoutIfNeeded()
        rig.canvas.layoutSubtreeIfNeeded()
        assertPieceSizes(message: "After size change to portrait 1080x1920")

        // Reset back to landscape 1920x1080
        rig.window.setContentSize(NSSize(width: 1920, height: 1080))
        rig.canvas.frame = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        rig.canvas.refresh()
        rig.window.layoutIfNeeded()
        rig.canvas.layoutSubtreeIfNeeded()
        assertPieceSizes(message: "After return to 1920x1080")

        // Phase 4: Side switch (swap leading and trailing pieces)
        let swapped = PieceArrangement(leading: [rig.glw.pieceID], trailing: [rig.atmos.pieceID])
        rig.pieceOrder.save(swapped)
        rig.canvas.refresh()
        rig.window.layoutIfNeeded()
        rig.canvas.layoutSubtreeIfNeeded()
        assertPieceSizes(message: "After side switch")

        // Phase 5: Rearrangement refresh
        let newOrder = PieceArrangement(leading: [rig.atmos.pieceID, rig.glw.pieceID], trailing: [])
        rig.pieceOrder.save(newOrder)
        rig.canvas.refresh()
        rig.window.layoutIfNeeded()
        rig.canvas.layoutSubtreeIfNeeded()
        assertPieceSizes(message: "After rearrangement refresh")
    }
}

