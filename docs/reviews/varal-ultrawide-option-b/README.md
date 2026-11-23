# Varal ultrawide Option B evidence

The before/after captures below were rendered offscreen from the app layout at the named display dimensions; they are not photographs of a physical display. `before` is the proportional-thirds layout and `after` is Option B. At 3440×1440, collapsed and expanded states show a 24 pt gap from each large piece to the cluster, with both pieces yielding outward as the cluster expands. At 1920×1080, collapsed and expanded layout coordinates are identical before and after: Atmos minX 24 pt and Get Long Weekend minX 1726 pt.

## Captures

| Display and state | Before | After |
| --- | --- | --- |
| 3440×1440, collapsed | ![Before, 3440×1440 collapsed](before-3440x1440-collapsed.png) | ![After, 3440×1440 collapsed](after-3440x1440-collapsed.png) |
| 3440×1440, expanded | ![Before, 3440×1440 expanded](before-3440x1440-expanded.png) | ![After, 3440×1440 expanded](after-3440x1440-expanded.png) |
| 1920×1080, collapsed | ![Before, 1920×1080 collapsed](before-1920x1080-collapsed.png) | ![After, 1920×1080 collapsed](after-1920x1080-collapsed.png) |
| 1920×1080, expanded | ![Before, 1920×1080 expanded](before-1920x1080-expanded.png) | ![After, 1920×1080 expanded](after-1920x1080-expanded.png) |

## Findings audit

### Already resolved in main

- **review-4:** Tearing a slip preserves its clothespin and neighboring positions; `ClotheslineCanvasView.swift` tear handling leaves slot geometry stable, covered by `tearLeavesPinWithoutShifting`.
- **review-5:** During downward drag the slip follows the pointer until the 48 pt tear threshold; `TaskSlipView.swift` drag tracking is covered by `dragPointerFollowing`.
- **review-6:** Basket undo requires an upward drag; `LaundryBasketView.swift` handles the drag gesture, covered by `basketClickDoesNothingDragUndoes`.
- **review-10:** Atmos suspends WKWebView rendering and timer updates on non-visible spaces while displaying its static snapshot; `AtmosPiece.swift` suspension path implements this behavior.
- **review-13:** English and Portuguese UI chrome strings are present in `UIStrings.swift` and used by `MenuBarController.swift`; covered by `menuBarAndSettingsStringsBilingual`.
- **review-14:** Clicking the laundry basket does not undo; `LaundryBasketView.swift` click handling is a no-op, covered by `basketClickDoesNothingDragUndoes`.

### Fixed now

- None. No valid findings remained unfixed in this audit.

### No longer applicable

- **review-12:** Rollover persistence across app quit is outside the current contract: `docs/designs/varal.md` §2.5.1 and correction C9 define rollover as in-memory while running and specify that a quit through 04:00 AM misses rollover until the next boundary while running.
