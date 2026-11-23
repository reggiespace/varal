# Varal — 6-Board Annotated Grayscale Wireframe Specification

* **Author:** Reginaldo dos Santos
* **Date:** 2026-11-16
* **Companion Files:** [concepts_brief.md](../product/concepts_brief.md) | [wireframe.html](./wireframe.html)

---

## Global Spatial Grid & Window Level Contract

* **Window Level, Display Selection & Portrait Mode:** For the current window level and top-anchor contract, see [the finalized design §2.2](varal.md#22-desktop-window-management-display-selection--portrait-layout-mode). Varal remains on one user-selected display; on portrait displays (`height > width`), **Portrait Layout Mode** stacks two parallel clotheslines vertically (Line 1 for big companion pieces, Line 2 for small task slips), with the basket at the bottom. The Occlusion & Power Governor evaluates window coverage on the chosen display only.
* **Screen Anchor & Catenary Line:**
  * For the current anchor, rendered curve, and sag formula, see [the finalized design §§2.2 and 2.4.1](varal.md#22-desktop-window-management-display-selection--portrait-layout-mode).
* **Zero-Notification Invariant:** No `UNUserNotificationCenter` permissions, no Dock icon (`LSUIElement = true`), no red badges, no modal alerts, no sounds. All state is passive and visual on the clothesline.
* **Accessibility Rule (Reduce Motion):** When macOS **Reduce Motion** (`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`) is enabled, Varal automatically pauses all wind sway and weather particles—identical in behavior to toggling **Pause Breeze**.
* **Immutable Paper & Rollover Weathering:** Task slips are immutable paper (no inline editing; to fix a typo, tear the slip off and pin a new one). Tearing is the *only* completion verb: unfinished slips remain on the line after the `04:00 AM` rollover with slightly weathered paper edges.

---

## Board 1: Morning Desktop (Full Line & Clustered Tasks)

### Structural Wireframe (Grayscale Blueprint)

```
+--------------------------------------------------------------------------------------------------+
| [] Finder  File  Edit  View  Go  Window  Help                      [⊶3]  Mon 16 Nov 09:42  100% |
+==================================================================================================+
| (0,38pt)                                                                            (1512,38pt)  |
| ~~~\~~~~~~~~~~~~~~~~~~~~~~~~~~~~\~~~~~\~~~~~\~~~~~\~~~~~~~~~~~~~~~~~~~~~~~~\~~~~~~~~~~~~~~~~~~~~ |
|     |                            |     |     |     |                        |                    |
|  +--[=]-------[=]-+           +--[=]--[=]--[=]--[=]-+                    +--[=]-------[=]-+      |
|  | ATMOS          |           | 09:30 | 11:00 | 14:00 | 16:30          | | GET LONG WKND  |      |
|  | +------------+ |           | Stand | Send  | Dent- | Review         | |  [||] [||] [ ] |      |
|  | |   ( O )    | |           | up    | Q4    | ist   | PRs            | |                |      |
|  | |  ~~~       | |           | sync  | brief | appt  | before         | |  Next Break    |      |
|  | |            | |           |       |       |       | EOD            | |  in 12 days    |      |
|  | | 18°C       | |           +-------+-------+-------+----------------+ |  4 days off    |      |
|  | +------------+ |             ^ Shingled Task Cluster (4 slips)        |  getlongwknd   |      |
|  | Calgary · 12kmh|               (Hover expands & pushes big cards out) +----------------+      |
|  +----------------+                                                                              |
|                                                                                       [===]      |
|                                                                                      Projetos    |
|                                                                                                  |
|                                                                                       [===]      |
|                                                                                      Capturas    |
|                                                                                                  |
|                                                                                \        /        |
|                                                                                 \______/         |
|                          +------------------------------------------+            cesto (0)       |
|                          | [  ] [  ] [  ] [  ] [  ] [  ] [  ] [  ]  |  <- macOS Dock             |
+--------------------------------------------------------------------------------------------------+
```

### Annotations
* **Visual Hierarchy:**
  1. **Primary Focal Tier (Upper Third):** The catenary line (`1.5pt` stroke) spans edge-to-edge. **Atmos** (`170×205pt`, 2 pins, left) and **Get Long Weekend** (`170×205pt`, 2 pins, right) frame the composition.
  2. **Secondary Focal Tier (Center):** 4–5 small task pieces (`104×126pt` each, 1 pin) hang in the center. To conserve horizontal space, slips from the same daily task group shingle with a `38pt` horizontal offset so the time header (`09:30`, `11:00`) and first words remain legible even while compact.
  3. **Tertiary Tier (Bottom-Right Corner):** The **Laundry Basket (`cesto`)** (`112×64pt`) sits above the Dock's right margin, clear of standard right-aligned Finder desktop icons.
* **What Moves and Why:**
  * **Shared Breeze Sway:** Driven by **Atmos** (`12 km/h E`). Every card and slip oscillates as a compound pendulum around its clothespin pivot (`θ(t) = θ_wind + A * sin(ωt + φ)`). Big pieces with 2 clothespins have high rotational damping (`±1.2°` sway); single-pin task slips sway more freely (`±3.5°`).
  * **Internal Atmos Motion (`WKWebView` Piece Mode + Bridge):** The Atmos card hosts `atmos.reggiespace.ca` in a `WKWebView` (compact piece mode) rather than re-implementing the scene natively. Varal holds no weather API key. Whenever the web scene updates its sky, sun/moon elevation, temperature, wind, or precipitation, it posts an `EnvironmentSnapshot` via `WKScriptMessageHandler` to the native host, which drives the clothesline sway and monochrome rain/snow particles settling along the clothesline and top edges of neighboring cards (falling back to a calm breeze if the WebView fails to load). The compact piece mode and JS bridge in the Atmos web app are an external dependency owned by the Atmos repo.
* **Exact Gestures & State Transitions:**
  * **Hovering the Shingled Task Cluster (`150ms` dwell):** Slips smoothly un-shingle (`gap: 12pt`), expanding the cluster width while sliding **Atmos** slightly left and **Get Long Weekend** slightly right along the rope curve. Moving the cursor out collapses the cluster back after `250ms`.

---

## Board 2: The Tear-Off Gesture Mid-Action

### Structural Wireframe (Grayscale Blueprint)

```
+--------------------------------------------------------------------------------------------------+
| ~~~\~~~~~~~~~~~~~~~~~~~~~~~~~~~~\~~~~~~~^~~~~~\~~~~~\~~~~~~~~~~~~~~~~~~~~~~\~~~~~~~~~~~~~~~~~~~~ |
|     |                            |      :      |     |                      |                    |
|  +--[=]-------[=]-+           +--[=]-+ [ ]  +--[=]-+-[=]-+               +--[=]-------[=]-+      |
|  | ATMOS          |           | 09:30|  :   | 14:00|16:30|               | GET LONG WKND  |      |
|  | (18°C / Wind)  |           | Stand|  :   | Dent-|Rev  |               |  in 12 days    |      |
|  +----------------+           +------+  :   +------+-----+               +----------------+      |
|                                         :                                                        |
|                                    (1) Empty pin stays on line;                                  |
|                                        rope recoils UPWARD (Δy -4.5pt)                           |
|                                         :                                                        |
|                                      \  v  /  <-- (2) Serrated perforation snaps at Δy > 48pt    |
|                                    .--vvv--.                                                     |
|                                   /  11:00   \                                                   |
|                                  /   Send Q4  \   (3) Slip rotates (-14° -> +22°)                |
|                                  \   brief    /       along sinusoidal flutter path              |
|                                   `----------'                                                   |
|                                         \                                                        |
|                                          ` - . _                                                 |
|                                                  ` - . _     (4) Trajectory arcs toward basket   |
|                                                          ` - . _                                 |
|                                                                  v                               |
|                                                                \  [===]  /  <- Undo: drag slip   |
|                                                                 \_______/      up from basket    |
|                                                                 cesto: 1                         |
+--------------------------------------------------------------------------------------------------+
```

### Annotations
* **Visual Hierarchy:**
  1. **Active Detached Slip:** Gains a deeper grayscale drop shadow (`0 12px 24px rgba(0,0,0,0.22)`) and serrated top edge (`zigzag perforation`) to separate it visually from the hanging pieces.
  2. **The Empty Clothespin:** Remains clipped to the line at its original $x$-position, subtly tilted, confirming where the task used to hang.
  3. **The Receiving Basket:** Subtle upward rim highlight as the falling slip approaches.
* **What Moves and Why:**
  * **Three-Phase Pull Kinematics:**
    * **Phase A — Elastic Tension (`0pt < Δy <= 18pt`):** Dragging downward pulls the local point of the catenary rope down with the cursor. Release here springs the slip back up without completing.
    * **Phase B — Perforation Rip (`18pt < Δy <= 48pt`):** A horizontal dashed tear line unzips across the top of the paper below the clothespin jaws.
    * **Phase C — Snap, Recoil & Flutter (`Δy > 48pt`):**
      1. **Rope Recoil:** Because the slip's weight (`4.5pt` sag equivalent) is suddenly removed, the clothesline springs upward with a damped harmonic bounce (`ζ = 0.35`, settling in `450ms`).
      2. **Aerodynamic Flutter:** Once released (or immediately upon crossing `72pt`), the slip enters an autonomous falling-leaf trajectory (`850ms` duration), biased horizontally by **Atmos**'s current wind vector while settling into the **Laundry Basket**.
* **Exact Gestures & State Transitions:**
  * **Complete:** Click-hold any task slip -> drag downward `>48pt` -> release.
  * **Undo (Basket -> Line):** Hover over the **Laundry Basket** (`cesto`) -> top-most completed slips peek upward like file tabs showing their titles -> drag any slip upward `>60pt` toward the line and release -> the slip flies back up and snaps into its empty clothespin, restoring the line's sag.

---

## Board 3: Desktop Mostly Covered by a Browser Window + Menu-Bar Popover Open

### Structural Wireframe (Grayscale Blueprint)

```
+--------------------------------------------------------------------------------------------------+
| [] Safari  File  Edit  View  History  Bookmarks  Window  Help     [⊶3]  Mon 16 Nov 14:10  100% |
+======================================================================^===========================+
| ~~~\~~~~~~~~~~~~~~~~~~~~~~~~~~~~\~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ | ~~~~~~~~~~~~~~~~~~~~~~~~~ |
|     |             +------------------------------------------------- | -------------------+      |
|  +--[=]-------[=] | [o][o][o]   < >   https://docs.project.local     |                    |      |
|  | ATMOS          |------------------------------------------------- +------------------+ |      |
|  | +------------+ |                                                  | VARAL MINI LINE  | |      |
|  | | (Left edge | |   DOCUMENTATION & WORKSPACE                      | ~-[=]-[=]-[=]-[=]| |      |
|  | |  peeking)  | |   ====================================           | 18°C · 12d to go | |      |
|  | | 18°C       | |                                                  |------------------| |      |
|  +--------------+ |   [Paragraph block............................]  | [+ Pin task... ] | |      |
|                   |   [Paragraph block............................]  |------------------| |      |
|                   |   [Paragraph block............................]  | [⊶] 09:30 Standup| |      |
|                   |                                                  | [⊶] 14:00 Dentist| |      |
|                   |   +------------------------------------------+   | [⊶] 16:30 PRs    | |      |
|                   |   | Code / Canvas Area                       |   |------------------| |      |
|                   |   | (Covers 80% of desktop & task cluster)   |   | Basket: 1  [Undo]| |      |
|                   |   +------------------------------------------+   | [Pause Breeze] ⚙ | |      |
|                   |                                                  +------------------+ |      |
|                   +-----------------------------------------------------------------------+      |
|                                                                                \  [===]  /       |
|                                                                                 \_______/        |
|                          +------------------------------------------+           cesto: 1         |
|                          | [  ] [  ] [  ] [  ] [  ] [  ] [  ] [  ]  |                            |
+--------------------------------------------------------------------------------------------------+
```

### Annotations
* **Visual Hierarchy:**
  1. **Foreground Application Window (`NSNormalWindowLevel`):** Completely occludes the center of the clothesline. Varal *never* floats above or steals focus from the browser window.
  2. **Peripheral Margins:** The left edge of **Atmos**, the far-right anchor of the rope, and the bottom-right **Laundry Basket** remain quietly visible in the desktop margins.
  3. **Menu-Bar Popover (`NSPopover` from `NSStatusItem`):** Invoked explicitly by clicking the `[⊶3]` clothesline glyph in the macOS menu bar.
* **What Moves and Why:**
  * **Occlusion Governor Activation:** Because `>85%` of the center task cluster is behind the opaque Safari window, the desktop window's `CADisplayLink` drops from `60fps` to `0fps` (static resting state) until the popover is opened or the browser window is moved/minimized.
  * **Mini-Line Popover Physics:** Inside the `260×310pt` popover, a miniature vector clothesline sways gently at the top, mirroring the exact count of pins and cards on the desktop.
* **Exact Gestures & State Transitions:**
  * **Quick-Add Task (`Cmd+Return` or `Return` in Popover Input):** Type `"17:30 Buy coffee beans"` -> press `Return` -> a new mini-pin drops onto the popover's mini-line with a bounce, and simultaneously pins a full-sized slip onto the desktop clothesline behind the browser window.
  * **Mini-Slip Tear-Off Inside Popover:** Dragging a mini-task row downward (`>24pt`) or clicking its `[↓ Tear]` action inside the popover tears it off into the popover's mini-basket (`Basket: 2`), keeping desktop and popover state 100% synchronized.
  * **Pause Breeze Toggle:** Freezes all wind sway and weather particles across the entire app for zero-motion focus sessions.

---

## Board 4: Night State (Nocturnal Physics & Ambient Sky Spill)

### Structural Wireframe (Grayscale Blueprint — Inverted Charcoal Palette)

```
+--------------------------------------------------------------------------------------------------+
| [] Finder  File  Edit  View  Go  Window  Help                      [⊶2]  Mon 16 Nov 22:45  100% |
+==================================================================================================+
| .  *       .        - - - > [sat] - - - .             *          .                    *          |
| ~~~\~~~~~~~~~~~~~~~~~~~~~~~~~~~~\~~~~~\~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\~~~~~~~~~~~~~~~~~~~~~~~~~~ |
|     |                            |     |                              |                          |
|  +--[=]-------[=]-+           +--[=]-+-[=]-+                       +--[=]-------[=]-+            |
|  | ATMOS (NIGHT)  |           | 21:00|22:30|                       | GET LONG WKND  |            |
|  | +------------+ |           | Read |Pack |                       |  [||] [||] [ ] |            |
|  | |  *   (C    | |           | 20p  |gym  |                       |                |            |
|  | |    .    *  | |           |      |bag  |                       |  Next Break    |            |
|  | |  ~~~~~~~~  | |           +------+-----+                       |  in 11 days    |            |
|  | | 9°C   Calm | |             ^ Moonlight rim highlight          |  4 days off    |            |
|  | +------------+ |               Low-glare warm-gray paper        +----------------+            |
|  | Clear · 3 km/h |                                                                              |
|  +----------------+                                                                              |
|                                                                                                  |
|        (o)  <- Firefly (halftone glow ring, slow sinusoidal drift)                               |
|                                                                          (o)                     |
|                                                          (o)                   \  [===]  /       |
|    (o)                                                                          \_______/        |
|                          +------------------------------------------+           cesto: 3         |
|                          | [  ] [  ] [  ] [  ] [  ] [  ] [  ] [  ]  |                            |
+--------------------------------------------------------------------------------------------------+
```

### Annotations
* **Visual Hierarchy:**
  1. **Low-Luminance Contrast:** In grayscale wireframe terms, paper slips shift from stark white (`#FFFFFF`) to muted slate-vellum (`#2A2A2E` fill with `#888888` typography and a `1pt` `#CCCCCC` top-edge moonlight rim highlight) so the desktop never glares at the user in a dark room.
  2. **Atmos Nocturnal Scene:** Displays waxing/waning moon phase, stars, and `9°C · 3 km/h`.
  3. **Ambient Sky Spill:** Because **Atmos** drives the environment, subtle nocturnal elements spill onto the desktop margin around the clothesline: a slow-moving satellite (`1px` point along a dashed trajectory arc once every 15–20 minutes) near the line, and 3–5 soft halftone firefly rings drifting near the bottom-right laundry basket.
* **What Moves and Why:**
  * **Nocturnal Damping:** Night wind is typically calmer (`3 km/h`); pendulum sway slows to a long, meditative period (`T = 6.5s`, amplitude `±0.8°`).
  * **Firefly Drift:** Slow Perlin/sinusoidal drift (`4–8 pt/sec`) restricted to the lower third of the canvas near the basket, fading in and out over `4s` cycles.
  * **Satellite Pass:** Rare, strictly linear vector traversal (`0.4°/sec`) across the upper band behind the clothesline.
* **Exact Gestures & State Transitions:**
  * **Automatic Solar Transition:** Driven by local sunset/dusk/night civil twilight times from **Atmos**'s coordinates (no manual toggle required, though inspectable via the wireframe switcher).

---

## Board 5: End of Day (Empty Task Line, Full Basket, "Day Complete")

### Structural Wireframe (Grayscale Blueprint)

```
+--------------------------------------------------------------------------------------------------+
| [] Finder  File  Edit  View  Go  Window  Help                      [⊶0]  Mon 16 Nov 23:30  100% |
+==================================================================================================+
|                                                                                                  |
| ~~~\~~~~~~~~~~~~~~~~~~~~~~~~~~~~[=]~~~[=]~~~[=]~~~[=]~~~~~~~~~~~~~~~~\~~~~~~~~~~~~~~~~~~~~~~~~~~ |
|     |                            ^                                    |                          |
|  +--[=]-------[=]-+              4 empty wooden clothespins        +--[=]-------[=]-+            |
|  | ATMOS          |              resting on taut line (Δy = 14pt)  | GET LONG WKND  |            |
|  | +------------+ |                                                |  [||] [||] [ ] |            |
|  | |  *   (C    | |                                                |                |            |
|  | | 8°C        | |                                                |  Next Break    |            |
|  | +------------+ |                                                |  in 11 days    |            |
|  +----------------+                                                +----------------+            |
|                                                                                                  |
|                                                                                                  |
|                                                                                                  |
|                                                                            [===] [===]           |
|                                                                          \ [===] [===] /         |
|                                                                           \___________/          |
|                          +------------------------------------------+      Dia concluído         |
|                          | [  ] [  ] [  ] [  ] [  ] [  ] [  ] [  ]  |      4 feitas · [Limpar]   |
+--------------------------------------------------------------------------------------------------+
```

### Annotations
* **Visual Hierarchy:**
  1. **Taut, Unburdened Clothesline:** With all 4 task slips torn off, the center of the line rises noticeably (`Δy` drops from `38pt` to `14pt`), holding only the 4 empty wooden clothespins in the center and the two big anchor cards (`Atmos` and `Get Long Weekend`).
  2. **Full Laundry Basket (`cesto`):** 4 folded/crumpled paper slips visibly stack above the rim of the basket in the bottom-right corner.
  3. **Calm "Day Complete" Caption:** Directly beneath the basket rim, a quiet typographic label reads `"Dia concluído · 4 feitas"` (`"Day complete · 4 done"`), accompanied by a subtle `[Limpar cesto]` (`[Empty basket]`) link on hover. No confetti, no modal popup, no sound.
* **What Moves and Why:**
  * **Empty Pin Micro-Sway:** Empty clothespins have minimal aerodynamic surface area, so they barely tremble in the breeze while the taut rope holds steady.
* **Exact Gestures & State Transitions:**
  * **Hovering the Full Basket:** Reveals individual paper edges so any slip can still be dragged back up to the line if torn off by mistake.
  * **Empty Basket / Midnight Rollover (`04:00 AM`):** Clicking `[Limpar cesto]` (or automatic rollover at `04:00 AM` local time) permanently deletes the completed `.inBasket` slips from `slips.json` (clearing the basket and removing their empty task clothespins). Any *unfinished* slips still hanging on the line at `04:00 AM` **stay on the line** for the new day and acquire slightly weathered paper edges—tearing is the only completion verb, and Varal never retires an unfinished task on the user's behalf.

---

## Board 6: First-Run / Empty State & Get Long Weekend Two-State Matrix

### Structural Wireframe (Grayscale Blueprint)

```
+--------------------------------------------------------------------------------------------------+
| [] Finder  File  Edit  View  Go  Window  Help                      [⊶1]  Tue 17 Nov 08:00  100% |
+==================================================================================================+
| ~~~\~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\~~~~~~~~~~~~~~~~~~~~~~~~~~~\~~~~~~~~~~~~~~~~~~~~~~~~~~ |
|     |                                     |                           |                          |
|  +--[=]-------[=]-+                    +--[=]- - - - - +           +--[=]-------[=]-+            |
|  | ATMOS          |                    :  FIRST SLIP   :           | GET LONG WKND  |            |
|  | +------------+ |                    :               :           | (STATE A:      |            |
|  | |   ( O )    | |                    :  Pin your     :           |  DISCOVERY)    |            |
|  | | 16°C       | |                    :  first task   :           |                |            |
|  | +------------+ |                    :  for today    :           | Next Holiday   |            |
|  | [Set City ↗]   |                    :      |        :           | Bridge: 12d    |            |
|  +----------------+                    :      v        :           | Turn 1 PTO day |            |
|                                        :  (Pull down   :           | into 4 off     |            |
|                                        :   to tear)    :           | [Plan Dates ↗] |            |
|                                        + - - - - - - - +           +----------------+            |
+--------------------------------------------------------------------------------------------------+
| DETAIL COMPARISON: GET LONG WEEKEND TWO-STATE LIFECYCLE + DEEP-LINK CONTRACT                     |
|                                                                                                  |
|  +-------------------------------+   Deep-Link (Idempotent)   +-------------------------------+  |
|  | STATE A: DISCOVERY CARD       |  varal://weekend?start=... | STATE B: PERSONAL COUNTDOWN   |  |
|  | (Calm, removable product card)|  &end=...&plan=...         | (Multi-Block Plan Support)    |  |
|  |-------------------------------| =========================> |-------------------------------|  |
|  | "Holiday Bridge Detected"     |                            | Counts down to NEXT block:    |  |
|  | 1 PTO -> 4 Consecutive Days   |                            | "Feriadão em 12 dias"         |  |
|  |                               |                            | Jun 4 - Jun 7 (Block 1 of N)  |  |
|  | CTA: [Select Vacation Dates   |                            |                               |  |
|  |       on getlongweekend.ca ↗] |                            | Each block spawns its own     |  |
|  +-------------------------------+                            | passive "[PTO]" reminder slip |  |
|                                                               | on the line. Re-hanging same  |  |
|                                                               | plan updates idempotently.    |  |
|                                                               +-------------------------------+  |
+--------------------------------------------------------------------------------------------------+
```

### Annotations
* **Visual Hierarchy:**
  1. **Bare Line + Single Onboarding Slip:** On first launch, the clothesline hangs with **Atmos** (defaulting to IP/system locale with a `[Set City]` caption), **Get Long Weekend** in **State A (Discovery)**, and a single dashed-border instructional slip in the center: `"Pin your first task for today — pull down to tear off"`.
  2. **Get Long Weekend State Machine & Boundary Contract (Right Anchor):**
     * **State A (Discovery Card):** A calm, removable product piece (never advertising inventory) highlighting the next regional bridge opportunity (e.g., *"Turn 1 PTO day into 4 days off"*). Clicking `[Plan Dates ↗]` opens `getlongweekend.ca` in the user's browser. If the user does not want the card on their line, they can remove/hide it cleanly.
     * **State B (Multi-Block Personal Countdown + Passive Slip Spawner):**
       * **Varal's Scope:** Varal registers the `varal://` URL scheme and handles `varal://weekend?start=...&end=...&plan=...` by switching the Get Long Weekend card to State B idempotently. State B supports multiple vacation blocks within a single plan: the card always counts down to the *next* upcoming block (`"Feriadão em 12 dias"`), each block spawns its own passive tear-off reminder slips (e.g., `"Request Friday PTO"`) onto the clothesline at its milestone threshold, and re-hanging the same `plan` updates the card and its slips idempotently without duplicating them.
       * **External Dependency (`getlongweekend.ca` Scope, Not a Varal Deliverable):** The `"Hang on Varal"` option in the `getlongweekend.ca` Share menu fires `varal://weekend?start=...&end=...&plan=...`; if Varal is not installed, `getlongweekend.ca` falls back to copying the plan link to the clipboard with one line explaining Varal.
* **What Moves and Why:**
  * **Pin-On Bounce Animation:** When the user tears off the onboarding slip or adds their first real task from the menu bar, a wooden clothespin drops onto the line (`Δy` dips by `10pt` then settles by `4.5pt`), visually teaching the weight-to-sag relationship (unless macOS **Reduce Motion** or **Pause Breeze** is active).

---

## Resolved Product & Architecture Rulings

1. **Unfinished Tasks at `04:00 AM` Rollover:** Unfinished slips **stay on the line** after the `04:00 AM` rollover and acquire slightly weathered paper edges. Tearing is the only completion verb—the app never retires a task for the user.
2. **Display Selection & Portrait Mode:** Varal lives on a **single user-selected display** chosen in Settings (default: main display; no mirroring or second instance). On portrait displays (`height > width`), Varal stacks two parallel clotheslines vertically (Line 1: big companion pieces; Line 2: task slips) with the basket at the bottom of the screen. The Occlusion & Power Governor evaluates window coverage on the chosen display only.
3. **Immutable Paper Slips:** Slips are **immutable paper** with no inline text editing. To fix a typo, tear the slip off into the basket and pin a new one.
4. **Accessibility (`Reduce Motion`):** Enabling macOS **Reduce Motion** (`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`) automatically pauses all breeze sway and weather particles, matching the behavior of **Pause Breeze**.
