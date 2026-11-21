# Design Document: Varal — Native macOS Ambient Clothesline & Companion Ecosystem

* **Author:** Reginaldo dos Santos
* **Date:** 2026-11-16
* **Status:** Finalized
* **Companion Artifacts:** [concepts_brief.md](../product/concepts_brief.md) | [wireframe_spec.md](./wireframe_spec.md) | [wireframe.html](./wireframe.html)

---

## 1. Problem Statement, Overview & Goals

### 1.1 The Problem

Desktop task utilities and ambient widgets on macOS fall into two categories:

1. **Intrusive Productivity Apps:** Standard task managers use floating windows, red dock badges, streak counters, and notification banners that compete for attention while the user is trying to work. They treat daily tasks as a database backlog of checkboxes rather than a physical, finite set of commitments for today.
2. **Static or Disconnected Desktop Widgets:** Native macOS Sonoma/Sequoia desktop widgets sit on a rigid grid, share no physical relationship with one another, and fade into monochrome blocks without tactile completion mechanics. Existing companion web apps by the author—specifically **Atmos** (`atmos.reggiespace.ca`) for live local weather and **Get Long Weekend** (`getlongweekend.ca`) for planning holiday bridge days—live inside browser tabs that disappear as soon as the user closes the tab.

There is no calm, physical desktop space on macOS that unifies daily tasks, live local weather, and upcoming vacation countdowns at wallpaper level without notifications, checkboxes, or window clutter.

### 1.2 Overview

**Varal** ("clothesline" in Portuguese) is a native macOS desktop application that lives on a single user-selected display (`selectedScreenID`, defaulting to `NSScreen.main`) at the spatial layer between the desktop wallpaper and Finder desktop icons (`CGWindowLevelForKey(.desktopIconWindow)`, ordered directly above the Finder desktop window per correction v1-app2 C11). In landscape orientation, it stretches a single catenary clothesline from the left edge to the right edge of the chosen screen; on tall/narrow portrait displays, it switches automatically to **Portrait Layout Mode**, stringing two parallel clotheslines stacked vertically (like a real multi-rope apartment varal).

Three types of items hang from the clothesline on clothespins and respond to one shared physics simulation:

1. **Atmos (Big Piece — 2 Clothespins, Left Anchor):** A live weather companion card that hosts `atmos.reggiespace.ca` inside an embedded `WKWebView` (running the Atmos web app's compact "piece mode") rather than re-implementing the sky scene natively. Varal holds no weather API key. Instead, the Atmos web app exports what it sees and renders via a `WKScriptMessageHandler` bridge: whenever its internal weather state changes, it posts an `EnvironmentSnapshot` (wind speed/direction, precipitation state, temperature, and solar/lunar phase) to the native host, which drives the shared clothesline physics. If the `WKWebView` fails to load or is offline, the clothesline physics fall back to a baseline breeze (`6 km/h`).
2. **Get Long Weekend (Big Piece — 2 Clothespins, Right Anchor):** A two-state companion piece for `getlongweekend.ca`:
   * **State A (Discovery):** Before a vacation plan is hung, the card acts as a calm, removable product card showing the next regional holiday bridge opportunity and linking to `getlongweekend.ca`. It is never advertising inventory and can be removed by the user at any time.
   * **State B (Personal Countdown):** When the user selects their vacation blocks on `getlongweekend.ca` and triggers `"Hang on Varal"` (`varal://weekend?start=...&end=...&plan=...`), Varal switches the card idempotently into a personal countdown to the next upcoming vacation block in the plan. As each block approaches, the card pins a physical tear-off reminder slip (such as a PTO request reminder) onto the clothesline without triggering a notification. Re-hanging the same `plan` updates the card and its slips idempotently without duplication.
3. **Daily Task Slips (Small Pieces — 1 Clothespin Each, Center Cluster):** Individual DayPad-inspired paper slips showing a time and a short title. Slips are immutable paper with no checkboxes and no inline text editing. To conserve horizontal space on laptop displays, 4 or more slips group into a shingled horizontal cluster that fans out after a `150ms` cursor hover dwell, sliding `Atmos` and `Get Long Weekend` toward the screen edges along the line. Completing a task is a physical gesture: the user drags the slip downward past `48pt` to tear it off its clothespin. The line recoils upward as the weight is removed, the empty clothespin stays on the line, and the torn slip flutters into a laundry basket (`cesto`) in the bottom-right corner of the desktop. Dragging a slip out of the basket back toward the line undoes completion. Tearing is the only completion verb: unfinished slips remain on the line past the `04:00 AM` rollover with slightly weathered paper edges.

Because application windows cover the desktop during normal work, a menu-bar icon (`NSStatusItem`) renders a micro-silhouette of the line and opens a popover containing a mini clothesline mirror, a quick-add task input, interactive mini-slip tear-off, and a **Pause Breeze** toggle. Varal never requests notification permissions, never displays badges, and never interrupts the user.

### 1.3 Goals

* **Wallpaper-Level Spatial Integration (`desktopIconWindow - 1` on One Chosen Display):** Keep the clothesline strictly behind all application windows and Finder desktop icons on the single screen selected by the user in Settings (defaulting to the main display; e.g., an always-uncovered secondary portrait monitor in a dual-screen setup), passing mouse clicks through to Finder everywhere outside the active bounding polygons of the cards, task cluster, and laundry basket.
* **Adaptive Landscape & Portrait Multi-Rope Layout:** Render a single full-width clothesline on landscape displays (`width >= height`), and automatically switch to two stacked parallel clotheslines on portrait displays (`height > width`)—Line 1 for big companion pieces and Line 2 for small task slips—while keeping the laundry basket at the bottom of the chosen screen so torn slips flutter down the full vertical drop.
* **Tactile, Checkbox-Free Task Lifecycle:** Enforce immutable paper slips where downward tear-off (`>48pt` pull) into the bottom-right laundry basket is the sole completion mechanism, drag-back from the basket is the undo mechanism, and unfinished slips persist across the `04:00 AM` rollover with weathered edges.
* **Shared Environmental Physics Driven by Atmos:** Drive catenary rope sag (`Δy`), compound pendulum sway, precipitation accumulation, and day/dusk/night lighting across all hanging pieces from Atmos's live weather and solar telemetry.
* **Idempotent Multi-Block Deep-Link Contract for Get Long Weekend:** Register and handle `varal://weekend?start=...&end=...&plan=...` so multi-block vacation plans transition the Get Long Weekend card from State A (Discovery) to State B (Countdown) idempotently, counting down to the next block and spawning per-block reminder slips without notifications.
* **Battery, Occlusion & Accessibility Compliance:** Automatically pause all 60fps sway and weather particle loops when the clothesline is `>85%` occluded by opaque windows, when a Fullscreen Space is active, when Low Power Mode is active, when macOS **Reduce Motion** (`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`) is enabled, or when the user toggles **Pause Breeze**.
* **6-Board Grayscale Wireframe Specification & Prototype:** Provide deterministic layout, hierarchy, motion kinematics, and gesture contracts across all 6 canonical wireframe boards (`wireframe_spec.md` and `wireframe.html`).

### 1.4 Non-Goals

* **No Notifications, Badges, Sounds, or Streaks:** Varal will never call `UNUserNotificationCenter`, display red unread counters, play completion sound effects, or track productivity streaks.
* **No Multi-List Project Management or Inline Editing:** No folders, tags, priorities, subtasks, recurring rules, or inline text editing on pinned slips (to fix a typo, tear the slip off and pin a new one).
* **No Automatic Task Retirement:** Varal will never auto-archive or delete an unfinished task slip at midnight.
* **No Multi-Monitor Mirroring or Second Instances:** Varal renders on one chosen display at a time—never mirrored or duplicated across multiple monitors simultaneously, and never floating above active application windows.
* **No Changes to `atmos.reggiespace.ca` or `getlongweekend.ca` Web Repositories in This Repo:**
  * The compact "piece mode" view and `window.webkit.messageHandlers.varalEnvironment.postMessage(...)` bridge inside the Atmos web app are an external dependency owned by the `atmos.reggiespace.ca` repository.
  * The `"Hang on Varal"` Share menu button and its clipboard fallback when Varal is not installed are an external dependency owned by the `getlongweekend.ca` repository.
* **No Final Color Art in the Wireframe Deliverable:** The wireframe specification and HTML prototype remain strictly grayscale to validate structure, hierarchy, and physics first.

---

## 2. Technical Plan

### 2.1 System Architecture & Data Flow

Varal is structured as a menu-bar-anchored macOS application (`LSUIElement = true`) that owns a single full-screen desktop window (`DesktopYardWindow`) placed on the user's chosen display (`selectedScreen`, defaulting to `NSScreen.main`, fallback to `NSScreen.main` on disconnect) while the `NSStatusItem` and its companion `NSPopover` remain anchored in the menu bar on the main display.

```text
+---------------------------------------------------------------------------------------------------+
|                                     EXTERNAL INPUT SOURCES                                        |
|                                                                                                   |
|  [atmos.reggiespace.ca in WKWebView (Piece Mode)]    [getlongweekend.ca Share Menu (External Dep)] |
|   (Posts EnvironmentSnapshot via                      (Fires varal://weekend?start=...&end=...     |
|    WKScriptMessageHandler; no native API key)          &plan=...)                                  |
+--------------------|-------------------------------------------------------|----------------------+
                     v                                                       v
+---------------------------------------------------------------------------------------------------+
|                                   VARAL CORE STATE & CONTROLLERS                                  |
|                                                                                                   |
|  +-------------------------------+   +---------------------------------------------------------+  |
|  | AtmosPiece (WKWebView Bridge) |   | URLSchemeRouter & HolidayPlanStore                      |  |
|  | - Hosts atmos.reggiespace.ca  |   | - Parses varal://weekend?start=...&end=...&plan=...     |  |
|  | - Receives JS postMessage ->  |   | - Replaces multi-block VacationPlan idempotently        |  |
|  |   EnvironmentSnapshot         |   | - Computes next upcoming block countdown                |  |
|  | - Offline/error -> nil        |   | - Spawns per-block reminder TaskSlip at T-7d            |  |
|  |   (Physics uses calm breeze)  |   +----------------------------+----------------------------+  |
|  +---------------+---------------+                                |                               |
|                  |                                                v                               |
|                  |                   +---------------------------------------------------------+  |
|                  |                   | TaskSlipStore & RolloverScheduler (04:00 AM)            |  |
|                  |                   | - Immutable TaskSlip records (.hanging vs. .inBasket)   |  |
|                  |                   | - 04:00 AM rollover & [Limpar cesto]: deletes .inBasket |  |
|                  |                   |   slips; keeps .hanging slips and increments            |  |
|                  |                   |   weatheredDays at 04:00 AM                             |  |
|                  |                   +----------------------------+----------------------------+  |
|                  v                                                v                               |
|  +---------------------------------------------------------------------------------------------+  |
|  | ClotheslinePhysicsEngine & Governor                                                         |  |
|  | - Layout Mode: Landscape (1 rope) vs. Portrait (2 stacked parallel ropes: Line 1 Big        |  |
|  |   Pieces, Line 2 Task Slips)                                                                |  |
|  | - Catenary sag per rope: Δy_sag = min(54pt, 8 + Σ massUnits_on_rope + moistureWeight)       |  |
|  | - Governor: evaluates window coverage on chosen display only; pauses CADisplayLink (0fps)   |  |
|  |   on >85% occlusion, Fullscreen Space on chosen display, Low Power Mode, or Reduce Motion   |  |
|  +---------------+-------------------------------------------------------------+---------------+  |
+------------------|-------------------------------------------------------------|------------------+
                   v                                                             v
+--------------------------------------------------+   +--------------------------------------------+
| DesktopYardWindow (Chosen Display Only)          |   | MenuBarController (Main Display Menu Bar)  |
| - Level: CGWindowLevelForKey(.desktopIcon) - 1   |   | - Live micro-line glyph [⊶ N]              |
| - Dynamic Hit-Test Mask (ignoresMouseEvents)     |   | - Mini Clothesline Mirror                  |
| - Landscape (1 line) or Portrait (2 lines)       |   | - Quick-Add immutable task input           |
| - Bottom Laundry Basket (cesto)                  |   | - Mini-slip tear-off & Pause Breeze toggle |
+--------------------------------------------------+   +--------------------------------------------+
```

### 2.2 Desktop Window Management, Display Selection & Portrait Layout Mode (`DesktopYardWindow`)

1. **Single Chosen Display ("One Yard, User-Selected Screen"):**
   * Varal renders a single `DesktopYardWindow` instance on one screen chosen by the user in Settings (`selectedScreenDisplayID: CGDirectDisplayID`, defaulting to `NSScreen.main`). There is no multi-monitor mirroring and no second window instance. If the user selects an always-uncovered secondary portrait monitor, Varal lives entirely on that display; if that monitor is unplugged (`NSApplication.didChangeScreenParametersNotification`), `DesktopYardWindow` automatically falls back to `NSScreen.main` and moves back to `selectedScreenDisplayID` when reconnected.
   * Window level is set to `NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)))`, ordered directly above the Finder desktop window (correction v1-app2 C11; the legacy `- 1` level let the Finder desktop window capture every bare-desktop click, making drag-to-tear impossible).
   * Window collection behavior is configured as `[.canJoinAllSpaces, .stationary, .ignoresCycle]`, with `isOpaque = false`, `backgroundColor = .clear`, and `hasShadow = false`.
2. **Top Safe-Margin Anchoring & Flipped Coordinate Space:**
   * The macOS menu bar and Varal's `NSStatusItem` remain on the main display.
   * `ClotheslineCanvasView` overrides `isFlipped -> true` so all rope anchors (`y_line1`, `y_line2`), piece coordinates, and downward catenary sag offsets (`+Δy_sag`) operate in a top-left origin coordinate space (`y = 0` at the top edge of `selectedScreen`).
   * On the chosen display, top rope anchoring computes `topSafeInset = selectedScreen.frame.maxY - selectedScreen.visibleFrame.maxY` (accounting for the menu bar or camera notch if present on that screen, or `0pt` on a secondary display without a menu bar) and places Line 1 at `y_line1 = topSafeInset > 0 ? topSafeInset + 28pt : 38pt` from the top edge of `selectedScreen` (correction v1-app2: the legacy `max(topSafeInset, 24pt) + 14pt` sat the rope right under the menu bar on the 3440×1440 display; menu-less displays keep the legacy `38pt` anchor pixel-identical).
3. **Landscape Mode vs. Portrait Layout Mode (Multi-Rope Varal):**
   * `DesktopYardWindow` inspects the aspect ratio of `selectedScreen.frame`:
     * **Landscape Mode (`width >= height`):** Renders a single edge-to-edge catenary rope at `y_line1`. Leading big pieces hang on the left, small task slips hang in the center shingled cluster, and trailing big pieces hang on the right.
     * **Portrait Layout Mode (`height > width`):** On tall, narrow displays, a single horizontal rope cannot fit big companion pieces and task slips side-by-side. Varal automatically switches to a stacked two-rope layout (like a traditional multi-line apartment varal):
       * **Line 1 (`y_line1 = topMargin + 14pt`):** Dedicated to **Big Companion Pieces** (`activeBigPieces`, e.g., `Atmos` and `Get Long Weekend` hanging side-by-side across Line 1).
       * **Line 2 (`y_line2 = y_line1 + 235pt`):** Dedicated to **Small Task Slips** (`TaskSlipStore` plus any Get Long Weekend reminder slips). Because Line 2 spans the full width of the portrait display without competing with big cards, up to 5 task slips hang side-by-side before shingling, and hover-expanding the cluster fans slips across Line 2 without needing to push the big pieces on Line 1.
       * **Bottom Laundry Basket & Full Vertical Drop:** The **Laundry Basket (`cesto`)** stays anchored at the bottom-right corner of the portrait display (`bottomMargin + 64pt`). When a slip is torn off Line 2, its falling-leaf flutter trajectory uses the entire vertical drop of the tall display down into the basket.
4. **Dynamic Hit-Test Mask (Point Z-Order & Finder Pass-Through Over N Pieces):**
   * By default, `DesktopYardWindow.ignoresMouseEvents = true`, allowing all clicks, right-clicks, and rubber-band marquee selections on the desktop wallpaper and Finder icons to pass straight through to Finder.
   * A passive global mouse monitor (`NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged])`) converts the cursor position into `selectedScreen`'s flipped view coordinates and performs in-memory geometry hit-testing against the union of active hit polygons across the rendered lines:
     * `bigPieceHitRects: [CGRect]` (computed dynamically from `activeBigPieces` on Line 1)
     * `smallSlipClusterHitRect: CGRect` (computed from the small-slip cluster on Line 1 in Landscape, or Line 2 in Portrait)
     * `laundryBasketHitRect: CGRect` (bottom-right basket `cesto` + protruding completed slip tabs on `selectedScreen`)
   * When the cursor enters any active hit polygon, `DesktopYardWindow` queries `NSWindow.windowNumber(at: cursorScreenPoint, belowWindowWithWindowNumber: 0)`—a lightweight single-point z-order query—to confirm that no standard application window (`windowLevel >= NSWindow.Level.normal`) is covering that exact cursor coordinate. Only when the cursor is inside an active hit polygon **and** uncovered by a foreground application window does `ignoresMouseEvents` flip to `false`; leaving the polygon or moving onto a covering foreground window restores `ignoresMouseEvents = true`.
   * Because Varal runs as a background `LSUIElement = true` process, `ClotheslineCanvasView` registers its hover `NSTrackingArea` with `[.mouseEnteredAndExited, .activeAlways, .inVisibleRect]` to gate the `150ms` hover-cluster dwell timer when `ignoresMouseEvents == false`.

### 2.3 Companion Piece Contract & Extension Boundaries (`CompanionPiece`)

1. **First-Party Module Protocol (Decoupled from Physics & Layout):**
   * Every big piece on the clothesline is a built-in, first-party module conforming to a shared `CompanionPiece` contract containing only the properties consumed by layout, physics, and environmental broadcast:

   ```swift
   enum PieceAnchorSide: String, Codable {
       case leading   // Hangs to the left of the center small-slip cluster
       case trailing  // Hangs to the right of the center small-slip cluster
   }

   struct PieceSizeMetrics: Equatable {
       let width: CGFloat         // Standard big piece: 170pt
       let height: CGFloat        // Standard big piece: 205pt
       let massUnits: CGFloat     // Sag contribution in points (default: 6.0pt)
   }

   protocol CompanionPiece: Identifiable {
       var pieceID: String { get }                     // e.g., "atmos", "get-long-weekend"
       var displayName: String { get }
       var sizeMetrics: PieceSizeMetrics { get }
       var pinCount: Int { get }                       // Standard big piece: 2 clothespins
       var preferredSide: PieceAnchorSide { get }
       var environmentalBroadcast: EnvironmentSnapshot? { get } // Optional wind/precip/solar output
       @MainActor var pieceView: NSView { get }        // Mounted by ClotheslineCanvasView without downcasting
   }
   ```

   * **Zero Hardcoding in Layout, Physics & Interaction:** `ClotheslinePhysicsEngine`, `DesktopYardWindow`, hit-testing, and cluster-expansion offset math operate strictly over an ordered collection `activeBigPieces: [any CompanionPiece]` filtered directly against the user's enabled piece IDs in `UserDefaults` (`enabledCompanionPieceIDs: [String]`, without a separate registry class). The physics and interaction layer never hardcodes a count of two big pieces (`0..N` enabled pieces are supported) and never references `Atmos` or `Get Long Weekend` by name. If any active piece provides a non-nil `environmentalBroadcast`, the physics engine consumes its wind, moisture, and solar phase; if no piece broadcasts weather (for example, if the user disables `Atmos` or its `WKWebView` fails to load), the line falls back to a baseline breeze (`6 km/h`, `0pt` moisture, system clock day/night).
2. **Atmos Web-Hosted Piece, `WKScriptMessageHandler` Bridge & Occlusion Throttling:**
   * Rather than re-implementing the Atmos sky scene natively or embedding a weather API key inside Varal, `AtmosPiece` hosts `https://atmos.reggiespace.ca/?mode=piece` inside a lightweight `WKWebView`. To prevent the retain cycle caused by `WKUserContentController.add(_:name:)`, `AtmosPiece` registers a weak `WKScriptMessageHandler` proxy (`WeakScriptMessageHandler`) named `"varalEnvironment"`.
   * Whenever the Atmos web app updates its internal weather or solar/lunar state, it posts a JSON payload via `window.webkit.messageHandlers.varalEnvironment.postMessage(...)` matching `EnvironmentSnapshot`:

   ```swift
   struct EnvironmentSnapshot: Codable, Equatable {
       let temperatureCelsius: Double
       let windSpeedKmh: Double
       let windDirectionDegrees: Double
       let precipitation: PrecipitationState // .clear | .rain | .snow
       let solarPhase: SolarPhase            // .morning | .day | .dusk | .night
   }
   ```

   * **Origin Validation & Crash Recovery:** `WKNavigationDelegate` restricts main-frame navigation strictly to `https://atmos.reggiespace.ca`, and `userContentController(_:didReceive:)` validates `message.frameInfo.securityOrigin.host == "atmos.reggiespace.ca"` before decoding `EnvironmentSnapshot`. When decoded, `AtmosPiece` updates `environmentalBroadcast` (caching it as the last-known-good snapshot for up to `30 minutes` across brief network drops). If macOS terminates the background `WebContent` process under memory pressure, `webViewWebContentProcessDidTerminate(_:)` triggers an automatic reload with exponential backoff.
   * **WebView Suspension Under Desktop Occlusion & Network Self-Healing:** When `OcclusionGovernor` transitions `isDesktopCanvasRenderActive` to `false` (or under Reduce Motion / Pause Breeze), `AtmosPiece` captures a static `takeSnapshot` image, hides/removes the live `WKWebView` from active rendering, and dispatches a JS pause event so `WebContent` and `GPU` helper processes drop to `0%` CPU/GPU. `AtmosPiece` also observes `NWPathMonitor` and `NSWorkspace.didWakeNotification` to reload the web view automatically when network connectivity returns after an offline period; if no fresh or cached snapshot is available, `environmentalBroadcast` becomes `nil` and physics falls back to the baseline breeze.
   * **External Dependency Boundary (`atmos.reggiespace.ca`):** Implementing the compact `?mode=piece` layout and calling `window.webkit.messageHandlers.varalEnvironment.postMessage(...)` inside the Atmos web app is an external dependency owned by the Atmos repository, not a Varal code deliverable.
3. **User-Chosen Line Composition:**
   * All big pieces are optional. The default first-run configuration enables `["atmos", "get-long-weekend"]`, but the user can toggle individual built-in pieces on or off in Settings (`UserDefaults` key `enabledCompanionPieceIDs: [String]`). Nothing ever hangs on the clothesline that the user did not choose to keep enabled.
4. **Strict V1 Scope Limits & Future Extension Axes:**
   * **V1 Implementation:** Pieces ship strictly as compiled, built-in first-party modules behind `CompanionPiece`.
   * **Explicitly Out of Scope:** Dynamic plugin loading (`.bundle` / `.dylib`), third-party pieces, a public plugin API or SDK, and per-piece configuration UI in Settings beyond a simple on/off toggle.
   * **Future First-Party Candidates (Examples Only, Not V1 Commitments):**
     * *Big Piece Axis (`CompanionPiece`):* **Gastric IQ** (meal-tracking companion app; a future first-party companion card that slots into `activeBigPieces` without changing layout or physics code).
     * *Small Piece Axis (`SmallSlipSource`):* **Clipboard Slips** (transient small paper slips pinned alongside daily task slips and Get Long Weekend reminder slips, sharing the same 1-pin shingled cluster and downward tear-off gesture).

### 2.4 Catenary Physics, Hover Cluster & Tear-Off Kinematics (`ClotheslinePhysicsEngine`)

1. **Per-Line Catenary Rope Sag & Recoil:**
   * Each clothesline $L_k$ is rendered as a quadratic Bezier approximation of a catenary curve between `(0, y_k)` and `(W, y_k)` with control point `(W / 2, y_k + 1.85 * Δy_sag(k))` (producing a mid-span curve deflection of $0.925 \times \Delta y_{\text{sag}}(k)$).
   * Equilibrium sag for rope $L_k$ is computed from the items hanging on $L_k$ plus weather moisture and clamped to a physical ceiling of `54pt` so high task counts never sag into the line below or the basket:
     $$\Delta y_{\text{sag}}(k) = \min\left(54\text{pt},\; 8\text{pt} + \sum_{p \in \text{BigPieces}(L_k)} p.\text{sizeMetrics.massUnits} + (4.5\text{pt} \times N_{\text{slips}}(L_k)) + W_{\text{moisture}}\right)$$
     where $W_{\text{moisture}}$ is `0pt` (clear), `5pt` (snow), or `8pt` (rain). In Landscape mode, all items hang on $L_1$; in Portrait mode, $L_1$ sags according to the weight of the big companion pieces while $L_2$ sags independently according to the day's task load.
   * When a small slip is pinned onto its line or torn off, $\Delta y_{\text{sag}}(k)$ transitions to its new equilibrium via an underdamped spring solver ($\omega_0 = 18\text{ rad/s}$, damping ratio $\zeta = 0.35$), producing the pin-on bounce and the upward rope recoil on tear-off. Upward displacement on $L_1$ is clamped to `y >= topSafeMargin + 2pt`.
2. **Dwell-Gated Shingled Small-Slip Cluster & Empty Pin Compression:**
   * In Landscape mode (`1` rope), leading big pieces (`preferredSide == .leading`) hang to the left of the center cluster and trailing big pieces (`preferredSide == .trailing`) hang to the right. **Ultrawide Landscape (correction v1-app2, aspect `width/height >= 2.0`):** big pieces are placed at proportional thirds of the display width (leading piece center at `W/3`, trailing at `2W/3`) instead of the screen edges, and slips lay side-by-side at full `116pt` pitch while they fit the span between the thirds-placed pieces; only beyond fit do they shingle or compress. Standard 16:9 landscape and Portrait keep the legacy edge anchors and count thresholds pixel-identical. In Portrait mode (`2` ropes), big pieces hang on Line 1 and small slips occupy the full width of Line 2.
   * Slips in `.inBasket` leave an empty wooden clothespin at their `pinSlotIndex` position on the rope. Slot positions form a uniform grid fixed by `pinSlotIndex`, so tearing a slip never moves its neighbors (correction v1-app2); only the pin graphic at an empty slot collapses to the bare pin pitch, centered where the slip's pin was, expanding back to the full slip only if the slip is dragged back from the basket (undo).
   * When the number of active `.hanging` slips is at or below the unclustered threshold (`<= 3` in Landscape, `<= 5` on Line 2 in Portrait), small slips (`104×126pt` each) hang side-by-side with `12pt` spacing (`116pt` pitch).
   * Beyond that threshold, `.hanging` slips group into a shingled horizontal fan in the center zone with a `38pt` horizontal step so each slip's header and leading title text remain visible.
   * Entering `smallSlipClusterHitRect` starts a `150ms` dwell timer. If the cursor remains inside the zone for `150ms`, the cluster transitions to `clusterExpanded = true`, fanning the slips out with a dynamic horizontal pitch of `min(116pt, availableClusterWidth / max(1, N_hangingSlips))` (guaranteeing that even `10+` weathered slips fan out within the available center span without pushing big pieces off-screen) and—when on a shared Landscape rope—translating all leading big pieces outward toward the left screen edge and all trailing big pieces outward toward the right screen edge along the catenary curve. Exiting the zone collapses the cluster after `250ms`.
3. **Three-Phase Downward Tear-Off & Undo:**
   * Slips are **immutable paper**—clicking or double-clicking a slip never opens an inline text editor.
   * Dragging a slip downward along $\Delta y_{\text{pull}}$ executes three deterministic phases:
     * **Phase A (`0pt < Δy_pull <= 18pt` — Elastic Stretch):** The slip follows the pointer during the drag (correction v1-app2, matching the pointer-captured prototype drag) while the local rope point dips by $0.45 \times \Delta y_{\text{pull}}$ (capped at `+28pt` extra sag). Releasing the mouse springs the slip back to rest without completing.
     * **Phase B (`18pt < Δy_pull <= 48pt` — Perforation Unzip):** A serrated dashed tear line progresses across the top of the slip beneath the clothespin jaws; the slip tilts slightly (`0° -> 10°`). Releasing returns the slip to rest without completing.
     * **Phase C (`Δy_pull > 48pt` — Snap, Recoil & Flutter):** The slip detaches from its clothespin. The empty wooden clothespin remains clipped on the line at that `pinSlotIndex` (`18pt` bare pin graphic), the rope rebounds upward (`-4.5pt` sag), and the detached slip follows an `850ms` wind-biased falling-leaf trajectory into the bottom-right **Laundry Basket (`cesto`)**.
   * **Undo Gesture:** Hovering over the bottom-right basket raises the top edges of completed slips inside the basket. Dragging any slip upward `>60pt` flies the slip back to its empty clothespin at `pinSlotIndex` on the line and restores `4.5pt` of rope sag. Undo is drag-only (correction v1-app2): clicking the basket never undoes.

### 2.5 Data Models, Rollover Weathering & Deep-Link Contract

```swift
enum SlipState: Codable, Equatable {
    case hanging
    case inBasket(completedAt: Date)
}

struct TaskSlip: Identifiable, Codable, Equatable {
    let id: UUID
    let timeLabel: String          // Parsed leading "HH:mm" token, or creation time "HH:mm" if omitted (e.g., "T-7d" for GLW)
    let title: String              // Immutable once pinned
    let createdAt: Date
    var pinSlotIndex: Int          // Preserves clothespin slot on the rope across restarts while .hanging or .inBasket
    var state: SlipState           // .hanging | .inBasket(completedAt: Date) — deleted on rollover / [Limpar cesto]
    var weatheredDays: Int         // Incremented at 04:00 AM rollover while .hanging
    var sourcePlanID: String?      // Non-nil if spawned by a Get Long Weekend block
    var sourceBlockStart: String?  // ISO-8601 date of the associated vacation block
}

struct VacationBlock: Codable, Equatable {
    let startDate: String          // ISO-8601 "YYYY-MM-DD"
    let endDate: String            // ISO-8601 "YYYY-MM-DD"
}

struct VacationPlan: Codable, Equatable {
    let planID: String             // Deterministic ID from varal://weekend?...&plan=<id>
    var blocks: [VacationBlock]    // Sorted chronologically by startDate
    var updatedAt: Date
}
```

1. **Quick-Add Parsing, `04:00 AM` Daily Rollover, Manual Basket Clear (`[Limpar cesto]`) & Paper Weathering:**
   * **Quick-Add Time Prefix Parsing:** When the user submits a string in the menu-bar quick-add input, `TaskSlipStore` checks for an optional leading 24-hour `HH:mm` token (e.g., `"17:30 Buy coffee beans"` -> `timeLabel = "17:30"`, `title = "Buy coffee beans"`). If no leading time token is present (`"Buy coffee beans"`), `timeLabel` defaults to the current local `HH:mm` timestamp at the moment the slip is pinned.
   * **Slot Preservation & Deletion on Clear/Rollover:** While a slip is `.hanging` or `.inBasket`, its `pinSlotIndex` reserves its deterministic clothespin position on the rope. At `04:00 AM` local time (or on wake from sleep if `04:00 AM` was crossed while asleep)—or when the user manually clicks the **`[Limpar cesto]`** (`Empty basket`) action on the laundry basket:
     * All slips in `.inBasket` are **deleted** from `slips.json` (there is no `.archived` state), removing them from the basket and removing their empty clothespins from the line while compacting the remaining `.hanging` `pinSlotIndex` values (`0..<N`). The rollover check is in-memory only (known limitation v1-app2): if the app is quit when `04:00 AM` passes, no catch-up rollover fires on the next launch — basket slips persist until the next boundary while running, and hanging slips miss that day's weathering.
     * At the `04:00 AM` rollover, all slips still in `.hanging` **remain on the line** and increment `weatheredDays += 1`. Slips with `weatheredDays >= 1` render with a subtly deckled/weathered paper border and softened corner texture. Varal never auto-completes or retires an unfinished slip.
2. **Get Long Weekend Deep-Link Contract & Multi-Block Lifecycle:**
   * **State A (Local Discovery Card):** When no active `VacationPlan` with upcoming blocks exists, `GetLongWeekendPiece` renders deterministic local discovery copy (`"Turn 1 PTO day into 4 days off"` in EN / `"Transforme 1 dia de folga em 4"` in PT) with a button that opens `https://getlongweekend.ca` via `NSWorkspace.shared.open(_:)`, requiring zero network calls in Varal. Big pieces are shown or hidden strictly via the Settings checkboxes (`enabledCompanionPieceIDs`), never by downward tear-off.
   * **URL Registration:** Varal registers the `varal` URL scheme (`CFBundleURLSchemes = ["varal"]`) and handles incoming links matching:
     `varal://weekend?start=<YYYY-MM-DD[,YYYY-MM-DD...]>&end=<YYYY-MM-DD[,YYYY-MM-DD...]>&plan=<plan_id>`
   * **Authoritative Idempotent State B Replacement & Bilingual Reminder Slip Template:**
     * When `URLSchemeRouter` receives `varal://weekend?start=...&end=...&plan=<id>`, the comma-separated `start` and `end` lists represent the **complete authoritative list of blocks** for `planID = <id>`. `HolidayPlanStore` replaces `blocks` for `<id>` in place with the newly parsed sorted list (computing total days off directly from `startDate..endDate`).
     * The Get Long Weekend card transitions from **State A (Discovery)** to **State B (Personal Countdown)** and displays the countdown to the **next upcoming block** (`first block where endDate >= today`). Once a block's `endDate` passes, the card automatically advances to count down to the subsequent block in `blocks` (or returns to State A (Discovery) if all blocks in the plan are in the past).
     * For each block in `blocks`, when the local date reaches `T-7 days` (or immediately on sync if `0 <= T <= 7 days`), Varal checks whether a `TaskSlip` with matching `(sourcePlanID, sourceBlockStart)` already exists; if not, it pins a single reminder slip onto the clothesline without triggering a notification, formatted in the active app locale:
       * **English (`EN`):** `timeLabel = "T-7d"`, `title = "Long weekend (\(startDate) – \(endDate)) — confirm time off"`
       * **Portuguese (`PT`):** `timeLabel = "T-7d"`, `title = "Feriadão (\(startDate) – \(endDate)) — confirmar folga"`
     * On re-hang of `<id>`, any existing `.hanging` reminder slip for `sourcePlanID == <id>` whose `sourceBlockStart` is no longer present in the updated `blocks` (or is now `> 7 days` in the future) is removed, while matching blocks preserve their existing slip idempotently.
   * **External Dependency Boundary (`getlongweekend.ca`):**
     * Implementing the `"Hang on Varal"` item in the `getlongweekend.ca` web Share menu (which invokes `varal://weekend?start=...&end=...&plan=...` and falls back to copying the plan URL with a one-line explanation of Varal if the custom scheme handler does not respond) is an external web dependency outside Varal's repository.

### 2.6 Occlusion, Power & Accessibility Governor

The `ClotheslinePhysicsEngine` evaluates window coverage and fullscreen state **strictly on the user's chosen display (`selectedScreen`)**—so if the user places Varal on an uncovered secondary portrait monitor while working in fullscreen or maximized apps on their primary display, Varal continues swaying uninterrupted on the portrait monitor.

To avoid high-frequency `WindowServer` IPC overhead, `OcclusionGovernor` computes `visibleFraction(on: selectedScreen)` via `CGWindowListCopyWindowInfo([.optionOnScreenAboveWindow], DesktopYardWindow.windowNumber)` only on `NSWorkspace.didActivateApplicationNotification`, `NSWorkspace.activeSpaceDidChangeNotification`, and a low-frequency coalesced timer (`3.0s` interval while active). Furthermore, it decouples full-screen desktop rendering from the lightweight menu-bar popover mirror:

```swift
isMotionAllowed = !isUserBreezePaused
               && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
               && !ProcessInfo.processInfo.isLowPowerModeEnabled

isDesktopCanvasRenderActive = isMotionAllowed
                           && !isFullscreenSpaceActive(on: selectedScreen)
                           && (visibleFraction(on: selectedScreen) >= 0.15)

isPopoverSimulationActive   = isMotionAllowed && isMenuBarPopoverShown
```

* When `isDesktopCanvasRenderActive == false`, `DesktopYardWindow`'s `CADisplayLink` / frame timer is invalidated (`0fps`), `AtmosPiece` suspends its embedded `WKWebView` animation loop behind a static snapshot, weather particle emitters stop, and all hanging pieces on the desktop rest at their static equilibrium angles along the catenary curve.
* If the desktop is covered (`isDesktopCanvasRenderActive == false`) and the user opens the menu-bar popover (`isPopoverSimulationActive == true`), only the lightweight 1D sag/recoil math for the popover's mini clothesline runs—keeping full-screen desktop canvas redraws and particle emitters paused at `0fps`.
* When macOS **Reduce Motion** (`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`) is enabled—or when the user clicks **Pause Breeze**—pinning or tearing off a task updates the line sag and basket count immediately via a clean opacity/position fade without pendulum oscillation, bounce, or falling particles.

### 2.7 Six-Board Grayscale Wireframe Architecture (`wireframe_spec.md` & `wireframe.html`)

To verify layout, spatial hierarchy, and gesture mechanics prior to production Swift/AppKit implementation, the design includes two synchronized wireframe artifacts:

1. **[wireframe_spec.md](./wireframe_spec.md):** Annotated ASCII blueprint diagrams and kinematic specifications for all 6 boards:
   * **Board 1 — Morning Desktop:** Full line (`Atmos` + 4-slip shingled center cluster + `Get Long Weekend`), Finder desktop icons in front of the right rope margin, bottom-right `cesto`, and macOS Dock.
   * **Board 2 — Tear-Off Gesture Mid-Action:** Multi-phase pull vector (`0–18pt` stretch, `18–48pt` perforation unzip, `>48pt` snap + upward rope recoil + wind-biased flutter into basket + drag-back undo).
   * **Board 3 — Desktop Covered by Browser Window + Menu-Bar Popover Open:** Foreground browser covering 80% of the desktop (`0fps` desktop governor active), left edge of `Atmos` and bottom-right basket peeking in margins, and the `NSStatusItem` popover open with the Mini Clothesline mirror and quick-add input.
   * **Board 4 — Night State:** Low-glare charcoal wireframe palette (`#171716`), `Atmos` in lunar mode (`9°C`, `3 km/h` calm breeze), slow linear satellite pass along a dashed trajectory, and halftone firefly rings near the basket.
   * **Board 5 — End of Day:** All task slips torn off into the overflowing basket, empty clothespins resting on a taut line (`Δy = 14pt`), calm `"Dia concluído · 4 feitas"` caption, and `04:00 AM` rollover rule preserving any unfinished slips with weathered edges.
   * **Board 6 — First-Run / Empty State & Get Long Weekend Two-State Matrix:** Bare line with one dashed onboarding slip and side-by-side specification of Get Long Weekend **State A (Discovery Card)** vs. **State B (Multi-Block Personal Countdown)** synced idempotently via `varal://weekend?start=...&end=...&plan=...`.
2. **[wireframe.html](./wireframe.html):** Self-contained grayscale HTML/CSS/SVG interactive prototype implementing the 6-board state switcher, quadratic Bezier catenary sag formula, dwell-gated cluster expansion, pointer-captured downward drag-to-tear (`>48px` threshold), basket click/drag undo, weather spill toggles (`Breeze`, `Rain`, `Snow`), and `Get Long Weekend` State A / State B switching.

### 2.8 Corrections Log (v1-app2 lane, 2026-11-20)

Review findings from the running app, answered here as the authoritative amendments (this section wins where it narrows an earlier clause):

* **C1 — Line clearance (amends §2.2.2):** `y_line1 = topSafeInset > 0 ? topSafeInset + 28pt : 38pt`. Displays with a menu bar clear it by `28pt`; menu-less displays (e.g. the portrait Dell) keep the legacy `38pt` anchor pixel-identical.
* **C2 — Ultrawide yard (amends §2.4.2):** on landscape displays with aspect `width/height >= 2.0`, big pieces sit at proportional thirds (leading center `W/3`, trailing center `2W/3`) and slips lay side-by-side at full pitch while they fit the inter-piece span, shingling/compressing only beyond fit. 16:9 landscape and Portrait keep the legacy geometry.
* **C3 — Slot-stable layout (amends §2.4.2):** slip slot positions form a uniform grid fixed by `pinSlotIndex`; the empty-pin graphic (bare `14pt` pin centered where the slip's pin was) stays on the line and no other slip moves. The cubic rope is drawn with control points `(W/3, y+1.2333·sag)` / `(2W/3, y+1.2333·sag)`, exactly reproducing the spec quadratic (`0.925` mid-span deflection) so slip tops sit on the visible rope.
* **C4 — Pointer-following drag (amends §2.4.3 Phase A):** the slip itself follows the pointer during the drag while the rope dips `0.45 × pull` (capped `+28pt`); past `48pt` the slip shows the full-width serration plus drop shadow.
* **C5 — Drag-only undo (amends §2.4.3):** basket undo is an upward drag `>60pt` only; clicking the basket (or any click shortcut) does nothing.
* **C6 — Suspended Atmos still image (confirms §2.2/§2.3.2):** while suspended the card shows the last `takeSnapshot` still image over the hidden `WKWebView`.
* **C7 — Bilingual chrome:** Settings title (`Varal Settings` / `Ajustes do Varal`), Display picker (`Display:` / `Tela:`), companion pieces (`Companion pieces:` / `Peças companheiras:`), basket count (`Basket: N` / `Cesto: N`).
* **C8 — Dark Mode paper (confirms Board 4):** slips render the night palette (`#2A2A2E` paper, light ink, moonlight rim) in Dark Mode so task text stays legible.
* **C10 — Click-through hit-testing (amends §2.2.4):** the transparency flip compares the topmost opaque window's *layer* against `.normalWindow` instead of our own window number. The Finder desktop layer the yard lives under never counts as cover, nor does system chrome at or above the dock level, so slips and basket are actually draggable; standard app windows still block.
* **C11 — Window level (amends §2.2.1):** the yard sits AT `CGWindowLevelForKey(.desktopIconWindow)` (not minus one), ordered directly above the dynamically-resolved Finder desktop window. One level below, the Finder desktop window captures every bare-desktop click and no drag — real or synthetic — can ever reach the yard, defeating tear-off and undo entirely. Opaque pieces still yield to every standard app window; transparent regions still pass clicks through to Finder, so icons stay clickable.
* **C9 — Rollover limitation (§2.5.1):** no persisted last-rollover state exists; a quit-through-`04:00 AM` misses the rollover until the next boundary while running.

---

## 3. Alternatives Considered

### 3.1 Full-Screen Illustrated Background with Wooden Posts vs. Transparent Edge-to-Edge Overlay
* **Alternative:** Render an opaque full-screen sky, green hills, and two vertical wooden posts supporting the clothesline (replacing the user's macOS desktop wallpaper).
* **Decision:** Rejected by author.
* **Technical Rationale:** Rendering a full-screen opaque sky behind the clothesline duplicates the sky scene already rendered inside the **Atmos** companion card frame and forces users to abandon their personal macOS desktop wallpaper. Using a transparent edge-to-edge clothesline overlay at `CGWindowLevelForKey(.desktopIconWindow)` (ordered above the Finder desktop window per correction v1-app2 C11) preserves the user's wallpaper while making **Atmos** the single source of sky and weather telemetry whose wind, rain, snow, and nocturnal fireflies spill onto the physical clothesline and neighboring cards.

### 3.2 Scratch-Out In-Place (Literal DayPad) vs. Downward Tear-Off Into Basket
* **Alternative:** Complete tasks by scribbling over the paper slip with the mouse cursor while leaving the crossed-out slip hanging on the clothesline all day (matching the physical DayPad scratch-off pad).
* **Decision:** Rejected by author.
* **Technical Rationale:** Leaving completed slips hanging on the clothesline throughout the day prevents horizontal space recovery and eliminates the physical weight-relief feedback loop where the catenary rope rebounds upward as tasks are removed. Downward tear-off (`>48pt` pull) into the bottom-right laundry basket (`cesto`) preserves DayPad's tactile, checkbox-free paper aesthetic while giving the clothesline a clear visual progression from a heavy morning load to a taut, empty end-of-day line.

### 3.3 Hard 5-Task Daily Cap vs. Dwell-Gated Shingled Cluster
* **Alternative:** Enforce a hard limit of 5 task slips on the clothesline and block the user from pinning a 6th slip until an existing slip is torn off.
* **Decision:** Rejected by author.
* **Technical Rationale:** While a small daily task load is encouraged, a hard software block frustrates users when Get Long Weekend automatically pins a PTO reminder slip onto a line that already holds 5 daily tasks. Grouping small slips into a shingled horizontal cluster that fans out after a `150ms` cursor hover dwell (and sliding surrounding big pieces toward the screen edges on a shared landscape rope) preserves horizontal legibility without artificially rejecting new slips.

### 3.4 Hardcoded Two-Card Layout vs. First-Party `CompanionPiece` Contract
* **Alternative:** Hardcode `Atmos` on the left and `Get Long Weekend` on the right directly inside `ClotheslinePhysicsEngine` and `DesktopYardWindow` hit-testing.
* **Decision:** Rejected by author.
* **Technical Rationale:** Coupling the physics, catenary sag math, and hit-testing layer to two named cards makes it impossible for a user to hide a card they do not use or for future first-party companion pieces (such as **Gastric IQ**, a meal-tracking companion app) to hang on the line without rewriting layout and hit-test code. Operating over a generic `activeBigPieces: [any CompanionPiece]` list keeps the physics engine agnostic to specific cards while avoiding the complexity of a third-party dynamic plugin SDK.

### 3.5 Main-Display-Only Lock vs. Single User-Selected Display + Portrait Two-Rope Mode
* **Alternative:** Lock `DesktopYardWindow` permanently to `NSScreen.main` with a single horizontal rope.
* **Decision:** Rejected by author.
* **Technical Rationale:** Users with multi-monitor setups often dedicate a secondary display (frequently rotated into portrait orientation) as an uncovered ambient monitor while keeping maximized IDE or browser windows on `NSScreen.main`. Allowing the user to select which single display hosts Varal—and automatically stacking two parallel ropes vertically (`Line 1` for big pieces and `Line 2` for task slips) when that display is in portrait orientation—lets Varal remain visible all day without adding multi-monitor mirroring complexity.

---

## 4. Detailed Implementation

This unified implementation plan enumerates every file created or updated across both the completed Phase 1 grayscale wireframe deliverables (in docs/) and the Phase 2 native macOS Swift/AppKit application target (`Varal.app`), along with its concrete responsibility and rationale.

### 4.1 Phase 1: Wireframe & Specification Artifacts (docs/)

1. **[concepts_brief.md](../product/concepts_brief.md)** *(Created / Updated)*
   * **Rationale:** Captures the upstream 7-lens Goldfish brainstorm synthesis, the `CompanionPiece` contract, display selection and Portrait two-rope rules, the `varal://weekend?start=...&end=...&plan=...` deep-link scope boundary, and the zero-notification invariant.
2. **[wireframe_spec.md](./wireframe_spec.md)** *(Created / Updated)*
   * **Rationale:** Provides the deterministic 6-board grayscale blueprint specification, spatial coordinate grid, catenary sag formula, 3-phase downward tear-off kinematics, `04:00 AM` weathered rollover rule, and resolved architecture rulings.
3. **[wireframe.html](./wireframe.html)** *(Created / Updated)*
   * **Rationale:** Self-contained interactive grayscale HTML/CSS/SVG prototype enabling live verification of Boards 1–6, catenary sag and upward recoil, dwell-gated shingled cluster expansion, downward drag-to-tear (`>48px`), basket undo, Atmos weather spill (`Breeze`, `Rain`, `Snow`), and Get Long Weekend State A (Discovery) / State B (Countdown) transitions.

### 4.2 Phase 2: Native macOS Application Package & Configuration (`Varal/`)

4. **[Package.swift](../../Package.swift)** *(Create)*
   * **Rationale:** Defines the Swift 6 / macOS 14+ package manifest for the `Varal` executable target and `VaralTests` unit test target with zero third-party UI dependencies. Configures `exclude: ["Info.plist"]` and linker settings (`-Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Varal/Info.plist`) on the `Varal` target.
5. **[Varal/Info.plist](../../Varal/Info.plist)** *(Create)*
   * **Rationale:** Configures `LSUIElement = true` (menu-bar utility with no Dock icon and no application menu bar takeover) and registers the `varal` custom URL scheme (`CFBundleURLSchemes = ["varal"]`) for handling `varal://weekend?start=...&end=...&plan=...` deep links. Packaged alongside the compiled executable into `Varal.app/Contents/Info.plist` (`Varal.app/Contents/MacOS/Varal`) so macOS Launch Services registers the `varal://` scheme. No `NSUserNotificationsUsageDescription` or notification entitlements are included.
6. **[Varal/VaralApp.swift](../../Varal/VaralApp.swift)** *(Create)*
   * **Rationale:** Application entry point (`@main`) and `NSApplicationDelegate` adapter. Initializes the shared stores (`TaskSlipStore`, `HolidayPlanStore`, `ClotheslinePhysicsEngine`), filters the built-in `[AtmosPiece, GetLongWeekendPiece]` array against `UserDefaults` (`enabledCompanionPieceIDs`), spawns the single `DesktopYardWindow` on the user's chosen display, attaches `MenuBarController` on the main display, and routes incoming `application(_:open:)` URL events to `URLSchemeRouter`.

### 4.3 Core Contracts, Models & Persistence (`Varal/Models/` & `Varal/Contracts/`)

7. **[Varal/Contracts/CompanionPiece.swift](../../Varal/Contracts/CompanionPiece.swift)** *(Create)*
   * **Rationale:** Declares the `CompanionPiece` protocol (`pieceID`, `displayName`, `sizeMetrics`, `pinCount`, `preferredSide`, `environmentalBroadcast`, `@MainActor var pieceView: NSView { get }`), `PieceAnchorSide` (`.leading`, `.trailing`), `PieceSizeMetrics`, `PrecipitationState`, `SolarPhase`, and `EnvironmentSnapshot` (wind speed/direction, precipitation state, solar/lunar phase), plus a static helper filtering the built-in first-party pieces against `enabledCompanionPieceIDs`. Decouples all layout, view mounting, catenary sag, hit-testing, and cluster-expansion math from specific card implementations without downcasting.
8. **[Varal/Models/TaskSlip.swift](../../Varal/Models/TaskSlip.swift)** *(Create)*
   * **Rationale:** Defines `SlipState` (`.hanging` and `.inBasket(completedAt: Date)` only—no `.archived` state) and the immutable `TaskSlip` model (`id`, `timeLabel`, `title`, `createdAt`, `pinSlotIndex`, `state`, `weatheredDays`, `sourcePlanID`, `sourceBlockStart`). Enforces immutability of `title` and `timeLabel` after creation and preserves the slip's clothespin slot index (`pinSlotIndex`) while `.hanging` or `.inBasket`.
9. **[Varal/Models/VacationPlan.swift](../../Varal/Models/VacationPlan.swift)** *(Create)*
   * **Rationale:** Defines `VacationBlock` (`startDate`, `endDate`) and `VacationPlan` (`planID`, sorted `blocks: [VacationBlock]`, `updatedAt`) to support multi-block vacation plans in Get Long Weekend State B.
10. **[Varal/Services/TaskSlipStore.swift](../../Varal/Services/TaskSlipStore.swift)** *(Create)*
    * **Rationale:** Persists `TaskSlip` records atomically to `~/Library/Application Support/Varal/slips.json`. Parses optional leading `HH:mm` tokens on quick-add (defaulting `timeLabel` to current local `HH:mm` if omitted), assigns `pinSlotIndex`, transitions torn slips to `.inBasket` (retaining `pinSlotIndex` at `18pt` empty-pin width), undoes `.inBasket` slips back to `.hanging`, and permanently deletes `.inBasket` slips on `04:00 AM` rollover or `[Limpar cesto]` while compacting remaining `.hanging` `pinSlotIndex` values.
11. **[Varal/Services/RolloverScheduler.swift](../../Varal/Services/RolloverScheduler.swift)** *(Create)*
    * **Rationale:** Monitors system clock and `NSWorkspace.didWakeNotification` to trigger the daily `04:00 AM` local rollover. Deletes all `.inBasket` slips from `TaskSlipStore` (clearing the basket, removing their empty clothespins, and compacting `pinSlotIndex` values) while keeping all unfinished `.hanging` slips on the line and incrementing their `weatheredDays` counter by `1`.

### 4.4 Built-In First-Party Companion Pieces & Deep-Link Router (`Varal/Pieces/` & `Varal/Services/`)

12. **[Varal/Pieces/AtmosPiece.swift](../../Varal/Pieces/AtmosPiece.swift)** *(Create)*
    * **Rationale:** Implements `CompanionPiece` (`pieceID = "atmos"`, `pinCount = 2`, `preferredSide = .leading`, `massUnits = 6.0`) and supplies its card container view via `pieceView`. Defines the internal `WeakScriptMessageHandler` proxy class, hosts `atmos.reggiespace.ca/?mode=piece` inside a `WKWebView` with `securityOrigin.host == "atmos.reggiespace.ca"` validation to receive `EnvironmentSnapshot` updates without holding any weather API key in Varal, caches the last valid snapshot for up to `30 minutes`, suspends the `WKWebView` behind a static `takeSnapshot` image (correction v1-app2 C6: the still image is mounted as an overlay while suspended) when `isDesktopCanvasRenderActive == false`, and reloads on `webViewWebContentProcessDidTerminate(_:)`, `NWPathMonitor`, or wake recovery.
13. **[Varal/Pieces/GetLongWeekendPiece.swift](../../Varal/Pieces/GetLongWeekendPiece.swift)** *(Create)*
    * **Rationale:** Implements `CompanionPiece` (`pieceID = "get-long-weekend"`, `pinCount = 2`, `preferredSide = .trailing`, `massUnits = 6.0`) and supplies its card view via `pieceView`. Renders State A (local Discovery card opening `https://getlongweekend.ca` when no active `VacationPlan` exists) or State B (Personal Countdown to the next upcoming `VacationBlock` in `HolidayPlanStore`).
14. **[Varal/Services/HolidayPlanStore.swift](../../Varal/Services/HolidayPlanStore.swift)** *(Create)*
    * **Rationale:** Persists `VacationPlan` records to `~/Library/Application Support/Varal/holiday_plans.json`, performs authoritative block replacement per `planID`, resolves the next upcoming `VacationBlock` (`endDate >= today`), spawns/updates passive reminder `TaskSlip` items keyed idempotently by `(sourcePlanID, sourceBlockStart)` at `T-7 days` using the bilingual template (`EN`: `timeLabel = "T-7d"`, `title = "Long weekend (<start> – <end>) — confirm time off"`; `PT`: `timeLabel = "T-7d"`, `title = "Feriadão (<start> – <end>) — confirmar folga"`), and removes orphaned `.hanging` reminder slips if a block is removed on re-hang.
15. **[Varal/Services/URLSchemeRouter.swift](../../Varal/Services/URLSchemeRouter.swift)** *(Create)*
    * **Rationale:** Parses `varal://weekend?start=...&end=...&plan=...` URLs, validates ISO-8601 date ranges, replaces the authoritative `blocks` list for `planID` in `HolidayPlanStore` idempotently, and ensures re-hanging the same `plan` updates the card and reminder slips in place without duplication.

### 4.5 Physics Engine, Occlusion Governor & Desktop Window (`Varal/Engine/` & `Varal/UI/`)

16. **[Varal/Engine/ClotheslinePhysicsEngine.swift](../../Varal/Engine/ClotheslinePhysicsEngine.swift)** *(Create)*
    * **Rationale:** Computes per-rope catenary sag (`Δy_sag(k)` clamped to `<= 54pt`), underdamped spring recoil (`ω0 = 18 rad/s`, `ζ = 0.35`) when slips are pinned or torn off, compound pendulum sway angles driven by the active `EnvironmentSnapshot` (or `6 km/h` fallback breeze if `Atmos` is disabled/offline), and the `150ms` dwell-gated shingled cluster expansion offsets (with dynamic pitch compression `min(116pt, availableClusterWidth / N_hangingSlips)` and `18pt` empty-pin pitch). Correction v1-app2: menu-conditional line anchor, ultrawide aspect gate + thirds placement, width-aware cluster step, uniform slot grid, and the draw-equivalent cubic control offset.
17. **[Varal/Engine/OcclusionGovernor.swift](../../Varal/Engine/OcclusionGovernor.swift)** *(Create)*
    * **Rationale:** Evaluates `isDesktopCanvasRenderActive` and `isPopoverSimulationActive` on the user's chosen display (`selectedScreen`) by observing `NSWorkspace.didActivateApplicationNotification`, `NSWorkspace.activeSpaceDidChangeNotification`, coalesced `3.0s` `CGWindowListCopyWindowInfo` checks (`>85%` occlusion of clothesline and basket rects on `selectedScreen`), `ProcessInfo.processInfo.isLowPowerModeEnabled`, `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` (macOS Reduce Motion), and the user's `Pause Breeze` preference. Pauses `DesktopYardWindow` `CADisplayLink` and `AtmosPiece` `WKWebView` rendering to `0fps` whenever `isDesktopCanvasRenderActive` is `false`.
18. **[Varal/UI/DesktopYardWindow.swift](../../Varal/UI/DesktopYardWindow.swift)** *(Create)*
    * **Rationale:** Subclasses `NSWindow` configured at `CGWindowLevelForKey(.desktopIconWindow) - 1` on the single display selected in Settings (`selectedScreenDisplayID`, defaulting to `NSScreen.main`, with automatic fallback to `NSScreen.main` on disconnect). Manages the passive global mouse monitor (`NSEvent.addGlobalMonitorForEvents`) that checks `NSWindow.windowNumber(at:belowWindowWithWindowNumber: 0)` and toggles `ignoresMouseEvents` dynamically against the in-memory union of `bigPieceHitRects`, `smallSlipClusterHitRect`, and `laundryBasketHitRect`. Correction v1-app2 C10: coverage is decided by the topmost opaque window's layer (`normal <= layer < dock` blocks; the Finder desktop layer never does). Correction v1-app2 C11: level is plain `.desktopIconWindow`, ordered above the Finder desktop window.
19. **[Varal/UI/ClotheslineCanvasView.swift](../../Varal/UI/ClotheslineCanvasView.swift)** *(Create)*
    * **Rationale:** Overrides `isFlipped -> true` (top-left coordinate origin) and registers an `[.mouseEnteredAndExited, .activeAlways, .inVisibleRect]` `NSTrackingArea` for the `150ms` cluster dwell gate. Renders the clothesline stage on `selectedScreen`, switching between **Landscape Mode** (`width >= height`: 1 horizontal rope at the §2.2 menu-conditional anchor holding leading big pieces, center task cluster, and trailing big pieces) and **Portrait Layout Mode** (`height > width`: 2 stacked parallel ropes with Line 1 for `activeBigPieces`, Line 2 for small task slips, and the laundry basket at the bottom of the screen for full-height tear-off flutter). Correction v1-app2: single unified `computeLayout()` (piece frames, slot-stable slip frames, pin rects) applied by refresh/frame-tick/draw/hit-test; ultrawide thirds placement; drawn clothespins over every slot; drag extra-dip; fly-back undo animation; unmount of disabled pieces.
20. **[Varal/UI/TaskSlipView.swift](../../Varal/UI/TaskSlipView.swift)** *(Create)*
    * **Rationale:** Renders an individual 1-pin immutable task slip at its `pinSlotIndex` (with deckled/weathered edge styling when `weatheredDays >= 1`) and handles the 3-phase downward drag gesture (`0–18pt` elastic stretch, `18–48pt` perforation unzip, `>48pt` detachment and falling-leaf flutter into the basket). Correction v1-app2: pointer-following drag with Phase C serration + shadow, and adaptive Dark Mode paper/ink (Board 4 night palette).
21. **[Varal/UI/LaundryBasketView.swift](../../Varal/UI/LaundryBasketView.swift)** *(Create)*
    * **Rationale:** Renders the bottom-right `cesto`, displays stacked completed slips and the `"Dia concluído"` caption when all active slips are torn off, handles drag-up undo back to the slip's preserved `pinSlotIndex` clothespin on the line, and provides the manual `[Limpar cesto]` deletion action. Correction v1-app2: undo is drag-up `>60pt` only; a click does nothing.
22. **[Varal/UI/MenuBarController.swift](../../Varal/UI/MenuBarController.swift)** *(Create)*
    * **Rationale:** Manages the `NSStatusItem` on the main display's menu bar (rendering the live `[⊶ N]` micro-line glyph) and its `NSPopover` containing the Mini Clothesline mirror (driven by `isPopoverSimulationActive`), quick-add task field, interactive mini-slip tear-off, **Pause Breeze** toggle, and Settings sheet (Display picker for choosing the single target screen + on/off checkboxes for built-in `CompanionPiece` modules). Correction v1-app2: Settings title, Display label, companion-pieces label, and basket count are bilingual EN/PT via `UIStrings`.

### 4.6 Verification & Unit Tests (`VaralTests/`)

23. **[VaralTests/URLSchemeRouterTests.swift](../../VaralTests/URLSchemeRouterTests.swift)** *(Create)*
    * **Rationale:** Verifies parsing of `varal://weekend?start=...&end=...&plan=...` across single-block and multi-block plans, confirms idempotent updates when re-hanging the same `plan`, and asserts that per-block `T-7d` reminder slips match the bilingual `EN`/`PT` templates and never duplicate.
24. **[VaralTests/RolloverAndStoreTests.swift](../../VaralTests/RolloverAndStoreTests.swift)** *(Create)*
    * **Rationale:** Verifies that `[Limpar cesto]` and the `04:00 AM` rollover permanently delete `.inBasket` slips from `slips.json` and compact `pinSlotIndex` values, that rollover retains unfinished `.hanging` slips and increments `weatheredDays`, and that slip fields remain immutable after quick-add `HH:mm` parsing.
25. **[VaralTests/PhysicsAndGovernorTests.swift](../../VaralTests/PhysicsAndGovernorTests.swift)** *(Create)*
    * **Rationale:** Verifies catenary sag calculation over `0..N` dynamic `CompanionPiece` items, Landscape single-rope vs. Portrait two-rope coordinate geometry, and `OcclusionGovernor` decoupling (`isDesktopCanvasRenderActive` vs. `isPopoverSimulationActive`) under macOS **Reduce Motion**, Low Power Mode, and `>85%` window coverage on `selectedScreen`.
26. **[VaralTests/YardLayoutTests.swift](../../VaralTests/YardLayoutTests.swift)** *(Create, correction v1-app2)*
    * **Rationale:** Verifies the ultrawide corrections in pixels and points: menu-conditional line clearance, aspect-gated thirds placement with legacy 1920×1080/Portrait geometry intact, side-by-side no-overlap slips at 3440×1440, tear-without-shift plus empty pin, draw-curve/layout-deflection agreement, pointer-following drag with the 48pt threshold, drag-only basket undo, slip-text contrast in light and dark appearances, and the bilingual chrome strings.



