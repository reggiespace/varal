# Varal — logo handoff (Direction 2b · "Varal, refined")

Chosen direction: **2b** — the whole clothesline, edited down. Source canvas (all directions, rationale):
https://claude.ai/artifact/GGRq6XN3d2f4EQ6nSLHgPe#artboard-D2b-Varal-refined

## Files

```
logos/
├── HANDOFF.md                       ← this file
├── app-icon/
│   ├── Varal.icns                   ← ready to ship (11 slots, small art in 16/32 slots)
│   ├── AppIcon.iconset/             ← source PNGs for `iconutil` (see below)
│   ├── varal-icon.svg               ← master, large art (used ≥ 128 px)
│   ├── varal-icon-small.svg         ← master, small art (used only for 16, 16@2x, 32, 32@2x)
│   └── varal-icon-1024.png
├── menu-bar/
│   ├── MenuBarIconTemplate.png      ← 14 × 16 px, 1x, hand-placed pixels
│   ├── MenuBarIconTemplate@2x.png   ← 28 × 32 px, @2x
│   └── MenuBarIconTemplate(.svg|@2x.svg)   ← sources
├── lockup/
│   ├── varal-wordmark.svg           ← "Varal", Nunito ExtraBold 800, outlined (no font needed)
│   ├── varal-lockup-color.svg / @2x.png
│   ├── varal-lockup-mono-black.svg / @2x.png
│   └── varal-lockup-mono-white.svg / @2x.png
└── previews/                        ← real-size renders, nearest-neighbour zoomed (not assets)
    ├── actual-size-1x-zoomed.png
    ├── actual-size-retina-zoomed.png
    ├── menubar-glyph-before-after.png
    └── varal-2b-actual-size-retina.png ← unzoomed retina preview (differs from zoomed render)
```

## Rules that matter

- **Two icon drawings, by size.** The large art turns to mush below 64 px; the small art (deeper sag, blue card + outlined slip, big pegs, nothing inside) is what goes in the 16/32 px slots. Never downscale `varal-icon.svg` into those slots.
- **Menu bar glyph is pixel-tuned.** Ship the PNG pair, not a resampled SVG/PDF. 1x is hand-placed on the 14 × 16 grid; @2x is the smooth version. 14 pt wide so it sits tight against the slip count.
- **Template image.** Pure black + alpha. The `Template` suffix makes `NSImage(named:)` mark it as a template automatically; set `isTemplate = true` anyway.
- **Lockup clear space:** half the icon tile height on all sides. Mono lockups use the @2x glyph geometry.

## Integration (for Claude Code)

The app is a SwiftPM executable assembled into `dist/Varal.app` by `scripts/assemble-app.sh`, with `LSUIElement = true` (no Dock icon — the app icon shows in Finder, Spotlight, Login Items, About).

1. **App icon**
   - Optional but preferred on macOS: regenerate the `.icns` with Apple's tool so it matches system expectations exactly:
     `iconutil -c icns logos/app-icon/AppIcon.iconset -o logos/app-icon/Varal.icns`
     (the shipped `Varal.icns` was assembled by hand from the same PNGs; byte-identical image data.)
   - `scripts/assemble-app.sh`: after creating `Contents/Resources`, add
     `cp "$ROOT/logos/app-icon/Varal.icns" "$DEST/Contents/Resources/Varal.icns"`
   - `Varal/Info.plist`: add `<key>CFBundleIconFile</key><string>Varal</string>`.
2. **Menu bar glyph** (`Varal/UI/MenuBarController.swift`, currently `button.title = "[⊶ \(n)]"`)
   - `assemble-app.sh`: copy both `logos/menu-bar/MenuBarIconTemplate*.png` into `Contents/Resources/`. Prefer this over SwiftPM `resources:` — `Bundle.module` in a hand-assembled `.app` looks for the resource bundle at the `.app` root, which breaks code signing.
   - Load with `NSImage(named: "MenuBarIconTemplate")` (picks @2x automatically), set `isTemplate = true`, `size = NSSize(width: 14, height: 16)`.
   - `button.image = image; button.imagePosition = .imageLeading; button.title = "\(n)"` (keep the count; drop the `[⊶ ]` text). Add `button.setAccessibilityLabel("Varal, \(n) slips")`.
   - Fallback if the image is missing: keep the current title so the item never disappears.
3. **Verify for real** (the renders here are from Chromium, not macOS): build, run, and check the glyph next to the count in the actual menu bar in Light, Dark, a tinted/translucent wallpaper, and System Settings › Accessibility › Display › Increase contrast. Check the icon in Finder list view (16 px) and Get Info (32/128 px).

## Palette

| Role | Hex |
|---|---|
| Linen tile (top → bottom) | `#FCF7EE` → `#EEE2CC` (small art `#FAF3E6` → `#EADCC2`) |
| Rope | `#6E5946` (small art `#5E4A39`) |
| Companion card — blue | `#3F7CC4`, sun `#FFE2A6` |
| Companion card — coral | `#EE7350` |
| Slip paper / tinted edge | `#FFFCF6` / `#D49A6A` (small art edge `#C9804D`) |
| Peg wood (light / shade) | `#EFC68C` / `#DDAE6C` (small art `#E9B26A` / `#D49A4E`) |
| Peg spring | `#9CA8B6` (small art `#7D8896`) |
| Wordmark ink | `#4A3A2C` |

Wordmark: **Nunito ExtraBold (800)**, letter-spacing −0.015 em, already outlined in `varal-wordmark.svg` (SIL OFL font).

Icon geometry: macOS 1024 grid, 824 px continuous-corner body (superellipse n≈5) at 100 px inset, drop shadow 0/10/10 at 30 % black.
