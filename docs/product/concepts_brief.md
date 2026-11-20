# Varal — Native macOS Ambient Clothesline & Companion Ecosystem

* **Author:** Reginaldo dos Santos
* **Date:** 2026-11-16

## Overview

**Varal** ("clothesline" in Portuguese) is a native macOS desktop utility that lives at wallpaper level (`CGWindowLevelForKey(.desktopIconWindow) - 1`), directly behind desktop icons and application windows. It stretches a single catenary clothesline edge-to-edge across the screen below the menu bar. Three kinds of items hang from the line on wooden clothespins and react to one shared physics simulation:

1. **Atmos (Big Piece — 2 Clothespins, Anchor Left):** A live weather companion card that hosts `atmos.reggiespace.ca` in a `WKWebView` (running the Atmos web app's compact "piece mode") rather than re-implementing the sky scene natively. Varal holds no weather API key. Whenever Atmos's internal weather state changes, it posts an `EnvironmentSnapshot` (wind, precipitation, temperature, solar/lunar phase) via a `WKScriptMessageHandler` bridge to the native host, which drives shared wind angle, sway frequency, rain/snow accumulation on pins and cards, and time-of-day lighting across the clothesline. If the WebView fails to load, physics falls back to the calm breeze. (The compact piece mode and JS bridge inside the Atmos web app are an external dependency in the Atmos repo, not a Varal deliverable.)
2. **Get Long Weekend (Big Piece — 2 Clothespins, Anchor Right):** A two-state companion card for `getlongweekend.ca`. In State A (Discovery), it hangs quietly as a calm, removable product card showing the next upcoming bridge-holiday opportunity in the user's region so the user can plan their days off on `getlongweekend.ca` whenever they choose. Once the user selects their vacation dates on the web app, Varal handles `varal://weekend?start=...&end=...&plan=...` to switch the card idempotently into State B (Personal Countdown). State B supports multiple vacation blocks per plan—counting down to the next upcoming block, spawning passive tear-off reminder slips on the clothesline for each block as it approaches, and updating in place without duplication if the same plan is re-hung—never triggering any system notification, banner, sound, or badge.
3. **Daily Task Slips (Small Pieces — 1 Clothespin Each, Center Cluster):** Individual DayPad-inspired paper slips showing a time and short title. There are no checkboxes. To save horizontal space, slips group into an overlapping accordion cluster that expands smoothly along the line when hovered, pushing the two big cards toward the screen edges. Completing a task requires dragging the slip downward past a tension threshold to tear it off its clothespin; the line recoils upward and the slip flutters down into a laundry basket in the bottom-right corner of the desktop. Dragging a slip from the basket back onto the line undoes completion.

A menu-bar icon (`NSStatusItem`) provides a micro-silhouette of the line and opens a popover containing a mini clothesline mirror, quick-add task input, and a breeze pause toggle so users can add or tear off tasks even when maximized windows cover the desktop.

## Analysis

### 1. Desktop-Level Hit-Testing vs. Finder Compatibility (`egm-design` & `egm-codebase-details`)
* **The Risk:** A full-screen transparent `NSWindow` placed at `CGWindowLevelForKey(.desktopIconWindow) - 1` faces a hit-testing conflict. If `ignoresMouseEvents` is `false` across the whole screen, Varal swallows clicks meant for the desktop wallpaper or Finder marquee selection. If `ignoresMouseEvents` is `true`, the user cannot drag task slips, hover the task cluster, or retrieve items from the laundry basket.
* **Resolution:** Varal uses a passive global cursor monitor (`NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved)`) paired with a bounding-box hit mask. The window defaults to `ignoresMouseEvents = true` and flips to `ignoresMouseEvents = false` only when the cursor enters the active hit polygons of the hanging pieces, the clothesline header strip, or the bottom-right laundry basket.
* **Notch, Chosen Display, Portrait Mode & Safe-Area Geometry:** Varal renders on a single display selected by the user in Settings (defaulting to `NSScreen.main` — one yard, never mirrored or duplicated across multiple screens). The menu bar and `NSStatusItem` stay on the main display, while the clothesline anchors to the top of the chosen screen with a safe margin (`max(topSafeInset, 24pt) + 14pt`). On tall/narrow portrait displays (`height > width`), Varal uses **Portrait Layout Mode**: two parallel clotheslines stacked vertically (Line 1 for big companion pieces, Line 2 for small task slips), with the basket at the bottom of the screen so torn slips flutter down the full vertical drop.
* **Companion Piece Contract (`CompanionPiece`):** Big pieces are built-in, first-party modules implementing a shared contract (`sizeMetrics`, `pinCount`, `preferredSide`, `environmentalBroadcast`). Layout, physics, hit-testing, and cluster expansion operate over a dynamic list of enabled big pieces (`0..N`)—never hardcoding two cards or naming `Atmos` / `Get Long Weekend` in the physics layer. Pieces are optional and user-chosen in Settings (default: `Atmos` + `Get Long Weekend`). Dynamic plugin loading, third-party pieces, public SDKs, and per-piece settings beyond on/off are out of scope for V1.

### 2. Always-On Physics, Accessibility & Laptop Battery Life (`egm-design`)
* **The Risk:** Running a continuous 60/120fps spring-damper catenary physics engine, wind sway, and weather particles on a background window when that screen is covered by maximized or fullscreen apps wastes CPU/GPU cycles, drains battery, and disregards motion-sensitivity preferences.
* **Resolution:** An **Occlusion, Accessibility & Power Governor** evaluates window coverage on the **chosen display only** and suspends the `CADisplayLink` animation loop and weather particles completely when:
  1. The user switches to a macOS Fullscreen Space on the chosen display.
  2. `CGWindowListCopyWindowInfo` reports that opaque standard windows on the chosen display cover more than 85% of the clothesline and basket bounding rects.
  3. The display sleeps, macOS Low Power Mode (`ProcessInfo.processInfo.isLowPowerModeEnabled`) is enabled, macOS **Reduce Motion** (`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`) is enabled, or the user toggles **Pause Breeze** in the menu bar.

### 3. Horizontal Space & Hover-Cluster Ergonomics (`egm-comprehension` & `egm-implementation-readiness`)
* **The Risk:** On a 14-inch MacBook screen (1512pt wide), two big cards plus more than 4 task slips will collide or overlap Finder desktop icons. Conversely, if hovering anywhere near the top of the screen triggers the task cluster to expand and push the big cards outward, incidental mouse movement toward the menu bar will cause constant visual jitter.
* **Resolution:**
  * **Soft Cap & Shingled Clustering:** Up to 3 task slips hang side-by-side. When 4 to 8 slips are on the line, they group into a shingled horizontal stack in the center of the line with each slip's time and title margin partially visible.
  * **Dwell-Gated Expansion:** The cluster expands only after the cursor dwells inside the task cluster's bounding box for `150ms`. Upon expansion, the slips fan out cleanly while `Atmos` and `Get Long Weekend` slide outward toward the screen edges along the catenary curve.
  * **Tear-Off Threshold:** Downward drag uses three distinct zones so clicks or minor cursor slips never accidentally complete a task:
    * `0–18pt` drag: Elastic line stretch (line dips locally at the pin; no tear).
    * `18–48pt` drag: Perforation stress (serrated top edge begins separating visually; tension resistance increases).
    * `>48pt` drag: Snap detachment. The slip tears free, the empty clothespin stays on the line, the rope rebounds upward with damped harmonic oscillation, and the slip flutters into the bottom-right basket.

  * **Immutable Paper & Rollover Persistence:** Task slips are immutable paper—there is no inline text editing on the line (to fix a typo, tear the slip off and pin a new one). Tearing is the *only* completion verb: at the `04:00 AM` daily rollover (or manual `[Limpar cesto]`), completed slips in the basket are permanently deleted from `slips.json` (no `.archived` state), while unfinished slips stay on the line and acquire slightly weathered paper edges so the app never retires a task behind the user's back.

### 4. Deep-Link Contract & Multi-Block Holiday Lifecycle (`egm-implementation-readiness`)
* **Varal's Scope (Deep-Link Handler & Multi-Block State B):** Varal registers the `varal://` URL scheme in `Info.plist` and handles `varal://weekend?start=...&end=...&plan=...`. Receiving this payload switches the Get Long Weekend card to State B idempotently, replaces the authoritative list of vacation blocks in the plan, displays the countdown to the *next* upcoming block, and pins a single passive reminder slip onto the clothesline for each block at `T-7 days`. Re-hanging the same `plan` identifier updates the existing card and its reminder slips idempotently rather than creating duplicates.
* **External Dependency (Get Long Weekend Web Scope — Not a Varal Deliverable):** The `"Hang on Varal"` action inside the `getlongweekend.ca` Share menu fires `varal://weekend?start=...&end=...&plan=...`; if Varal is not installed on the user's Mac, `getlongweekend.ca` falls back to copying the plan link to the clipboard along with a single explanatory line about Varal.

### 5. Inventive Resolutions (`egm-inventive-catalyst`)
* **Contradiction 1 — Zero Notifications vs. Holiday Visibility:** Varal strictly bans every form of push notification, system alert, sound, banner, or badge—the app only displays state passively on the line and the user acts on it whenever they want.
  * **Resolution (Passive State Change & Physical Slips Only):** `Get Long Weekend` never interrupts the user. When a planned long weekend approaches, the card simply updates its countdown typography in place and optionally hangs a silent paper slip on the clothesline next to the user's other slips. If the user does not look at the desktop for days, nothing pops up or begs for attention.
* **Contradiction 2 — Wallpaper Immersion vs. Window Occlusion:** Living behind all windows makes Varal unobtrusive, but hides the day's load during window-heavy work.
  * **Resolution (Live Micro-Line Status Icon & Mirror Popover):** The menu-bar icon dynamically draws ticks on its tiny clothesline glyph matching the number of remaining task slips on the line, and its popover renders an interactive mini clothesline where slips can be torn off directly when the desktop is covered.
* **Contradiction 3 — Pure Grayscale Wireframe Constraint vs. Rich Environmental Mood:** Wireframe boards must remain strictly grayscale (structure and hierarchy first, no color art) while clearly distinguishing Morning, Dusk, Night, Rain, Snow, and Wind.
  * **Resolution:** Use architectural blueprint conventions across the 6 wireframe boards: monochrome halftone dot patterns for dusk/night skies, inverted charcoal wireframe surfaces (`#181818`) for Night state with vector star coordinates and dashed orbital paths for satellites, force vectors (`F_wind`, `Δy_sag`) for physics annotations, and serrated dashed lines for tear perforations.

## Goals vs. Non-Goals

* **In-Scope Goals:**
  * Define the complete structural and interaction architecture for Varal on macOS (`desktopIconWindow - 1` window level on a single user-chosen display, Landscape single-line and Portrait multi-line modes, generic `CompanionPiece` contract over `0..N` built-in big pieces, dynamic hit-testing, catenary sag physics, Reduce Motion accessibility compliance, and chosen-display occlusion governor).
  * Specify the environmental coupling where **Atmos** drives wind sway, precipitation (rain/snow on pins and cards), and day/dusk/night states across the entire clothesline.
  * Specify the two-state lifecycle for **Get Long Weekend** (State A calm, removable Discovery card linking to `getlongweekend.ca` -> State B multi-block Personal Countdown card synced idempotently via `varal://weekend?start=...&end=...&plan=...` that pins passive reminder slips onto the line).
  * Deliver the 6-board annotated grayscale wireframe specification and interactive HTML/CSS wireframe prototype covering: (1) Morning desktop, (2) Tear-off gesture mid-action, (3) Desktop covered by browser window with menu-bar popover open, (4) Night state, (5) End-of-day empty line / full basket, and (6) First-run / empty state & Get Long Weekend state comparison.
* **Out-of-Scope Non-Goals:**
  * Multi-list project management, inline task text editing, automatic retirement of unfinished tasks, recurring nested subtasks, tags, priority flags, or streak counters.
  * Multi-monitor mirroring or multiple simultaneous instances (Varal renders on one user-selected display at a time).
  * Dynamic plugin loading, third-party pieces, a public plugin API/SDK, or per-piece settings beyond on/off.
  * Floating "Always on Top" HUD modes that obstruct active application windows.
  * Final color visual design, custom illustration assets, or production Swift/Metal shader code in this phase.
  * Full vacation planning UI inside Varal or changes to the `getlongweekend.ca` and `atmos.reggiespace.ca` web codebases (the `getlongweekend.ca` Share menu's `"Hang on Varal"` trigger + fallback copy behavior, and the `atmos.reggiespace.ca` compact piece mode + `WKScriptMessageHandler` bridge, are external dependencies owned by their respective web repositories).

## Alternatives Weighed

* **Full-Screen Illustrated Background with Wooden Posts vs. Transparent Edge-to-Edge Overlay:**
  * *Rejected by author / synthesis:* A full-screen opaque sky and hill illustration (with vertical wooden posts) duplicates the sky already rendered inside the **Atmos** frame and forces users to give up their macOS wallpaper. Using an edge-to-edge clothesline over a transparent/ambient desktop layer allows **Atmos** to act as the dedicated window to the sky while its weather physics (wind, rain, snow, night fireflies) spill out onto the clothesline and neighboring cards.
* **Scratch-Out In-Place (DayPad Literal) vs. Downward Tear-Off Into Basket:**
  * *Rejected by author:* Leaving scratched-out tasks hanging on the line all day clutters the clothesline and eliminates the physical weight relief (line rebounding upward as tasks are removed). Selected **Option B (Downward Tear-Off Into Basket)** while keeping DayPad's tactile paper aesthetic and compact daily focus.
* **Hard 5-Task Cap vs. Hover-Expandable Shingled Cluster:**
  * *Rejected by author:* Instead of blocking users from adding a 6th task, grouping tasks from the same app into a shingled cluster that fans out on hover preserves horizontal breathing room while pushed cards glide toward the screen edges.

## Key Decisions & Staging for Next Steps

1. **Environmental Physics Driver (`WKWebView` Bridge) & Accessibility:** `Atmos` hosts `atmos.reggiespace.ca` in a `WKWebView` (compact piece mode) and posts `EnvironmentSnapshot` updates to Varal via `WKScriptMessageHandler` (`Varal` holds no weather API key, and falls back to a calm breeze if the WebView fails to load). Enabling macOS **Reduce Motion** automatically pauses all sway and weather particles (identical to **Pause Breeze**).
2. **Get Long Weekend Two-State & Multi-Block Contract:** Starts in State A (`Discovery` — a calm, removable product piece, never advertising inventory), switches idempotently via `varal://weekend?start=...&end=...&plan=...` to State B (`Personal Countdown` supporting multiple vacation blocks per plan, counting down to the next block and spawning per-block reminder slips without duplicating on re-hang). The `"Hang on Varal"` Share menu action on `getlongweekend.ca` is documented as an external dependency.
3. **Immutable Paper, Rollover Weathering, Chosen Display & Portrait Mode:** Slips are immutable paper (no inline editing; tear off and re-pin to fix typos). Unfinished slips remain on the line past the `04:00 AM` rollover with slightly weathered paper edges because tearing is the only completion verb. Varal lives on a single user-selected display (defaulting to `NSScreen.main`) and switches to stacked parallel clotheslines in Portrait Layout Mode.
4. **Deliverable Structure:** Alongside this `concepts_brief.md` (in `docs/product/`), maintain the complete 6-board wireframe specification (`wireframe_spec.md`) and self-contained interactive grayscale HTML/CSS wireframe prototype (`wireframe.html`) in `docs/designs/`.
