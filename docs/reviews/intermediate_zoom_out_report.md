# Stage 8: Intermediate Zoom Out Review (`egm-zoom-out`)

* **Target Document:** [docs/designs/varal.md](../designs/varal.md) (`1..401`, full file)
* **Prior Report Context:** [zoom_out_report.md](./zoom_out_report.md)
* **Companion Artifacts Audited:** [concepts_brief.md](../product/concepts_brief.md), [wireframe_spec.md](../designs/wireframe_spec.md), [wireframe.html](../designs/wireframe.html)
* **Date:** 2026-11-18

---

## 1. Stage 5 Findings Verification (`ZO-1` through `ZO-4`)

All four Stage 5 Zoom Out findings were resolved in [docs/designs/varal.md](../designs/varal.md):

1. **`ZO-1` (Resolved):** Speculative `"Line 3+"` multi-rope reservation in Portrait Layout Mode was removed from `docs/designs/varal.md` (Lines 38, 96–97, 125–128, 324, 383). Portrait mode strictly models 2 parallel ropes in V1 (`Line 1` for big companion pieces, `Line 2` for small task slips).
2. **`ZO-2` (Resolved):** Unused polling members (`updateCadence` and `refreshData() async`) were removed from the `CompanionPiece` protocol in Section 2.3.1 (Lines 155–162) and Section 4.3 (Line 353).
3. **`ZO-3` (Resolved):** The redundant `CompanionPieceRegistry.swift` file was eliminated. `activeBigPieces` is filtered directly against `UserDefaults` (`enabledCompanionPieceIDs: [String]`) via a static helper on `CompanionPiece` / `VaralApp` (Lines 165, 348, 353).
4. **`ZO-4` (Resolved):** Relative paths from `docs/designs/varal.md` to workspace-root artifacts use `../../` (Lines 6, 288, 295, 334–339).

---

## 2. Evaluation of Stage 6 (Comprehension) & Stage 7 (Critic) Additions

The additions introduced during Stages 6 and 7 were audited for YAGNI, architectural bloat, or altitude drops:

* **Hit-Testing & Z-Order Check (`NSWindow.windowNumber(at:belowWindowWithWindowNumber:)` + `isFlipped` + `.activeAlways` tracking area, Lines 120, 135–136):** Necessary and minimal. Replaces expensive 60–120Hz `CGWindowListCopyWindowInfo` calls on `.mouseMoved` with a single-point z-order query while preventing click-stealing behind covering standard windows.
* **`WKWebView` Weak Script Handler, Origin Validation & Occlusion Snapshot Suspension (Lines 167, 180–181):** Appropriate boundary hygiene and battery mitigation for an always-on desktop `WKWebView`; directly fulfills the `0fps` occlusion governor goal without adding new abstractions.
* **Catenary Sag Clamp (`min(54pt, ...)`), Empty-Pin Compression (`18pt`), and Dynamic Fan Pitch (Lines 197–205):** Simple scalar bounds inside existing layout math that prevent multi-day weathered slips from sagging off-screen or pushing big cards out of bounds.
* **Removal of `.archived` State from `SlipState` (Lines 217–219, 250, 355):** Deleting `.inBasket` slips on `04:00 AM` rollover or `[Limpar cesto]` rather than persisting an ever-growing `.archived` history in `slips.json` reduces data model and storage complexity.
* **Authoritative Multi-Block Replacement in `HolidayPlanStore` & Quick-Add `HH:mm` Prefix Parsing (Lines 248, 256–258):** Keeps the deep-link sync stateless/idempotent and defines how `timeLabel` is populated without adding extra UI fields.

---

## 3. Remaining Findings

No Blocker or Major findings exist in `docs/designs/varal.md`. One minor cross-artifact consistency nit remains in the companion markdown files:

### Finding ZO-5: Residual Mentions of `ZO-1` ("Line 3+") and `ZO-2` (`updateCadence`) in Companion Docs
* **Severity:** Nit
* **Affected Scope:** [concepts_brief.md](../product/concepts_brief.md#L21-L22) (lines 21–22) and [wireframe_spec.md](../designs/wireframe_spec.md#L11) (lines 11, 312).
* **Simplicity Rationale:** While `docs/designs/varal.md` removed the speculative `"Line 3+ reserved for future piece types"` rule (`ZO-1`) and the unused `updateCadence` property (`ZO-2`), `concepts_brief.md` still mentions `"Line 3+ reserved for future piece types"` and `updateCadence`, and `wireframe_spec.md` still mentions `"further lines reserved for future piece types"` / `"Line 3+: reserved for future piece types"`. The target design document `docs/designs/varal.md` itself is already clean.
