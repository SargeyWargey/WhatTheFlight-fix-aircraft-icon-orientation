# Ambient Map — spec

A third way to look at the same radar. The radar face compresses the sky into bearing and
distance; the map puts the geography back: approach paths lining up for the airport, the
news helicopter tracing the interstate, a heavy's fifteen-minute trail curving onto final.
On Apple TV it is designed to be left on in a room, like a living wallpaper of your
airspace. On iPad it sits beside the radar in landscape.

Everything here builds on code that already exists: the per-flight MapKit map in
`UI/FlightDetailSheet.swift` (`DetailMap`, also used on tvOS from `UI/TV/TVFlightScreens.swift:78`),
the trails `RadarModel` already records, `AircraftGlyph`, `Palette.blip(for:)`, the TV dock
in `UI/TV/TVRadarScreen.swift`, and `RadarSettings`. Read `CLAUDE.md` first, then those files.

**It is a feature the user turns on and off.** With it off, every screen behaves exactly as
it does today. See "The switch" below before anything else.

---

## 1. Goals and non-goals

Goals
- A full-screen live map of every aircraft inside the radius, with trails, the radius ring,
  the airports that matter right now, and a compact card for the focused aircraft.
- On Apple TV: a view you switch to from the dock, driven by the same remote grammar as the
  radar, that settles into an ambient display when left alone.
- On iPad: the same map as a second pane next to the radar in landscape.
- One shared `TrafficMap` view, so the two platforms and the existing detail map share code.

Non-goals (do not build these)
- No map on the iPhone's main screen. The iPhone keeps the radar face (see `Working Spec.md`).
- No change to the Apple Watch.
- No camera drift, flyover, 3D or pitched map. Ambient means still.
- No new data sources. Everything comes from `RadarModel`, `AirportCatalog` and MapKit.
- No change to the detail sheet's Nearby / Full Route modes beyond extracting shared code.

---

## 2. The switch

Three new settings in `Services/RadarSettings.swift`, following the existing `Key` /
`save(_:_:)` pattern so `-wtf.<key>` launch arguments override them for free.

| Setting | Key | Type | Default | Meaning |
|---|---|---|---|---|
| `mapView` | `wtf.mapView` | Bool | `true` | The feature switch. Off = no Map dock item on TV, no iPad pane, nothing else changes. |
| `tvView` | `wtf.tvView` | `TVView` enum `radar` / `map` | `.radar` | Which view the TV shows. Remembered across launches. |
| `mapNorthUp` | `wtf.mapNorthUp` | Bool | `false` | Map rotates so "up" is the TV's facing direction (like the radar face). On = north up. |

Rules
- `mapView == false` must leave the app indistinguishable from today. Guard every entry
  point on it: the dock item, the TV view switch, the iPad pane, the settings rows that
  depend on it (`mapNorthUp` hides when the feature is off).
- If `mapView` is switched off while the TV is showing the map, the TV returns to the radar
  immediately (observe the setting in `TVRadarScreen`, and clamp at init: `tvView` is treated
  as `.radar` whenever `mapView` is false).
- `resetToDefaults()` resets all three.
- The default for `mapView` is **on** so people find it from the dock. If you'd rather ship
  it dark, flip the one default; nothing else depends on it.

Where the user finds it
- **Apple TV**: Settings → Display pane (`UI/TV/TVSettingsView.swift`, next to the
  "Topographic background" / "Compass bezel" / "Radar sweep" rows, ~line 453). Two
  `TVToggleRow`s: "Map view" (symbol `map.fill`) and, only while Map view is on,
  "Map north up" (symbol `location.north.line.fill`). Footer under Map view:
  "Adds a Map item to the dock: a live map of every aircraft around you."
- **iPad**: Settings → Display section (`UI/RadarSettingsSheet.swift`, `displaySection`,
  ~line 194). Same two toggles, shown only when `UIDevice.current.userInterfaceIdiom == .pad`.
  Footer: "In landscape, shows a live map beside the radar."
- **iPhone**: no rows, no effect.

Launch arguments (for screenshots and UI tests; no code needed beyond the settings):
`-wtf.mapView NO`, `-wtf.tvView map`, `-wtf.mapNorthUp YES`. Combine with the existing
`-wtf.demoTraffic YES -wtf.debugSpot 33.749,-84.388` on the TV.

---

## 3. What the viewer sees

### Apple TV (1920 × 1080 points, `scale = 1.7` like the radar)

```
┌──────────────────────────────────────────────────────────────────────────┐
│ ● 14 overhead · Atlanta, GA · 20 mi                       (status badge) │
│                                                                          │
│            ╭─────────── radius ring (dashed) ───────────╮                │
│         ╭──╯        ✈ DL570                              ╰──╮            │
│        │               30,000 ft    ·‥‥‥‥✈ (trail)          │           │
│        │                                         ✈ N44RH     │           │
│        │                  ● You · Atlanta                    │           │
│        │        ▲ATL                                         │           │
│         ╰──╮        ✈ SWA2533  ‥‥‥‥‥‥‥‥‥‥·               ╭──╯            │
│            ╰─────────────────────────────────────────────╯                │
│                                              ┌─────────────────────────┐ │
│                                              │ Delta Air Lines         │ │
│                                              │ DL570    SFO → ATL      │ │
│                                              │ B752 · 30,000 ft · 300  │ │
│                                              │ Closest pass 1 mi 1:12  │ │
│                                              └─────────────────────────┘ │
│   ◀ ▶ aircraft   click details   ⏯ pin   ▼ dock          (remote hints) │
└──────────────────────────────────────────────────────────────────────────┘
```

- **Base map**: the SwiftUI `Map` with
  `.mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))`.
  Muted greys the roads and labels back so the glyphs carry the screen. If `emphasis:` is
  unavailable on tvOS, fall back to `.standard(elevation: .flat, pointsOfInterest: .excludingAll)`
  under a `Palette.paper.opacity(0.35)` overlay with `.blendMode(.multiply)` in light and
  `.plusLighter` in dark. Appearance follows `settings.appearance` as everywhere else.
- **Framing**: centred on the observer, zoomed so the radius ring fits with clear space for
  the hero card in the bottom-right. Rotated so "up" is `settings.tvFacingDegrees` unless
  `mapNorthUp`. The camera does not move otherwise (see "Behaviour").
- **The ring**: the dashed `MapCircle` from `DetailMap`, plus two fainter circles at half
  and quarter radius echoing `RangeRings` in `UI/RadarBackdrop.swift`.
- **You**: the `DetailMap` observer dot, labelled with the place name on TV.
- **Aircraft**: one `Annotation` per in-range contact. `AircraftGlyph(silhouette:size:)`
  rotated by `flight.track`, filled with `Palette.blip(for: flight)`. The focused aircraft is
  `Palette.signal` with the same pulse ring `AircraftBlip` uses in `UI/PerimeterLayer.swift`.
  No label on the map: the radar (Split, iPad, Duo) or the hero card (TV Map) already shows
  the focused aircraft's callsign and altitude, so the map carries only glyphs and paths.
  Contacts in `outsideContacts` within `radiusMiles * 1.5` are drawn at 40 % opacity, so you
  see traffic about to enter.
- **Trails**: for every drawn aircraft, `model.trail(for:)` + the current coordinate as a
  `MapPolyline`, split into three segments by age: newer than 5 min at opacity 0.9, 5–10 min
  at 0.5, 10–15 min at 0.25, stroked `Palette.route`, width 3 × scale, round caps. The focused
  aircraft also gets the dashed 10-minute projected path `DetailMap` already draws.
- **Airports that matter right now**: an `AirportPin` (from `FlightDetailSheet.swift`) for
  every airport inside the visible bounds that is the origin or destination of a drawn
  flight. Nothing else, or busy regions fill with airstrips.
- **Chrome**: `StatusBadge` (`UI/RadarScreen.swift:210`) top-left. Bottom-right, a card on
  `.glassSurface(in:)` holding `FlightHero(contact:isPinned:heading:wideStats: true, detailScale: 0.9)`
  for the focused aircraft; when nothing is focused the card shows the same `CenterStateView`
  copy the radar uses. `RemoteHints` footer and the dock stay exactly where they are.
- **Notices** (`model.notice`) appear as they do on the radar.

### iPad (landscape, regular width)

```
┌───────────────────────┬──────────────────────────────────────┐
│                       │                                      │
│    radar face         │          TrafficMap                  │
│   (RadarScreen,       │   interactive: pan / zoom            │
│    unchanged)         │   ⊙ recentre button, bottom-right    │
│                       │                                      │
└───────────────────────┴──────────────────────────────────────┘
```

- Radar on the left at its natural width (square-ish, full height), map fills the rest.
- Both read the same `RadarModel`, so focus stays in sync. Tapping a glyph on the map calls
  `model.focus(on:)` with the same `withAnimation(.snappy)` the perimeter uses.
- The map is pannable and zoomable; a recentre button (symbol `location.fill`) bottom-right
  snaps back to the fitted frame. No hero card on iPad: the radar beside it is the hero.
- Portrait iPad and compact width: no pane, radar only, exactly as today.

---

## 4. Behaviour

Remote (TV)
- Unchanged: ◀ / ▶ `focusPrevious` / `focusNext`, click opens details, ⏯ pin, ▼ dock,
  MENU from the dock returns focus. The focus anchor stays the hero button; the map must
  never take focus or respond to the touch surface (`interactionModes: []`, `.disabled(true)`,
  `.focusable(false)`), or swipes stop reaching `onMoveCommand`.
- The dock gains a sixth item. `DockItem` becomes `nearest, pin, aircraft, logbook, map, settings`.
  Title "Map" / symbol `map.fill` on the radar; "Radar" / `scope` when the map is showing.
  Pressing it flips `settings.tvView` and returns focus to the hero. Only present when
  `settings.mapView`.
- Update `RemoteHints` if it enumerates dock items.

Ambient settle (TV only)
- After 30 s without remote input, the status badge and remote hints fade out
  (`opacity 0`, `.smooth(duration: 1.2)`); the map and the hero card stay. Any remote
  event (`onMoveCommand`, `onPlayPauseCommand`, `onExitCommand`, a dock press) brings them
  back and restarts the timer. Implement with `@State private var lastInput = Date()` and
  `.task(id: lastInput)` sleeping 30 s.
- Screen sleep: respect `keepScreenAwake` as today. The first time the map opens with it
  off, post one notice: "Turn on Keep screen awake in Settings to leave the map running"
  (`model.post(notice:symbol: "sun.max.fill")`). Remember you've said it in
  `UserDefaults` key `wtf.mapAwakeHintShown`.

Camera
- Fit the ring once (plus the hero card's clear space on TV). Do not chase the focused
  aircraft; a drifting camera is what makes ambient displays feel restless.
- One exception: a **pinned** aircraft that leaves the radius. Widen the frame to keep both
  the ring and the aircraft (`DetailMap.region(fitting:padding:minimumSpan:)` already does
  this maths), animated `.smooth(duration: 1.5)`. Snap back when it is unpinned or lost.
- Reframe on radius change, place change, and `mapNorthUp` change.

Motion
- Positions come from the model's 1 Hz dead-reckoning tick, so each glyph hops once a
  second. At a 20 mi radius on a 4K panel that hop is several pixels. Wrap the state that
  drives annotation coordinates in `withAnimation(.linear(duration: 1))`.
- If MapKit on tvOS does not animate `Annotation` coordinate changes (verify on hardware),
  drive the map's own clock instead: `TimelineView(.periodic(from: .now, by: 0.25))` and
  compute `flight.predictedCoordinate(at: timeline.date)` per aircraft. That is independent
  of the model tick and needs no model change.
- Trails and airport pins change only when a feed arrives, not every tick. Key them on
  `model.trailVersion` (new, see §5) so they are not rebuilt every second.
- Reduce Motion: plain hops, no pulse ring, no chrome fades (snap), no reframe animation.

Accessibility
- TV: the map is decorative, like the radar face. `.accessibilityHidden(true)` on the map;
  the hero card and the dock's Aircraft list remain the VoiceOver path, as today.
- iPad: each annotation gets `.accessibilityLabel` "DL570, Delta Air Lines, 3 miles northeast,
  30,000 feet" (`PerimeterLayer.accessibilityText(for:)` is private; lift it to a shared helper if it fits) and the recentre
  button a label.
- Dynamic Type: labels on the map stay fixed like the radar face; the settings rows are
  standard controls and already scale.

---

## 5. Architecture and files

New files (main `WhatTheFlight` target only; they are iOS + tvOS and need no entries in the
widget / Top Shelf / Watch membership-exception lists in `project.pbxproj`).

`UI/TrafficMap.swift` — `#if os(iOS) || os(tvOS)`
```swift
struct TrafficMap: View {
    let observer: CLLocationCoordinate2D
    let radiusMiles: Double
    /// In range, nearest first (`model.contacts`).
    let contacts: [RadarContact]
    /// Just outside, drawn faded (`model.outsideContacts` filtered by the caller).
    var fringe: [RadarContact] = []
    let focusedID: String?
    var isPinned = false
    /// `model.trail(for:)`.
    let trail: (String) -> [RadarModel.TrailPoint]
    /// Bump to rebuild trails and airport pins (`model.trailVersion`).
    let trailVersion: Int
    /// Compass direction for "up"; nil = north up.
    var headingUp: Double? = nil
    var options = Options()
    var onTap: ((String) -> Void)? = nil

    struct Options {
        var scale: CGFloat = 1
        var interactive = false          // iPad: true
        var showsLabels = true
        var showsProjectedPath = true    // focused aircraft only
        var showsFringe = true
        var trailMinutes: Double = 15
        var placeName: String? = nil     // "You · Atlanta"
        var cardInset: CGSize = .zero    // TV: keep the ring clear of the hero card
    }
}
```
Internals: the `Map` builder with ring, trails, projected path, airport pins, observer,
aircraft annotations; framing via `TrafficMapGeometry`; a `MapCameraPosition` `@State`.
`DetailMap` keeps its own body (route mode, origin/destination pins) but moves the shared
pieces (`AirportPin`, observer dot, ring, projected path, `region(fitting:)`) into this file
or into `Core` so both use one copy.

`Core/TrafficMapGeometry.swift` — platform neutral, no SwiftUI/MapKit, so `swift test` covers it
```swift
enum TrafficMapGeometry {
    struct Frame: Equatable { let center: CLLocationCoordinate2D; let latitudeDelta: Double; let longitudeDelta: Double }
    /// A frame around the ring (plus `extra` points), with `padding` as a multiplier.
    static func frame(observer:radiusMiles:extra:padding:) -> Frame
    /// Trail split by age for fading: (points, opacity) oldest first.
    static func segments(_ trail: [RadarModel.TrailPoint], now: Date, bands: [(minutes: Double, opacity: Double)]) -> [(coordinates: [CLLocationCoordinate2D], opacity: Double)]
    /// Origin/destination airports of the given flights that fall inside `bounds`.
    static func relevantAirports(for flights: [Flight], in bounds: GeographicBounds) -> [Airport]
}
```

`UI/TV/TVMapStack.swift` — `#if os(tvOS)`
The TV's map layer: `TrafficMap` (scale 1.7, `headingUp: settings.mapNorthUp ? nil : settings.tvFacingDegrees`,
`cardInset` for the hero card), the hero card, and the ambient-settle state. It is a view
`TVRadarScreen` places in its `ZStack` in place of the radar stack; the status badge, hints,
dock and focus handling stay in `TVRadarScreen` so there is one remote implementation.

Changed files
- `Radar/RadarModel.swift`: add `private(set) var trailVersion = 0`, incremented at the
  end of `updateTrails(with:)`. Nothing else. (Pruning trails to in-range aircraft is a
  separate, optional memory improvement; not needed here.)
- `Data/AirportCatalog.swift`: add `static func airports(in bounds: GeographicBounds) -> [Airport]`
  using the same bounding-box test `nearest(to:withinMiles:)` already does.
- `Services/RadarSettings.swift`: the three settings (§2) and `enum TVView: String, CaseIterable { case radar, map }`.
- `UI/TV/TVRadarScreen.swift`: `DockItem.map`; `if settings.mapView && settings.tvView == .map { TVMapStack(...) } else { radar stack }`
  with `.transition(.opacity)`; `onChange(of: settings.mapView)` clamps `tvView`; input
  events feed the ambient-settle timer.
- `UI/TV/TVSettingsView.swift`: the two rows in the Display pane.
- `UI/TV/TVComponents.swift`: `RemoteHints` if it lists dock items.
- `UI/RadarRootView.swift`: iPad pane. Read `@Environment(\.horizontalSizeClass)` and the
  interface orientation; when `.regular`, landscape, `.pad` and `settings.mapView`, wrap
  `RadarScreen` in `HStack(spacing: 0) { RadarScreen(...).frame(width: side); TrafficMap(...) }`
  where `side` is the screen height. Otherwise the body is unchanged.
- `UI/RadarSettingsSheet.swift`: the two rows, iPad only.
- `UI/FlightDetailSheet.swift`: `DetailMap` uses the shared pieces; its public interface and
  both modes stay as they are. Check tvOS still builds (`TVFlightScreens.swift:78`).
- `CLAUDE.md`: a line in the "Apple TV (radar v2)" section (dock gains Map; `wtf.mapView`,
  `wtf.tvView`, `wtf.mapNorthUp`; `TVMapStack`, `TrafficMap`) and one under iOS for the iPad pane.

---

## 6. Build order

Do these in order; each step leaves the app shippable.

1. **Settings.** Add the three settings and the Display rows on TV and iPad. With nothing
   else built, toggling them must change nothing visible except the rows themselves.
2. **Geometry + tests.** `Core/TrafficMapGeometry.swift` and
   `WhatTheFlightTests/Radar/TrafficMapGeometryTests.swift`. Run `cd WhatTheFlight && swift test`.
3. **TrafficMap.** Build it against `DemoTrafficFeed` traffic in a preview, then move the
   shared pieces out of `DetailMap` and confirm the detail sheet is pixel-identical on iPhone
   and TV (`-wtf.debugSheet detail` / `-wtf.debugScreen detail`).
4. **TV.** `TVMapStack`, dock item, view switch, ambient settle, awake notice.
5. **iPad pane.** Including the recentre button and tap-to-focus.
6. **Polish.** Hop animation (or the 4 Hz fallback), pulse ring, Reduce Motion, VoiceOver
   labels on iPad, screenshot args.

Acceptance (all must hold)
- `-wtf.mapView NO`: no Map dock item, no iPad pane, no Map rows beyond the switch itself,
  TV always radar.
- Switching Map view off while the TV shows the map returns to the radar at once.
- `-wtf.tvView map` launches straight into the map; the choice survives relaunch.
- ◀ ▶ click ⏯ ▼ MENU behave identically on the map and the radar; the dock opens and
  closes the same way; focus never lands on the map.
- 30 s idle fades badge and hints; any press restores them.
- Focused aircraft: signal colour, pulse ring, projected path; pin it, let it leave the
  radius, and the frame widens then snaps back on unpin.
- Trails fade by age and update on feed arrival, not every tick (watch `trailVersion`).
- Only airports that are an origin/destination of a drawn flight get a pin.
- iPad landscape regular width: radar left, map right, tap on a glyph focuses it, recentre
  works; rotate to portrait and the pane is gone.
- iPhone: no visible change anywhere.
- Reduce Motion on: no pulse, no fades, no animated reframe.
- `swift test` passes; `xcodebuild` succeeds for the iOS and tvOS schemes.

---

## 7. Verify on hardware before polishing

- **Frame rate on an Apple TV 4K** with 30+ annotations and polylines updating every second
  (`-wtf.demoTraffic YES` gives 11; set `-wtf.radius 60` over a hub for a real load). Profile
  in Instruments if the map stutters; the 4 Hz `TimelineView` path is the alternative.
- **Whether `Annotation` coordinates animate** inside `withAnimation` on tvOS. If not, use
  the `TimelineView` path and drop the `withAnimation`.
- **Whether `.standard(emphasis: .muted)` compiles and looks right on tvOS** next to the
  paper aesthetic. The tinted-overlay fallback is in §3.
- **Rotated map legibility.** With facing-up the map labels rotate too. If it reads badly at
  common facings, make north-up the default and keep facing-up as the option.

---

## 8. Out of scope, noted for later

- Trail length as a setting (5 / 15 / 30 min). Currently the model constant.
- Pruning `RadarModel.trails` to in-range aircraft (memory at large radii).
- A Mac window via "Designed for iPad"; this spec makes it worthwhile but does not do it.
- A `-wtf.debugScreen map` for the iPhone; the iPhone has no map screen.
