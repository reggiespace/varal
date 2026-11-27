import AppKit
import Foundation
import Testing
@testable import VaralKit

/// Widescreen + interaction corrections (v1-app2 lane). Proves in pixels and
/// points that the 3440x1440 yard lays slips out legibly with no overlap,
/// keeps the line clear of the menu bar, and that standard/portrait layouts
/// are unchanged.
@MainActor
private final class YardStubPiece: NSObject, CompanionPiece {
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
func isolatedPieceOrder() -> PieceOrderStore {
    PieceOrderStore(defaults: UserDefaults(suiteName: "varal-tests-\(UUID().uuidString)")!)
}

@MainActor
private func makeYard(
    width: CGFloat = 3440, height: CGFloat = 1440, slipCount: Int = 6
) -> (ClotheslineCanvasView, TaskSlipStore) {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    let store = TaskSlipStore(fileURL: dir.appendingPathComponent("slips.json"))
    let now = Date()
    for i in 0..<slipCount {
        store.pin(TaskSlip(
            timeLabel: String(format: "%02d:00", 9 + i),
            title: "Task \(i)", createdAt: now, pinSlotIndex: i))
    }
    let plans = HolidayPlanStore(fileURL: dir.appendingPathComponent("plans.json"), slipStore: store)
    let pieces: [any CompanionPiece] = [
        YardStubPiece(pieceID: "atmos", side: .leading),
        YardStubPiece(pieceID: "get-long-weekend", side: .trailing),
    ]
    let canvas = ClotheslineCanvasView(
        slipStore: store, planStore: plans, pieceOrder: isolatedPieceOrder(),
        pieces: { pieces }, environment: { nil })
    canvas.frame = NSRect(x: 0, y: 0, width: width, height: height)
    canvas.refresh()
    return (canvas, store)
}

@Suite("YardLayout")
@MainActor
struct YardLayoutTests {
    // MARK: - Line clearance (item 1: clear of the menu bar)

    @Test("line clears the menu bar, legacy anchor without one")
    func lineClearance() {
        #expect(ClotheslineMath.lineY(topSafeInset: 0) == 38)
        #expect(ClotheslineMath.lineY(topSafeInset: 25) == 53)
        #expect(ClotheslineMath.lineY(topSafeInset: 30) == 58)
    }

    // MARK: - Ultrawide gate

    @Test("ultrawide gate is aspect-based")
    func ultrawideGate() {
        #expect(ClotheslineMath.isUltrawide(size: CGSize(width: 3440, height: 1440)) == true)
        #expect(ClotheslineMath.isUltrawide(size: CGSize(width: 2560, height: 1080)) == true)
        #expect(ClotheslineMath.isUltrawide(size: CGSize(width: 1920, height: 1080)) == false)
        #expect(ClotheslineMath.isUltrawide(size: CGSize(width: 1512, height: 982)) == false)
        #expect(ClotheslineMath.isUltrawide(size: CGSize(width: 1080, height: 1920)) == false)
    }

    // MARK: - Fixed-gap rule (design 2026-11-23, Phase 1)

    /// Asserts the gap rule on a landscape layout: pieces a fixed G from the
    /// cluster edges and hanging from the rope at their centre.
    private func expectGapRule(_ layout: YardLayout, width: CGFloat) {
        let leading = layout.pieceFrames.first { $0.id == "atmos" }!.frame
        let trailing = layout.pieceFrames.first { $0.id == "get-long-weekend" }!.frame
        let xs = layout.slipFrames.map(\.frame.minX).sorted()
        let clusterMin = xs.first!
        let clusterMax = xs.last! + ClotheslineMath.slipWidth
        #expect(abs((clusterMin - leading.maxX) - YardGeometry.clusterGap) < 0.001)
        #expect(abs((trailing.minX - clusterMax) - YardGeometry.clusterGap) < 0.001)
        for f in [leading, trailing] {
            let ropeY = YardGeometry.ropeY(x: f.midX, width: width, lineY: layout.line1Y, sag: layout.sag1)
            #expect(abs(f.minY - ropeY) < 0.001)
        }
    }

    @Test("16:9 at rest: pieces sit G from the centred cluster")
    func gapRuleAtRest169() {
        let (canvas, _) = makeYard(width: 1920, height: 1080)
        let layout = canvas.computeLayout()
        expectGapRule(layout, width: 1920)
        // 6 slips shingle at 38pt, centred on the display.
        let xs = layout.slipFrames.map(\.frame.minX).sorted()
        for i in 1..<xs.count {
            #expect(abs((xs[i] - xs[i - 1]) - ClotheslineMath.shingledStep) < 0.001)
        }
        let mid = (xs.first! + xs.last! + ClotheslineMath.slipWidth) / 2
        #expect(abs(mid - 960) < 0.001)
        let leading = layout.pieceFrames.first { $0.id == "atmos" }!.frame
        #expect(leading.minX > 24) // no longer edge-anchored
    }

    @Test("3440 at rest: G rule, side-by-side slips, no overlap")
    func gapRuleAtRestUltrawide() {
        let (canvas, _) = makeYard()
        let layout = canvas.computeLayout()
        expectGapRule(layout, width: 3440)
        #expect(layout.slipFrames.count == 6)
        let xs = layout.slipFrames.map(\.frame.minX).sorted()
        for i in 1..<xs.count {
            #expect(abs((xs[i] - xs[i - 1]) - ClotheslineMath.sideBySidePitch) < 0.001)
        }
        let rects = layout.slipFrames.map(\.frame)
        for i in rects.indices {
            for j in rects.indices where j > i {
                #expect(!rects[i].intersects(rects[j]))
            }
        }
        for f in layout.slipFrames {
            #expect(abs(f.frame.minY - (layout.line1Y + layout.sag1 * 0.925)) < 0.5)
        }
    }

    @Test("16:9 expansion pushes both stacks out by half the growth (zero-cap regression)")
    func expansionPushesStacks169() {
        let (canvas, _) = makeYard(width: 1920, height: 1080)
        let before = canvas.computeLayout()
        let lead0 = before.pieceFrames.first { $0.id == "atmos" }!.frame
        let trail0 = before.pieceFrames.first { $0.id == "get-long-weekend" }!.frame
        let w0 = before.clusterRect.width
        canvas.setClusterExpanded(true)
        let after = canvas.computeLayout()
        let lead1 = after.pieceFrames.first { $0.id == "atmos" }!.frame
        let trail1 = after.pieceFrames.first { $0.id == "get-long-weekend" }!.frame
        let growth = after.clusterRect.width - w0
        #expect(growth > 100)
        #expect(abs((lead0.minX - lead1.minX) - growth / 2) < 0.001)
        #expect(abs((trail1.minX - trail0.minX) - growth / 2) < 0.001)
        expectGapRule(after, width: 1920)
    }

    @Test("expansion clamps the stacks 24pt from the screen edges")
    func expansionClampsAtEdge() {
        let (canvas, _) = makeYard(width: 1280, height: 800, slipCount: 12)
        canvas.setClusterExpanded(true)
        let layout = canvas.computeLayout()
        let leading = layout.pieceFrames.first { $0.id == "atmos" }!.frame
        let trailing = layout.pieceFrames.first { $0.id == "get-long-weekend" }!.frame
        #expect(abs(leading.minX - YardGeometry.edgeMargin) < 0.001)
        #expect(abs(trailing.maxX - (1280 - YardGeometry.edgeMargin)) < 0.001)
        expectGapRule(layout, width: 1280)
    }

    @Test("stack math: one-sided overflow shifts the group off the edge")
    func stackOverflowShift() {
        let s = YardGeometry.landscapeStacks(
            displayWidth: 1000, clusterWidth: 500, leadingWidths: [170, 170], trailingWidths: [])
        #expect(s.leadingXs.count == 2)
        #expect(abs(s.leadingXs[0] - 24) < 0.001)
        #expect(abs(s.leadingXs[1] - 210) < 0.001)
        let expectedClusterMinX: CGFloat = 24 + 356 + 32
        #expect(abs(s.clusterMinX - expectedClusterMinX) < 0.001)
        #expect(s.trailingXs.isEmpty)
    }

    @Test("portrait keeps two ropes and Line 2 slips")
    func portraitUnchanged() {
        let (dell, _) = makeYard(width: 1080, height: 1920, slipCount: 4)
        let pl = dell.computeLayout()
        #expect(dell.layoutMode == .portrait)
        #expect(pl.line2Y - pl.line1Y == 235)
        for f in pl.slipFrames {
            #expect(abs(f.frame.minY - (pl.line2Y + pl.sag2 * 0.925)) < 0.5)
        }
        let leading = pl.pieceFrames.first { $0.id == "atmos" }!.frame
        let trailing = pl.pieceFrames.first { $0.id == "get-long-weekend" }!.frame
        #expect(leading.minX == 24)
        #expect(trailing.maxX == CGFloat(1080 - 24))
    }

    // MARK: - Empty pin stays, others do not shift (review finding)

    @Test("tearing a slip keeps neighbors fixed and leaves an empty pin")
    func tearLeavesPinWithoutShifting() {
        let (canvas, store) = makeYard()
        let before = canvas.computeLayout()
        let beforeBySlot = Dictionary(uniqueKeysWithValues: before.slipFrames.map { ($0.slot, $0.frame) })
        let tornID = before.slipFrames.first { $0.slot == 2 }!.id
        store.tearOff(id: tornID)
        canvas.refresh()
        let after = canvas.computeLayout()
        #expect(after.slipFrames.count == 5)
        for f in after.slipFrames {
            #expect(f.frame == beforeBySlot[f.slot])
        }
        // The torn slot keeps a bare pin on the line.
        #expect(after.emptyPinRects.count == 1)
        let pin = after.emptyPinRects[0]
        #expect(abs(pin.width - 14) < 0.001)
        #expect(abs(pin.midX - (beforeBySlot[2]!.midX)) < 0.5)
    }

    @Test("slot grid is uniform: origins never depend on occupancy")
    func slotGridUniform() {
        #expect(ClotheslineMath.slotOrigins(slots: [true, true, true], step: 38) == [0, 38, 76])
        #expect(ClotheslineMath.slotOrigins(slots: [true, false, true], step: 38) == [0, 38, 76])
        #expect(ClotheslineMath.slotOrigins(slots: [true, false, true], step: 116) == [0, 116, 232])
        #expect(ClotheslineMath.slotTotalWidth(slots: [true, true], origins: [0, 116]) == CGFloat(116 + 104))
    }

    // MARK: - Rope curve matches layout deflection

    @Test("drawn cubic reproduces the 0.925 mid-span deflection")
    func ropeCubicMatchesLayout() {
        let sag: CGFloat = 40
        let a = ClotheslineMath.ropeCubicControlYOffset(sag: sag)
        // Cubic midpoint with C1=(W/3,y+a), C2=(2W/3,y+a): y + 3a/4.
        #expect(abs(a - (4.0 / 3.0) * 0.925 * sag) < 0.001)
        #expect(abs(0.75 * a - ClotheslineMath.midSpanDeflection(sag: sag)) < 0.001)
    }

    // MARK: - Slip follows the pointer (review finding)

    @Test("drag moves the slip with the pointer; 48pt threshold")
    func dragFollowsPointer() {
        let slip = TaskSlip(timeLabel: "09:30", title: "Standup sync", createdAt: Date(), pinSlotIndex: 0)
        let view = TaskSlipView(slip: slip)
        view.frame = NSRect(x: 10, y: 20, width: 104, height: 126)
        var pulls: [CGFloat] = []
        var torn = 0
        view.onPullChanged = { _, pull in pulls.append(pull) }
        view.onTearOff = { _ in torn += 1 }

        func event(_ type: NSEvent.EventType, at p: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(
                with: type, location: p, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        view.mouseDown(with: event(.leftMouseDown, at: NSPoint(x: 50, y: 80)))
        #expect(view.isDragging)
        view.mouseDragged(with: event(.leftMouseDragged, at: NSPoint(x: 50, y: 30)))
        // Pointer moved down 50pt: slip follows (flipped superview default).
        #expect(abs(view.frame.origin.y - 70) < 0.001)
        #expect(abs(view.frame.origin.x - 10) < 0.001)
        #expect(pulls.last == 50)
        view.mouseUp(with: event(.leftMouseUp, at: NSPoint(x: 50, y: 30)))
        #expect(torn == 1)
        #expect(!view.isDragging)
    }

    @Test("sub-threshold release springs back without completing")
    func dragReleaseSpringsBack() {
        let slip = TaskSlip(timeLabel: "09:30", title: "Standup sync", createdAt: Date(), pinSlotIndex: 0)
        let view = TaskSlipView(slip: slip)
        view.frame = NSRect(x: 10, y: 20, width: 104, height: 126)
        var torn = 0
        var lastPull: CGFloat = -1
        view.onPullChanged = { _, pull in lastPull = pull }
        view.onTearOff = { _ in torn += 1 }
        func event(_ type: NSEvent.EventType, at p: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(
                with: type, location: p, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        view.mouseDown(with: event(.leftMouseDown, at: NSPoint(x: 50, y: 80)))
        view.mouseDragged(with: event(.leftMouseDragged, at: NSPoint(x: 50, y: 60)))
        #expect(ClotheslineMath.tearPhase(pull: 20) == .perforation)
        view.mouseUp(with: event(.leftMouseUp, at: NSPoint(x: 50, y: 60)))
        #expect(torn == 0)
        #expect(lastPull == 0)
        #expect(view.frameRotation == 0)
    }

    // MARK: - Basket undo is drag-only (review finding)

    @Test("basket click does nothing; drag-up past 60pt undoes")
    func basketDragOnlyUndo() {
        func events(up: CGFloat) -> (down: NSEvent, drag: NSEvent, upEv: NSEvent) {
            func ev(_ type: NSEvent.EventType, _ y: CGFloat) -> NSEvent {
                NSEvent.mouseEvent(
                    with: type, location: NSPoint(x: 56, y: y), modifierFlags: [],
                    timestamp: 0, windowNumber: 0, context: nil,
                    eventNumber: 0, clickCount: 1, pressure: 1)!
            }
            return (ev(.leftMouseDown, 32), ev(.leftMouseDragged, 32 + up), ev(.leftMouseUp, 32 + up))
        }
        // Short drag: no undo.
        let short = LaundryBasketView()
        short.basketCount = 1
        var undone = 0
        short.onUndoTop = { undone += 1 }
        let s = events(up: 30)
        short.mouseDown(with: s.down)
        short.mouseDragged(with: s.drag)
        #expect(short.currentDragLift == 30)
        short.mouseUp(with: s.upEv)
        #expect(undone == 0)
        // Click without drag: no undo.
        let click = LaundryBasketView()
        click.basketCount = 1
        click.onUndoTop = { undone += 1 }
        let c = events(up: 0)
        click.mouseDown(with: c.down)
        click.mouseUp(with: c.upEv)
        #expect(undone == 0)
        // Full drag-up: undo fires.
        let full = LaundryBasketView()
        full.basketCount = 1
        full.onUndoTop = { undone += 1 }
        let f = events(up: 70)
        full.mouseDown(with: f.down)
        full.mouseDragged(with: f.drag)
        full.mouseUp(with: f.upEv)
        #expect(undone == 1)
    }

    // MARK: - Hit-testing (review finding: the yard must be clickable)

    @Test("finder desktop layer never counts as cover; app windows do")
    func coverageDecision() {
        let finderDesktop = Int(CGWindowLevelForKey(.desktopIconWindow))
        let normal = Int(CGWindowLevelForKey(.normalWindow))
        // Bare desktop: only the Finder layer above us -> uncovered.
        #expect(DesktopYardWindow.isCoveredByLayers([finderDesktop]) == false)
        #expect(DesktopYardWindow.isCoveredByLayers([]) == false)
        // A standard app window above -> covered.
        #expect(DesktopYardWindow.isCoveredByLayers([normal]) == true)
        #expect(DesktopYardWindow.isCoveredByLayers([normal, finderDesktop]) == true)
        // System chrome at/above the dock level never blocks the yard.
        let dock = Int(CGWindowLevelForKey(.dockWindow))
        #expect(DesktopYardWindow.isCoveredByLayers([dock, normal]) == false)
        #expect(DesktopYardWindow.isCoveredByLayers([8, finderDesktop]) == true) // modal alert
    }

    // MARK: - Pixels: legible slips in light and dark (item 1 proof)

    @Test("slip text renders with contrast in both appearances")
    func slipPixelsBothAppearances() {
        func fractions(dark: Bool) -> (ink: Double, paper: Double) {
            let slip = TaskSlip(
                timeLabel: "09:30", title: "Standup sync with the team",
                createdAt: Date(), pinSlotIndex: 0)
            let view = TaskSlipView(slip: slip)
            view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let size = TaskSlipView.slipSize
            view.frame = NSRect(origin: .zero, size: size)
            let img = NSImage(size: size)
            img.lockFocus()
            NSColor.clear.setFill()
            NSRect(origin: .zero, size: size).fill()
            view.draw(view.bounds)
            img.unlockFocus()
            guard let tiff = img.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff) else {
                return (0, 0)
            }
            var ink = 0, paper = 0, total = 0
            for y in 0..<rep.pixelsHigh {
                for x in 0..<rep.pixelsWide {
                    var p = [0, 0, 0, 0, 0]
                    rep.getPixel(&p, atX: x, y: y)
                    let b = (Double(p[0]) + Double(p[1]) + Double(p[2])) / (3.0 * 255.0)
                    total += 1
                    if dark {
                        if b > 0.6 { ink += 1 }      // light text on dark paper
                        if b < 0.3 { paper += 1 }    // dark paper body
                    } else {
                        if b < 0.4 { ink += 1 }      // dark text on white paper
                        if b > 0.9 { paper += 1 }    // white paper body
                    }
                }
            }
            return (Double(ink) / Double(total), Double(paper) / Double(total))
        }
        let light = fractions(dark: false)
        #expect(light.ink > 0.01, "light mode: text pixels must exist, got \(light)")
        #expect(light.paper > 0.5, "light mode: paper must stay white, got \(light)")
        let dark = fractions(dark: true)
        #expect(dark.ink > 0.01, "dark mode: text pixels must exist, got \(dark)")
        #expect(dark.paper > 0.3, "dark mode: paper must go dark, got \(dark)")
    }

    @Test("paper colors are adaptive, not white-on-white")
    func paperColorsAdaptive() {
        let light = TaskSlipView.paperColors(dark: false, weathered: false)
        let dark = TaskSlipView.paperColors(dark: true, weathered: false)
        #expect(light.paper != dark.paper)
        #expect(light.ink != dark.ink)
        #expect(dark.rim != nil)
        #expect(light.rim == nil)
    }

    // MARK: - Localized chrome (review finding)

    @Test("menu bar and settings strings are bilingual")
    func localizedChrome() {
        #expect(UIStrings.settingsTitle(locale: .en) == "Varal Settings")
        #expect(UIStrings.settingsTitle(locale: .pt) == "Ajustes do Varal")
        #expect(UIStrings.displayPickerLabel(locale: .en) == "Display:")
        #expect(UIStrings.displayPickerLabel(locale: .pt) == "Tela:")
        #expect(UIStrings.companionPiecesLabel(locale: .en) == "Companion pieces:")
        #expect(UIStrings.companionPiecesLabel(locale: .pt) == "Peças companheiras:")
        #expect(UIStrings.basketCountLabel(count: 3, locale: .en) == "Basket: 3")
        #expect(UIStrings.basketCountLabel(count: 3, locale: .pt) == "Cesto: 3")
    }
}
