# Stage 5: Initial Zoom Out & Inventive Catalyst Review Report

* **Target Document:** [docs/designs/varal.md](./docs/designs/varal.md) (`1..389`, full file)
* **Reviewers:** `egm-zoom-out`, `egm-inventive-catalyst`
* **Date:** 2026-11-18

---

## Part 1: Zoom Out Review (`egm-zoom-out`)

Overall, the design document maintains high-altitude discipline: it bounds V1 scope (no notifications, no multi-monitor mirroring, no dynamic third-party plugin SDK, no inline task editing, and no native weather API key duplication by reusing `atmos.reggiespace.ca` via `WKWebView`). However, four areas introduce speculative V1+ abstractions or redundant layers.

### Finding ZO-1: Speculative "Line 3+" Multi-Rope Reservation in Portrait Layout Mode
* **Severity:** Major
* **Affected Scope:** Section 1 (`Goals`, line 38), Section 2.1 (line 97), Section 2.2.3 (`Portrait Layout Mode`, line 126), Section 3.5 (line 310), and Section 4.5 (`ClotheslineCanvasView.swift`, line 371).
* **Simplicity Rationale:** In Portrait Layout Mode (`height > width`), the design specifies Line 1 for big companion pieces (`activeBigPieces`) and Line 2 for small task slips (`TaskSlipStore`), which solves the narrow aspect ratio problem for V1. However, it also specifies `"Line 3+ (y_line3 = y_line2 + 165pt, rendered on demand): Reserved for future piece types (such as transient clipboard slips)"`. Because V1 only has two piece categories (Big Companion Pieces on Line 1 and Small Task Slips on Line 2) and Clipboard Slips are explicitly a non-V1 future candidate (line 190), designing generalized `Line 3..K` dynamic rope allocation in `ClotheslinePhysicsEngine` and `ClotheslineCanvasView` now violates YAGNI. Portrait mode should strictly model 2 ropes in V1 (Line 1 for big pieces, Line 2 for task slips).

### Finding ZO-2: Unused Protocol Surface on `CompanionPiece` (`updateCadence` & `refreshData()`)
* **Severity:** Major
* **Affected Scope:** Section 2.3.1 (`CompanionPiece` protocol definition, lines 151–162) and Section 4.3 (`CompanionPiece.swift`, line 339).
* **Simplicity Rationale:** The `CompanionPiece` protocol mandates `var updateCadence: TimeInterval { get }` and `func refreshData() async`. Neither V1 implementation uses them:
  * `AtmosPiece` hosts a live `WKWebView` that pushes `EnvironmentSnapshot` events asynchronously via `WKScriptMessageHandler` whenever the web app's internal state changes (lines 167–180).
  * `GetLongWeekendPiece` is driven locally by `HolidayPlanStore` (updated via `varal://weekend?...` deep links and the daily `04:00 AM` `RolloverScheduler`).
  Removing `updateCadence` and `refreshData() async` from `CompanionPiece` eliminates an unused polling contract.

### Finding ZO-3: Redundant `CompanionPieceRegistry` File/Service for a 2-Item Built-In Array
* **Severity:** Nit
* **Affected Scope:** Section 4.2 (`VaralApp.swift`, line 334) and Section 4.3 (`CompanionPieceRegistry.swift`, lines 340–341).
* **Simplicity Rationale:** Since V1 ships only compiled, built-in first-party pieces (`AtmosPiece` and `GetLongWeekendPiece`) and rules out dynamic plugin loading (line 187), creating a dedicated `CompanionPieceRegistry.swift` class just to filter a static 2-element array against a `UserDefaults` `[String]` array (`enabledCompanionPieceIDs`) is unnecessary boilerplate. This filter can live directly on `CompanionPiece` or in `VaralApp`.

### Finding ZO-4: Relative Path Links From `docs/designs/varal.md` to Workspace-Root Wireframe Artifacts
* **Severity:** Nit
* **Affected Scope:** Header (line 6), Section 2.7 (lines 274, 281), and Section 4.1 (lines 320–325).
* **Simplicity Rationale:** Inside `docs/designs/varal.md`, links to `./concepts_brief.md`, `./wireframe_spec.md`, and `./wireframe.html` use `./` instead of `../../`, which fails to resolve to the workspace root where those three files live.

---

## Part 2: Inventive Catalyst Review (`egm-inventive-catalyst`)

### Finding IC-1: Window-Server IPC Contention in Global Mouse Hit-Testing vs. Occlusion Governor
* **Severity:** Major
* **Affected Scope:** Section 2.2.4 (`Dynamic Hit-Test Mask`, lines 128–134) & Section 2.6 (`Occlusion, Power & Accessibility Governor`, lines 255–268).
* **False Compromise:** Accurate Wallpaper-Level Pass-Through (`ignoresMouseEvents` toggling only when unoccluded) **vs.** Zero Idle CPU/IPC Overhead.
  * Section 2.2.4 states that when the cursor enters a hit polygon on `.mouseMoved`, Varal verifies that no standard application window covers that coordinate via `CGWindowListCopyWindowInfo`. Calling `CGWindowListCopyWindowInfo` on `.mouseMoved` performs a synchronous Mach IPC round-trip to `WindowServer` up to 60–120 times per second.
  * Furthermore, because `DesktopYardWindow` sits at `CGWindowLevelForKey(.desktopIconWindow) - 1`, macOS `WindowServer` *already* routes mouse clicks to higher-level standard windows (`NSNormalWindowLevel`) before `DesktopYardWindow` can receive them, even when `DesktopYardWindow.ignoresMouseEvents == false`. `DesktopYardWindow` only competes for events with Finder's desktop layer.
* **Proposed Resolution (Inversion + Preliminary Action):**
  1. **Remove `CGWindowListCopyWindowInfo` from the `.mouseMoved` hit-test path:** Toggle `ignoresMouseEvents` using pure in-memory geometry (`bigPieceHitRects ∪ smallSlipClusterHitRect ∪ laundryBasketHitRect`), and use standard `NSTrackingArea` (`mouseEntered:` / `mouseExited:`) on `DesktopYardWindow` to gate the `150ms` hover-cluster expansion (which macOS only fires when the window is unoccluded at the cursor position).
  2. **Event-Driven + Low-Frequency Coalesced Occlusion Check in `OcclusionGovernor`:** Run `CGWindowListCopyWindowInfo(.optionOnScreenAboveWindow, DesktopYardWindow.windowNumber)` only on `NSWorkspace.didActivateApplicationNotification`, `NSWorkspace.activeSpaceDidChangeNotification`, and a coalesced `2.0s–5.0s` timer while `isSimulationActive == true`.

### Finding IC-2: Unthrottled `WKWebView` Process Inside `AtmosPiece` Under Desktop Occlusion
* **Severity:** Major
* **Affected Scope:** Section 2.3.2 (`Atmos Web-Hosted Piece`, lines 166–182) & Section 2.6 (`Occlusion, Power & Accessibility Governor`, lines 255–268).
* **False Compromise:** Zero-Duplication Web Re-use (`atmos.reggiespace.ca/?mode=piece` in `WKWebView`) **vs.** Zero Background GPU/Battery Drain when Occluded (`0fps` governor guarantee).
  * When `isSimulationActive == false` (`>85%` occlusion, Fullscreen Space, Low Power Mode, Reduce Motion, or Pause Breeze), Varal pauses its native `CADisplayLink` to `0fps`. However, `AtmosPiece` embeds an out-of-process `WKWebView` whose `WebContent` and `GPU` helper processes will continue running web animations at 60fps behind covering windows unless explicitly suspended.
* **Proposed Resolution (Beforehand Cushioning + Self-Service):**
  * When `isSimulationActive` transitions to `false`, `AtmosPiece` suspends `WKWebView` rendering (e.g., hiding/freezing the web view behind a cached static snapshot or pausing its animation loop while keeping periodic telemetry).
  * Cache the last valid `EnvironmentSnapshot` across brief network drops and observe `NWPathMonitor` / `NSWorkspace.didWakeNotification` to reload the `WKWebView` automatically when connectivity returns.

### Finding IC-3: Popover "Mini Clothesline Mirror" vs. Full-Screen Desktop Redraw Coupling
* **Severity:** Nit
* **Affected Scope:** Section 2.6 (`Occlusion, Power & Accessibility Governor`, lines 259–267).
* **False Compromise:** Coupling full-screen `DesktopYardWindow` rendering to `|| isMenuBarPopoverShown` wakes the full-screen desktop canvas and weather particle emitters at 60fps behind an opaque fullscreen/maximized window just to animate the small `NSPopover` mirror.
* **Proposed Resolution (Segmentation):** When `visibleFraction(on: selectedScreen) < 0.15` and `isMenuBarPopoverShown == true`, run only the scalar sag/recoil solver for the popover view while keeping `DesktopYardWindow` canvas redraws and full-screen particle emitters paused at `0fps`.

### Finding IC-4: Spatial Clothespin Slot Continuity Across App Restarts (`pinSlotIndex`)
* **Severity:** Nit
* **Affected Scope:** Section 2.4.3 (`Three-Phase Downward Tear-Off & Undo`, lines 210–211) & Section 2.5 (`Data Models`, lines 216–225).
* **False Compromise:** Tearing a slip leaves an empty clothespin at that $x$-coordinate, and undoing flies the slip back to its empty clothespin. Without a persisted `pinSlotIndex: Int` on `TaskSlip`, restarting Varal or pinning new tasks while slips are in `.inBasket` loses which empty clothespin slot belongs to which `.inBasket` slip prior to the `04:00 AM` rollover.
* **Proposed Resolution (Preliminary Action):** Add `pinSlotIndex: Int` to `TaskSlip` so both `.hanging` and `.inBasket` slips hold their deterministic clothespin slot on the line until the `04:00 AM` rollover archives `.inBasket` slips and compacts the remaining `.hanging` slots.
