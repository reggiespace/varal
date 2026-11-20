import AppKit
import Foundation
import Testing
@testable import VaralKit

@MainActor
private struct StubPiece: CompanionPiece {
    let pieceID: String
    nonisolated var id: String { pieceID }
    let displayName: String
    let sizeMetrics: PieceSizeMetrics
    let pinCount = 2
    let preferredSide: PieceAnchorSide
    var environmentalBroadcast: EnvironmentSnapshot? { nil }
    @MainActor var pieceView: NSView { NSView() }
}

@Suite("PhysicsAndGovernor")
struct PhysicsAndGovernorTests {
    @Test("equilibrium sag follows the spec formula with 54pt ceiling")
    func sagFormula() {
        // Morning load: 2 big cards (6pt each) + 4 slips + clear.
        let sag = ClotheslineMath.equilibriumSag(
            bigPieceMassUnits: [6, 6], hangingSlipCount: 4, precipitation: .clear)
        #expect(sag == CGFloat(8 + 12 + 18))

        // Moisture weights: snow +5, rain +8.
        #expect(ClotheslineMath.moistureWeight(.clear) == 0)
        #expect(ClotheslineMath.moistureWeight(.snow) == 5)
        #expect(ClotheslineMath.moistureWeight(.rain) == 8)

        // High load clamps at 54pt.
        let heavy = ClotheslineMath.equilibriumSag(
            bigPieceMassUnits: [6, 6], hangingSlipCount: 12, precipitation: .rain)
        #expect(heavy == 54)

        // Empty line: base 8pt only.
        #expect(ClotheslineMath.equilibriumSag(bigPieceMassUnits: [], hangingSlipCount: 0, precipitation: .clear) == 8)

        // Curve math: control point + mid-span deflection.
        #expect(ClotheslineMath.controlPointYOffset(sag: 38) == 1.85 * 38)
        #expect(ClotheslineMath.midSpanDeflection(sag: 38) == 0.925 * 38)
    }

    @MainActor @Test("sag operates over 0..N generic pieces, never naming Atmos/GLW")
    func genericPieces() {
        let empty: [StubPiece] = []
        #expect(ClotheslineMath.equilibriumSag(
            bigPieceMassUnits: empty.map(\.sizeMetrics.massUnits),
            hangingSlipCount: 2, precipitation: .clear) == CGFloat(8 + 9))
        let three = [
            StubPiece(pieceID: "a", displayName: "A", sizeMetrics: .init(), preferredSide: .leading),
            StubPiece(pieceID: "b", displayName: "B", sizeMetrics: .init(), preferredSide: .trailing),
            StubPiece(pieceID: "c", displayName: "C", sizeMetrics: .init(massUnits: 4), preferredSide: .leading),
        ]
        #expect(ClotheslineMath.equilibriumSag(
            bigPieceMassUnits: three.map(\.sizeMetrics.massUnits),
            hangingSlipCount: 0, precipitation: .clear) == CGFloat(8 + 6 + 6 + 4))
    }

    @Test("recoil spring converges (underdamped bounce, settles)")
    func recoilSpring() {
        var s = ClotheslineMath.SpringState(position: 38) // loaded line
        let equilibrium: CGFloat = 33.5 // after tearing one slip (-4.5pt)
        for _ in 0..<600 {
            s = ClotheslineMath.springStep(s, equilibrium: equilibrium, dt: 1.0 / 60.0)
        }
        #expect(abs(s.position - equilibrium) < 0.05)
        #expect(abs(s.velocity) < 0.5)
    }

    @Test("tear-off thresholds: 18pt elastic, 48pt snap")
    func tearThresholds() {
        #expect(ClotheslineMath.tearPhase(pull: 0.5) == .elastic)
        #expect(ClotheslineMath.tearPhase(pull: 18) == .elastic)
        #expect(ClotheslineMath.tearPhase(pull: 18.5) == .perforation)
        #expect(ClotheslineMath.tearPhase(pull: 48) == .perforation)
        #expect(ClotheslineMath.tearPhase(pull: 48.5) == .snap)
    }

    @Test("cluster thresholds and pitch compression")
    func cluster() {
        // Landscape: side-by-side up to 3, shingled beyond.
        #expect(!ClotheslineMath.isClustered(slipCount: 3, portraitLine2: false))
        #expect(ClotheslineMath.isClustered(slipCount: 4, portraitLine2: false))
        // Portrait Line 2: side-by-side up to 5.
        #expect(!ClotheslineMath.isClustered(slipCount: 5, portraitLine2: true))
        #expect(ClotheslineMath.isClustered(slipCount: 6, portraitLine2: true))

        #expect(ClotheslineMath.clusterStep(slipCount: 2, expanded: false, availableWidth: 900, portraitLine2: false) == 116)
        #expect(ClotheslineMath.clusterStep(slipCount: 6, expanded: false, availableWidth: 900, portraitLine2: false) == 38)
        // Expanded compresses so 10+ slips fit the available span.
        #expect(ClotheslineMath.clusterStep(slipCount: 10, expanded: true, availableWidth: 900, portraitLine2: false) == 90)
        // Empty-pin pitch collapses freed slots to 18pt.
        #expect(ClotheslineMath.emptyPinPitch == 18)
    }

    @Test("landscape single-rope vs portrait two-rope geometry")
    func layoutModes() {
        #expect(ClotheslineMath.layoutMode(size: CGSize(width: 1512, height: 982)) == .landscape)
        #expect(ClotheslineMath.layoutMode(size: CGSize(width: 1000, height: 1000)) == .landscape)
        #expect(ClotheslineMath.layoutMode(size: CGSize(width: 900, height: 1440)) == .portrait)
        #expect(ClotheslineMath.lineY(topSafeInset: 0) == 38)
        #expect(ClotheslineMath.lineY(topSafeInset: 40) == 54)
        #expect(ClotheslineMath.secondLineY(firstLineY: 38) == 273)
        #expect(ClotheslineMath.clampedLineY(10, topSafeMargin: 24) == 26)
    }

    @Test("governor matrix: motion, occlusion, fullscreen, low power, popover")
    func governor() {
        // Clear day, popover closed: everything live.
        var d = GovernorCore.evaluate(
            isUserBreezePaused: false, reduceMotion: false, lowPowerMode: false,
            fullscreenOnSelectedDisplay: false, visibleFraction: 1.0, popoverShown: false)
        #expect(d == GovernorCore.Decision(
            isMotionAllowed: true, isDesktopCanvasRenderActive: true, isPopoverSimulationActive: false))

        // >85% covered (visible < 15%) on the chosen display: desktop 0fps.
        d = GovernorCore.evaluate(
            isUserBreezePaused: false, reduceMotion: false, lowPowerMode: false,
            fullscreenOnSelectedDisplay: false, visibleFraction: 0.14, popoverShown: false)
        #expect(d.isDesktopCanvasRenderActive == false)
        #expect(d.isMotionAllowed == true)
        // Boundary: exactly 85% covered stays live.
        d = GovernorCore.evaluate(
            isUserBreezePaused: false, reduceMotion: false, lowPowerMode: false,
            fullscreenOnSelectedDisplay: false, visibleFraction: 0.15, popoverShown: false)
        #expect(d.isDesktopCanvasRenderActive == true)

        // Fullscreen space on the chosen display pauses the desktop canvas.
        d = GovernorCore.evaluate(
            isUserBreezePaused: false, reduceMotion: false, lowPowerMode: false,
            fullscreenOnSelectedDisplay: true, visibleFraction: 1.0, popoverShown: false)
        #expect(d.isDesktopCanvasRenderActive == false)

        // Reduce Motion / Low Power / Pause Breeze each kill all motion…
        let rms = GovernorCore.evaluate(
            isUserBreezePaused: false, reduceMotion: true, lowPowerMode: false,
            fullscreenOnSelectedDisplay: false, visibleFraction: 1.0, popoverShown: true)
        #expect(rms.isMotionAllowed == false)
        #expect(rms.isDesktopCanvasRenderActive == false)
        #expect(rms.isPopoverSimulationActive == false)

        let lps = GovernorCore.evaluate(
            isUserBreezePaused: false, reduceMotion: false, lowPowerMode: true,
            fullscreenOnSelectedDisplay: false, visibleFraction: 1.0, popoverShown: true)
        #expect(lps.isMotionAllowed == false)

        let paused = GovernorCore.evaluate(
            isUserBreezePaused: true, reduceMotion: false, lowPowerMode: false,
            fullscreenOnSelectedDisplay: false, visibleFraction: 1.0, popoverShown: true)
        #expect(paused.isMotionAllowed == false)

        // …while the covered-desktop + open-popover case decouples:
        // desktop stays 0fps, mini mirror still simulates.
        d = GovernorCore.evaluate(
            isUserBreezePaused: false, reduceMotion: false, lowPowerMode: false,
            fullscreenOnSelectedDisplay: false, visibleFraction: 0.0, popoverShown: true)
        #expect(d.isDesktopCanvasRenderActive == false)
        #expect(d.isPopoverSimulationActive == true)
    }

    @MainActor @Test("activePieces filters built-ins without a registry, count-agnostic")
    func activePiecesFiltering() {
        @MainActor struct P: CompanionPiece {
            let pieceID: String
            nonisolated var id: String { pieceID }
            let displayName: String
            let preferredSide: PieceAnchorSide
            let sizeMetrics = PieceSizeMetrics()
            let pinCount = 2
            var environmentalBroadcast: EnvironmentSnapshot? { nil }
            @MainActor var pieceView: NSView { NSView() }
        }
        let builtIn: [any CompanionPiece] = [
            P(pieceID: "atmos", displayName: "Atmos", preferredSide: .leading),
            P(pieceID: "get-long-weekend", displayName: "GLW", preferredSide: .trailing),
        ]
        let both = CompanionPieces.activePieces(from: builtIn, enabledIDs: ["atmos", "get-long-weekend"])
        #expect(both.count == 2)
        let one = CompanionPieces.activePieces(from: builtIn, enabledIDs: ["atmos"])
        #expect(one.map(\.pieceID) == ["atmos"])
        let none = CompanionPieces.activePieces(from: builtIn, enabledIDs: [])
        #expect(none.isEmpty)
    }
}
