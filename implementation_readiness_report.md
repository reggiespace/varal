# Stage 9: Implementation Readiness Test Report (`DetailedRange`: Lines 328..401)

* **Target Document:** [docs/designs/varal.md](./docs/designs/varal.md) (`328..401`)
* **Reviewers:** `egm-implementation-readiness`, `egm-codebase-details`, `egm-style`
* **Standards Applied:** `implementation-readiness-standard`
* **Date:** 2026-11-18

---

## Part 1: Implementation Readiness & Codebase Details (`egm-implementation-readiness` & `egm-codebase-details`)

### Finding IR-1: SwiftPM Executable Target (`Package.swift`) vs. `.app` Bundle Packaging for `Info.plist` (`LSUIElement` & `varal://`)
* **Severity:** Major
* **Affected Scope:** Section 4.2, Items 4 & 5 (`Package.swift` and `Varal/Info.plist`, lines 341–344).
* **Readiness Gap:** Item 4 specifies a standalone SwiftPM `Package.swift` executable target (`Varal`), and Item 5 specifies `Varal/Info.plist` configuring `LSUIElement = true` and `CFBundleURLSchemes = ["varal"]`. In SwiftPM (`swift build`), an `.executableTarget` produces a bare command-line binary (`.build/debug/Varal`), does not assemble a `Varal.app` bundle, and rejects an unhandled `Info.plist` inside the target source directory unless listed in `exclude: ["Info.plist"]`. Furthermore, macOS Launch Services (`lsregister`) only registers `CFBundleURLSchemes = ["varal"]` (`varal://weekend?...`) from a `.app` bundle structure (`Varal.app/Contents/Info.plist` + `Varal.app/Contents/MacOS/Varal`).
* **Recommendation:** Specify in Item 4 (`Package.swift`) that `exclude: ["Info.plist"]` and linker flags (`-Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Varal/Info.plist`) are configured on the `Varal` target, and specify in Item 5 (`Varal/Info.plist`) how the build packages `.build/release/Varal` and `Varal/Info.plist` into `Varal.app/Contents/` so Launch Services registers `varal://` and `LSUIElement = true`.

### Finding IR-2: Missing `@MainActor var pieceView: NSView { get }` & Supporting Types on `CompanionPiece`
* **Severity:** Major
* **Affected Scope:** Section 2.3.1 (lines 155–162), Section 4.3 Item 7 (`CompanionPiece.swift`, line 352), Section 4.4 Items 12 & 13 (`AtmosPiece.swift`, `GetLongWeekendPiece.swift`, lines 365–368), and Section 4.5 Item 19 (`ClotheslineCanvasView.swift`, lines 381–383).
* **Readiness Gap:**
  1. `CompanionPiece` declares metadata and physics properties (`pieceID`, `displayName`, `sizeMetrics`, `pinCount`, `preferredSide`, `environmentalBroadcast`), while forbidding `ClotheslineCanvasView` from referencing `AtmosPiece` or `GetLongWeekendPiece` by name. Without a view property (`@MainActor var pieceView: NSView { get }`) on `CompanionPiece`, `ClotheslineCanvasView` cannot mount or transform a piece's card view (`WKWebView` or countdown card) without downcasting.
  2. Section 2.3.2 names `WeakScriptMessageHandler`, `PrecipitationState`, and `SolarPhase`, which need explicit file ownership in Items 7 and 12.
* **Recommendation:**
  1. Add `@MainActor var pieceView: NSView { get }` to `CompanionPiece` in Section 2.3.1 and Item 7 (`Varal/Contracts/CompanionPiece.swift`), and explicitly list `PrecipitationState` and `SolarPhase` in Item 7.
  2. State in Item 12 (`Varal/Pieces/AtmosPiece.swift`) that it defines the internal `WeakScriptMessageHandler` proxy class and supplies its card container view via `pieceView`, and state in Item 13 (`GetLongWeekendPiece.swift`) that it supplies its State A / State B card view via `pieceView`.

### Finding IR-3: Missing Data Source Contract for Get Long Weekend State A (Discovery) & Reminder Slip Copy / `ptoDaysCount`
* **Severity:** Major
* **Affected Scope:** Section 2.5 (lines 229–261) and Section 4.4 Items 9, 13, 14, 15 (`VacationPlan.swift`, `GetLongWeekendPiece.swift`, `HolidayPlanStore.swift`, `URLSchemeRouter.swift`, lines 357, 367–372).
* **Readiness Gap:**
  1. **State A (Discovery) Data Source:** Before any `varal://weekend` deep link is received, what does `GetLongWeekendPiece` display in State A? The spec does not state whether State A displays static local discovery copy or fetches a remote endpoint.
  2. **Unused `ptoDaysCount: Int?` on `VacationBlock`:** `VacationBlock` (line 231) declares `let ptoDaysCount: Int?`, but `varal://weekend?start=...&end=...&plan=...` (line 247) has no query parameter for PTO count.
  3. **Spawned Reminder `TaskSlip` Copy:** When a vacation block reaches `T-7 days`, `HolidayPlanStore` (Item 14) pins a reminder `TaskSlip`, but the deterministic `timeLabel` and `title` format for that slip are not specified for implementers and unit tests (`URLSchemeRouterTests.swift`, Item 23).
* **Recommendation:**
  1. Specify in Section 2.5.2 and Item 13 (`GetLongWeekendPiece.swift`) that State A renders a deterministic local discovery card (static copy `"Turn 1 PTO day into 4 days off"` with a button opening `https://getlongweekend.ca` via `NSWorkspace.shared.open(_:)`, requiring zero network calls in Varal). Also clarify that big pieces are removed/hidden strictly via the Settings checkboxes (`enabledCompanionPieceIDs`), never by downward tear-off.
  2. Remove unused `ptoDaysCount: Int?` from `VacationBlock` (computing total days off directly from `startDate..endDate`).
  3. Specify the deterministic reminder `TaskSlip` format spawned by `HolidayPlanStore`: `timeLabel = "T-7d"` and `title = "Long weekend (\(startDate) – \(endDate)) — confirm time off"`.

### Finding IR-4: Sync Discrepancies in Workspace `wireframe.html` vs. Item 3 & Section 2 Formulas
* **Severity:** Major
* **Affected Scope:** Section 4.1 Item 3 (`wireframe.html`, lines 338–339) vs. actual file [wireframe.html](./wireframe.html).
* **Readiness Gap:** Auditing the live code in `/Users/reggie/personal/projetos/varal/wireframe.html` against the updated specification in `docs/designs/varal.md` found three drifts:
  1. `computeCurrentSag()` (`wireframe.html` lines 872–876) computes `14 + activeCount * 5.2 + moistureBonus` (`rain = 9`) without the `54pt` ceiling clamp, instead of `Math.min(54, 8 + 12 + activeCount * 4.5 + moistureBonus)` (`rain = 8`, `snow = 5`).
  2. `handleQuickAdd()` (`wireframe.html` line 1126) defaults an omitted time prefix to `'TODAY'` instead of the current local `HH:mm` timestamp specified in Section 2.5.1 and Item 10.
  3. `pinGLWReminderSlip()` (`wireframe.html` line 1109) uses `time: 'T-12d'` instead of `'T-7d'` specified in Section 2.1, Section 2.5.2, and Item 14.
* **Recommendation:** Update `wireframe.html` lines 872–876, 1109, and 1126 so the prototype's math and labels match `docs/designs/varal.md` and `wireframe_spec.md`.

---

## Part 2: Style & Copy Consistency (`egm-style`)

### Finding ST-9.1: Contradictory `"archival trigger"` Terminology in Item 21 (`LaundryBasketView.swift`)
* **Severity:** Major
* **Affected Scope:** Section 4.5, Item 21 (`Varal/UI/LaundryBasketView.swift`, line 387).
* **Discrepancy:** Line 387 still describes `[Limpar cesto]` as `"the manual [Limpar cesto] archival trigger"`, contradicting Stage 7's deletion rule (`"no .archived state"`, `"permanently deletes .inBasket slips"` in lines 242, 355, 359, 396). Replace `"archival trigger"` with `"deletion action"`.

### Finding ST-9.2: Subjective Adjectives & Phrase Repetition in Items 13 & 24
* **Severity:** Nit
* **Affected Scope:** Section 4.4 Item 13 (`GetLongWeekendPiece.swift`, line 368) and Section 4.6 Item 24 (`RolloverAndStoreTests.swift`, lines 395–396).
* **Recommendation:**
  * In Item 13 (line 368), replace `"Renders State A (calm, removable Discovery card linking to getlongweekend.ca..."` with `"Renders State A (local Discovery card opening https://getlongweekend.ca..."`.
  * In Item 24 (lines 395–396), tighten the repeated `"the 04:00 AM rollover"` clause into a single direct sentence.
