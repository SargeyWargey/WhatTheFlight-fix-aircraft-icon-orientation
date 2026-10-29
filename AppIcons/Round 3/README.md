# Round 3 app icons

Fourteen alternates for iPhone and iPad (Settings → Display → App Icon), reviewed at
https://claude.ai/artifact/1KRtbk5NcjRQBz7LEo7M7T and added October 2026:

- **What the…?!** (playful): Interrobang, Cloud Mark, Wide-Eyed, Loop-the-Loop, Double Take,
  Tail Fin, Departure Board, Bird or Plane?
- **Planes by the Numbers** (aircraft and stats): Trend Contrail, Sky by the Hour, Heading Rose,
  Tally, Badge Ring, Collection

Each comes in three looks, so it can be kept light or dark whatever the Home Screen is set to:

| Asset | Slots | Shows |
|---|---|---|
| `AppIcon-<Name>.appiconset` | any (light), dark, tinted | follows the Home Screen (Automatic) |
| `AppIcon-<Name>Light.appiconset` | any (light), tinted | always light (no dark slot, so iOS has nothing to swap in) |
| `AppIcon-<Name>Dark.appiconset` | any (dark), tinted | always dark |
| `IconPreview-<Name>.imageset` | 240 px, light + dark appearance | the picker's tile |

A tinted Home Screen always shows the tinted art; apps can't change that.

- `icon-render.html` — the source: every icon drawn as SVG on a 100-unit square, the same code as
  the review page. Open it with a hash to see one: `icon-render.html#tally,dark,1024`.
- `render.sh` — renders all fourteen in light, dark and tinted with headless Chrome, flattens
  them (app icons can't have an alpha channel) and writes the sets above into
  `WhatTheFlight/Assets.xcassets`. Needs Google Chrome and Python with Pillow.

The choices live in `Services/AppIconChoice.swift` (`AppIconConcept` + `AppIconChoice.Look`) and
the picker in `UI/AppIconPicker.swift`. Each 1024 px image is stored once per idiom (iPhone,
iPad) in the compiled catalog, about 11 MB for all fourteen; App Store thinning sends a device
only its own idiom's, about 5.5 MB.
