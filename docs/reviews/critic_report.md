# Stage 7: Critic Review Report (`FeatureRange`: Lines 1..320)

* **Target Document:** [docs/designs/varal.md](./docs/designs/varal.md) (`1..320`)
* **Reviewers:** `egm-design`, `egm-structural`, `egm-style`
* **Standards Applied:** `feature-spec-standard`
* **Date:** 2026-11-18

---

## Part 1: Hostile Design Critic (`egm-design`)

### Finding D-1: WindowServer Z-Order & `NSTrackingArea` Hover Gating Under Covering Windows
* **Severity:** Major
* **Affected Scope:** Section 2.2.4 (`Dynamic Hit-Test Mask`, lines 127–135).
* **Flaw:**
  1. Section 2.2.4 relies on a global mouse monitor (`NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged])`) to flip `ignoresMouseEvents = false` whenever the cursor enters the 2D screen-space bounding boxes (`bigPieceHitRects`, `smallSlipClusterHitRect`, `laundryBasketHitRect`), and then claims standard AppKit `NSTrackingArea` callbacks (`mouseEntered:` / `mouseExited:`) will gate the `150ms` hover-cluster expansion so it *"never expands when covered by a foreground window."*
  2. Because Varal is an `LSUIElement = true` background utility, `DesktopYardWindow` is almost never the active application when hovered, meaning `NSTrackingArea` **must** be configured with `.activeAlways` to fire at all. Furthermore, the global mouse monitor fires on 2D screen coordinates even when an opaque browser window's tab bar (which occupies the same `y = 38..160pt` band at the top of the screen!) is directly over the clothesline—causing `DesktopYardWindow` to toggle `ignoresMouseEvents` on every mouse move over a foreground browser toolbar.
* **Recommendation:**
  1. Specify that `NSTrackingArea` uses `[.mouseEnteredAndExited, .activeAlways, .inVisibleRect]`.
  2. Before flipping `ignoresMouseEvents = false` or starting the `150ms` hover-cluster dwell timer when the cursor enters an active hit polygon, verify via `NSWindow.windowNumber(at: cursorScreenPoint, belowWindowWithWindowNumber: 0)` that no standard application window (`windowLevel >= NSWindow.Level.normal`) is covering that cursor coordinate. (A single point query via `NSWindow.windowNumber(at:belowWindowWithWindowNumber:)` checks only the topmost window at that point without copying the full window dictionary list.)

### Finding D-2: Unbounded Catenary Sag & Horizontal Cluster Overflow Under Weathered Accumulation
* **Severity:** Major
* **Affected Scope:** Section 2.4.1 & 2.4.2 (`Catenary Physics & Shingled Small-Slip Cluster`, lines 191–202) and [wireframe_spec.md](./wireframe_spec.md#L15-L16).
* **Flaw:**
  1. **Unbounded Linear Sag:** The sag equation $\Delta y_{\text{sag}}(k) = 8\text{pt} + \sum p.\text{massUnits} + (4.5\text{pt} \times N_{\text{slips}}(L_k)) + W_{\text{moisture}}$ has no upper clamp. Because unfinished tasks never auto-retire at `04:00 AM` and there is no hard 5-task cap, accumulating 15–20 unfinished tasks causes $\Delta y_{\text{sag}}$ to exceed `110pt` (`control point > 200pt`), colliding with Line 2 in Portrait Mode (`y_line2 = y_line1 + 235pt`).
  2. **Expanded Cluster Horizontal Collision:** When `clusterExpanded = true`, slips fan out with `12pt` spacing (`116pt` pitch per slip). At `>= 10` slips (`1160pt`), the expanded fan exceeds the center span between leading and trailing big pieces on a 14-inch MacBook (`1512pt` width), causing cards to collide or clip off-screen.
  3. **Bezier Multiplier Alignment:** `varal.md` line 193 specifies Bezier control point `y_k + 1.85 * Δy_sag(k)` (so the curve midpoint sags by $\approx 0.925 \times \Delta y_{\text{sag}}$), whereas `wireframe_spec.md` line 15 writes `cy: menuBarHeight + 14pt + Δy_sag`.
* **Recommendation:**
  1. Clamp catenary sag to a physical ceiling: $\Delta y_{\text{sag}}(k) = \min(54\text{pt}, 8\text{pt} + \sum p.\text{massUnits} + 4.5\text{pt} \times N_{\text{slips}}(L_k) + W_{\text{moisture}})$.
  2. Dynamically clamp the expanded inter-slip horizontal step to `min(116pt, availableClusterWidth / max(1, N_slips))` so an expanded fan with `8–12` slips still fits between the pushed outer cards without clipping off-screen.
  3. Align `wireframe_spec.md` line 15 with `varal.md`'s `1.85 * Δy_sag` control-point formula.

### Finding D-3: Ambiguity in `pinSlotIndex` Layout for Empty Pins & Deep-Link Multi-Block Replacement Semantics
* **Severity:** Major
* **Affected Scope:** Section 2.5 (`Data Models, Rollover Weathering & Deep-Link Contract`, lines 214–253).
* **Flaw:**
  1. **Empty Pin Layout (`pinSlotIndex`):** Section 2.5.1 states that both `.hanging` and `.inBasket` slips reserve their `pinSlotIndex` on the rope until `04:00 AM` or `[Limpar cesto]`. However, Section 2.4.2 does not clarify whether empty clothespins (`.inBasket` slots) take up full `104pt` card widths or compact `18pt` pin widths on the line when neighboring `.hanging` slips shingle and expand.
  2. **Contradictory Upsert vs. Merge Rule in `varal://weekend`:** Line 249 says: *"If `HolidayPlanStore` already holds a `VacationPlan` with the same `plan` identifier, it updates that plan's `blocks` in place; if a single new `(start, end)` block is passed for an existing `plan`, it merges/updates that block idempotently."* If a URL arrives with 1 block for existing plan `p1`, it is impossible to distinguish whether the user deleted 2 blocks from a 3-block plan on `getlongweekend.ca` (full replacement) or is merging 1 block into `p1`. Furthermore, the spec does not state what happens to an already-pinned `.hanging` reminder slip if its block is removed or pushed outside the `T-7d` window on re-hang.
* **Recommendation:**
  1. Specify that `.inBasket` empty clothespins collapse to their bare pin width (`18pt` pitch) in-place at their `pinSlotIndex` slot, expanding back to full slip width (`104pt`) only if the slip is dragged back from the basket (undo).
  2. Make `varal://weekend?start=...&end=...&plan=<id>` strictly a **full authoritative replacement** of `blocks` for `planID = <id>`. On re-hang, any existing `.hanging` reminder slip for `sourcePlanID == <id>` whose `sourceBlockStart` is no longer in the updated `blocks` (or is now `> 7 days` in the future) is removed, while matching blocks preserve their existing slip idempotently.

### Finding D-4: `WKWebView` Process Crash Recovery, Weak Handler Proxy & Origin Validation (`AtmosPiece`)
* **Severity:** Major
* **Affected Scope:** Section 2.3.2 (`Atmos Web-Hosted Piece`, lines 164–182).
* **Flaw:**
  1. **WebContent Process Crash (`Jetsam`):** macOS terminates background `WKWebView` `WebContent` processes under memory pressure (`webViewWebContentProcessDidTerminate(_:)`). Observing only `NWPathMonitor` and `didWakeNotification` leaves `AtmosPiece` permanently blank if `WebContent` terminates while the Mac is awake and online.
  2. **Strong Retain Cycle & Missing Security Origin Check:** `WKUserContentController.add(_:name:)` strongly retains its handler, leaking `AtmosPiece` unless wrapped in a weak proxy, and `userContentController(_:didReceive:)` does not specify validating `message.frameInfo.securityOrigin.host == "atmos.reggiespace.ca"`.
* **Recommendation:**
  1. Handle `WKNavigationDelegate.webViewWebContentProcessDidTerminate(_:)` with an automatic reload (using exponential backoff).
  2. Wrap the `WKScriptMessageHandler` in a weak proxy and validate `message.frameInfo.securityOrigin.host == "atmos.reggiespace.ca"` (and restrict navigation to `atmos.reggiespace.ca`).

### Finding D-5: AppKit Top-Left vs. Bottom-Left Coordinate Convention (`isFlipped`)
* **Severity:** Nit
* **Affected Scope:** Section 2.2.2 (line 119).
* **Recommendation:** State explicitly that `ClotheslineCanvasView` overrides `isFlipped -> true` so all `y_line1`, `y_line2`, and `+Δy_sag` equations operate in top-left origin coordinates.

### Finding D-6: Quick-Add Time Token Parsing Rule
* **Severity:** Nit
* **Affected Scope:** Section 2.5 (`TaskSlip.timeLabel`, line 217).
* **Recommendation:** Specify the deterministic quick-add parser rule: if the input starts with a leading `HH:mm` token (e.g., `"17:30 Buy coffee"`), split it into `timeLabel = "17:30"` and `title = "Buy coffee"`; otherwise default `timeLabel` to the current local `HH:mm` time when pinned.

### Finding D-7: Unneeded `.archived` State Retention in `slips.json`
* **Severity:** Nit
* **Affected Scope:** Section 2.5.1 (lines 221, 241–243).
* **Recommendation:** Since productivity history and streaks are an explicit Non-Goal, either delete `.inBasket` slips outright from `slips.json` upon `04:00 AM` rollover / `[Limpar cesto]` (leaving only `.hanging` and `.inBasket` states in `SlipState`), or prune `.archived` entries older than 7 days at rollover so `slips.json` never grows unboundedly.

---

## Part 2: Structural Layout Validator (`egm-structural`)

### Finding S-1: Unindented Fenced Code Blocks Inside Ordered List Items
* **Severity:** Nit
* **Affected Scope:** Section 2.3 (`### 2.3 Companion Piece Contract & Extension Boundaries`, lines 141–161 and 168–176).
* **Discrepancy:** Unindented 0-column fenced `swift` code blocks inside numbered list items `1.` and `2.` break CommonMark list continuation for the subsequent 3-space-indented sub-bullets. Indenting those code blocks by 3 spaces preserves list hierarchy.

### Finding S-2: Section 1 H3 Heading Numbering Symmetry
* **Severity:** Nit
* **Affected Scope:** Section 1 (`## 1. Overview, Problem Statement & Goals`, lines 10–55).
* **Discrepancy:** Sections 2, 3, and 4 number all H3 subsections (`### 2.1`–`2.7`, `### 3.1`–`3.5`, `### 4.1`–`4.6`), whereas Section 1 uses unnumbered H3 headings (`### The Problem`, `### Overview`, `### Goals`, `### Non-Goals`). Numbering them `### 1.1 The Problem`, `### 1.2 Overview`, `### 1.3 Goals`, `### 1.4 Non-Goals` (and matching the H2 header order `## 1. Problem Statement, Overview & Goals`) restores structural symmetry.

### Finding S-3: Missing Fenced Code Block Language Tags
* **Severity:** Nit
* **Affected Scope:** Section 2.1 (line 64) and Section 2.6 (line 261).
* **Discrepancy:** Add `text` to the ASCII architecture diagram fence (line 64) and `swift` to the boolean governor expression fence (line 261).

---

## Part 3: Technical Copy Editor & Style (`egm-style`)

### Finding ST-1: Subjective Framing in Problem Statement
* **Severity:** Nit
* **Affected Scope:** Section 1 (line 14).
* **Recommendation:** Replace *"force users into an unpleasant choice between two extremes:"* with neutral phrasing: *"Desktop task utilities and ambient widgets on macOS fall into two categories:"*.

### Finding ST-2: Decorative Adverbs in Technical Transitions (`cleanly`, `quietly`, `calmly`, `smoothly`, `safely`)
* **Severity:** Nit
* **Affected Scope:** Lines 27, 30, 31, 202, 207, 250, 251.
* **Recommendation:** Strip decorative adverbs (`cleanly`, `quietly`, `calmly`, `smoothly`, `safely`) and state the technical mechanism directly (e.g., *"pins a reminder slip without triggering a notification"*, *"Releasing returns the slip to rest without completing"*).

### Finding ST-3: Subjective Spacing & Threshold Qualifiers
* **Severity:** Nit
* **Affected Scope:** Lines 124, 130, 200.
* **Recommendation:**
  * Line 124: Replace *"hanging side-by-side with generous horizontal breathing room"* with *"hanging side-by-side across Line 1"*.
  * Line 130: Replace *"performs pure in-memory geometry hit-testing"* with *"performs in-memory geometry hit-testing"*.
  * Line 200: Replace *"When the number of active slips fits comfortably on the line (`<= 3` in Landscape, `<= 5` on Line 2 in Portrait)"* with *"When the number of active slips is at or below the unclustered threshold (`<= 3` in Landscape, `<= 5` on Line 2 in Portrait)"*.
