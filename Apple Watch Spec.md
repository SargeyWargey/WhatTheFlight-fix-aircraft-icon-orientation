# WhatTheFlight for Apple Watch — Spec

Status: **Implemented (v1), awaiting on-device testing** · October 2026 · Branch `ios-overhaul`

> **Decisions from review (Oct 20, 2026)**
> - The Digital Crown steps through aircraft on the radar (no crown paging; the Nearby list and settings are toolbar buttons).
> - The Watch keeps its own, tighter radius: **10 mi** by default (roughly what you can see), not synced with the iPhone.
> - **No logbook on the Watch** for now: §5.8, §6.3 and the logbook page are out of scope.
> - Point & Find ships in v1 and gets tested live on the Watch (raw readout on screen, "Flip pointing" setting as the escape hatch).
> - Photos load over Wi-Fi or through the iPhone; over the Watch's own cellular only with "Photos on cellular" on (off by default).
> - Watch → iPhone relay (§7.2 phase 2) and badge celebrations are not built.
> - Point & Find, after the first live test: direction and height are shown and felt separately — a compass strip plus an elevation gauge on screen; clicks while you swing round, "up"/"down" taps for the height, a firm tap when you're on it.
> - Three modes: **Radar**; **Identify** (radar's hand button: point at a plane you can see within 15 mi and the Watch names it — tick, then a firm tap after a half-second hold inside a 10° cone, details on screen, optional spoken call-out; while you swing round, the aircraft nearest your arm on the compass shows its height on the gauge ahead of time; helicopters count down to 1° above the horizon, aeroplanes 3°); **Find** (from a flight's details or an alert: guided to that aircraft). Identify and Find always use the arm-out layout, which auto-rotates like a phone so the text reads from where you stand whatever the wrist, crown side or hand pose (palm-down: top toward the hand; thumb-up: upright along the arm), with a "Turn screen around" setting as a fallback.
> - Two aim styles, chosen in Settings → Identify & Find → Aim with: **Point** (arm out, finger at the plane) and **Aim** (hold the Watch as if reading it and aim its top edge — turn your body, tilt your wrist — so the screen faces you and stays bright). A red arrow on the aiming edge (top for Aim, finger side for Point) shows which style is on.

## 1. The idea

You hear a jet, glance at your wrist, and it already tells you what the plane is, where it is and when it passes closest. No phone needed.

The iPhone app is the full radar. The Apple TV is the radar across the room. The Watch is the **radar you have on you when you're outside looking up**. It should:

- answer "what's that plane?" within about two seconds of raising your wrist,
- tap your wrist when something is about to pass overhead,
- help you find the plane in the sky by pointing your arm at it,
- keep counting sightings for the logbook while you're out.

The Watch app runs on its own (Wi-Fi, cellular or through the iPhone), uses the Watch's own GPS, and reuses the radar core already shared by iOS and tvOS.

### Goals

1. **Wrist Radar**: the iPhone radar's layout (nearest aircraft in the centre, other aircraft on the screen edge at their compass bearing), redrawn for a 40–49 mm screen.
2. **Glanceable everywhere**: complications, Smart Stack widgets, the iPhone's Sky Watch Live Activity, and rich notifications.
3. **Point & Find**: raise your arm toward the sky and haptics guide you to the aircraft.
4. **One logbook**: sightings logged on the Watch merge into the iPhone logbook, and badges unlock on either device.
5. **Works standalone**: needs no iPhone app open and no phone in reach on cellular Watches; needs the iPhone app installed once, for setup and sync.

### Non-goals (v1)

- Sky View with a camera (the Watch has none). Point & Find replaces it.
- Watch-only background monitoring (see §7.3; watchOS doesn't allow it for this kind of app).
- Controlling the Apple TV from the Watch. `TVLink` uses MultipeerConnectivity, which watchOS doesn't have.
- Full place search. The Watch watches from where it is, or from the spot the iPhone set.
- macOS / visionOS changes.

---

## 2. Platform & targets

| | |
|---|---|
| Minimum OS | **watchOS 11** (pairs with the iPhone app's iOS 18.5 minimum). Use `#available(watchOS 26, *)` for Liquid Glass, like `glassSurface` does on iOS. |
| App type | Single-target watchOS app (no separate WatchKit extension), `WKRunsIndependentlyOfCompanionApp = YES`, companion `SargeyWargey.WhatTheFlight`. |
| Bundle IDs | `SargeyWargey.WhatTheFlight.watchkitapp`, widgets `SargeyWargey.WhatTheFlight.watchkitapp.Widgets` |
| App Group | `group.SargeyWargey.WhatTheFlight` (same ID; on the Watch it's shared between the Watch app and its widget extension only, not with the phone) |
| Screens | Design at 46 mm (208×248 pt), verify at 40 mm (162×197 pt) and 49 mm Ultra (205×251 pt). |
| Compass | Series 5+, SE and Ultra. Older Watches show the radar north-up. |

### New targets

1. **WhatTheFlight Watch App** (watchOS)
2. **WhatTheFlight Watch Widgets** (watchOS WidgetKit extension): complications and Smart Stack.

Both reuse app files through `PBXFileSystemSynchronizedBuildFileExceptionSet` membership lists, as the iOS widgets and Top Shelf targets already do. Both are embedded into the iOS app with a `watchos` platform filter.

> **Later option (not v1):** turn the existing `Package.swift` core (`Core/`, `Data/`, `Radar/`, feed, settings, shared store) into a local library linked by every target. That would end the membership-list upkeep, but every shared type would need `public`, so it's a separate refactor.

---

## 3. What's reused vs. new

### Reused as-is (add to the Watch targets' membership lists)

| File / type | Use on Watch |
|---|---|
| `Core/*`: `GeoMath`, `Flight`/`RadarContact`, `FlightFeedParser`, `PerimeterTrack`, `FocusPolicy`, `OperatorInfo`, `NotableTraffic`, `RouteProgress`, `SkyProjector` | All radar maths. `SkyProjector`/`GeoMath.elevationDegrees` drive Point & Find. |
| `Data/*` catalogs | Airline, type, airport and registration lookups. Measure launch time and memory (§10). |
| `Radar/RadarModel` | Same state machine: polling with backoff, 1 Hz dead reckoning, focus, notices, alert engine. |
| `Radar/Logbook`, `LogbookStats`, `Achievement` | Watch-local logbook and badges. |
| `Radar/TrafficAlerts` (`TrafficAlertEngine`, `SpokenTraffic`) | In-app wrist alerts. |
| `Services/FlightFeed` (`FlightRadarFeed`, `DemoTrafficFeed`) | Watch fetches directly; demo mode works unchanged. |
| `Services/RadarSettings` | Same keys (`wtf.*`), Watch-local `UserDefaults`, plus a few Watch-only keys (§8). |
| `Services/SharedRadarStore`, `RadarSnapshot`, `NearbyTraffic` | Watch app ↔ Watch complications. |
| `Services/AircraftPhotoProvider` | Small photo on the detail screen, with the photographer credit Planespotters requires. |
| `Models/GeographicBounds` | Feed query box. |

### Small changes to shared code

| Change | Why |
|---|---|
| `UI/Theme.swift`: add an `#if os(watchOS)` branch with the **dark** palette values as plain `Color`s, plus `Font.mono`. | Theme is iOS/tvOS-only today and uses `UIColor` trait providers. The Watch is always dark. |
| `Logbook`: add `merge(_ incoming: [Sighting])` and `Sighting.merged(with:)` | Watch → iPhone logbook sync (§6.3). Pure logic, unit-tested. |
| `AlertNotifier.deliver`: set `categoryIdentifier = "wtf.traffic"` and add bearing, miles, altitude, identifier and route to `userInfo` | Lets the Watch draw a custom notification (§5.6). |
| `SkyWatchLiveActivity`: add `.supplementalActivityFamilies([.small])` and a compact layout | The Sky Watch Live Activity already appears in the Watch Smart Stack; this gives it a layout designed for the Watch. |
| `RadarIntents`: move `WhatsOverheadIntent.sentence(for:)` into a platform-neutral helper | So the Watch's Siri intent says the same sentence. |
| `PerimeterPlanner.plan`: add a `maxIcons` parameter (default 32) | The Watch caps icons at 8; today the cap is a fixed constant. |
| `Flight.predictedCoordinate(maxExtrapolation:)` | Already a parameter. Complication timelines pass a longer cap (§5.5); no code change. |

### New code (Watch only, under `WhatTheFlight/Watch/`)

| File | Role |
|---|---|
| `WatchApp.swift` | `@main`, scene phase handling, owns `RadarModel`, `Logbook`, `WatchLocationService`, `WatchSync`. |
| `WatchLocationService.swift` | GPS + heading for watchOS (the iOS `RadarLocationService` imports UIKit and handles orientation). |
| `WatchRadarView.swift` | Wrist Radar: hero + perimeter on the Watch's rounded rectangle. |
| `WatchFlightDetail.swift` | Scrolling detail page. |
| `WatchNearbyList.swift` | List of everything in range. |
| `WatchLogbookView.swift` | Stats, recent sightings, badges. |
| `WatchSettingsView.swift` | Watch settings. |
| `PointAndFind.swift` + `Core/WristPointing.swift` | Arm-pointing guidance (wrist-axis maths in `Core/`, so it's unit-tested). |
| `WatchHaptics.swift` | One place for the haptic vocabulary (§5.7). |
| `WatchSync.swift` (shared: iOS + watchOS) | WatchConnectivity: settings, observer, logbook. |
| `WatchNotificationView.swift` | Long-look notification UI for `wtf.traffic`. |
| `WhatTheFlightWatchWidgets/` | Complications and Smart Stack widget. |

---

## 4. Navigation

The watchOS 10+ pattern: a **vertical page stack** turned with the Digital Crown, with toolbar buttons in the corners.

```
┌──────────────┐
│  Wrist Radar │  ← page 1 (launch screen)
├──────────────┤
│  Nearby list │  ← page 2
├──────────────┤
│  Logbook     │  ← page 3
└──────────────┘
   Settings: gear button, top-left of the radar
   Details:  tap the hero or a list row (pushes onto a NavigationStack)
```

**Conflict to resolve:** on the radar page the crown is also the obvious way to step between aircraft (like ◀/▶ on the TV). Proposal: the radar page **captures the crown** for aircraft stepping (`digitalCrownRotation` with detents); scrolling past the last aircraft moves to the next page. If that feels wrong on device, fall back to **swipe to page, crown to step** and move the list to a toolbar button. (Open question Q1.)

---

## 5. Features

### 5.1 Wrist Radar (main screen)

```
        ╭───────── N ─────────╮
     ✈ 9│                      │
        │      DELTA           │✈ 16
        │      DL570           │
        │    SFO → ATL         │
        │  30,000 ft · 1 mi    │
      ⟳ │   ◉ 0:48 closest     │
      4 │                      │ ✈ 12
        ╰──────────────────────╯
```

**Centre (hero), top to bottom:**
1. Notable badge, when there is one (`NotableBadge` colours, condensed: "EMERGENCY 7700", "RARE · A380").
2. Operator, compact (`OperatorInfo.compact`): "DELTA", "Private aircraft 🇺🇸".
3. **Identifier**: `Font.mono(30, .heavy)`, scaling down to 0.5.
4. Route `SFO → ATL` (omitted when unknown).
5. One stat line: altitude · whole-mile distance. On 45 mm and larger, add speed on a second line.
6. Approach chip, same three states as the iPhone `ApproachChip`: **OVERHEAD** pulsing in signal red, **"0:48 closest"** countdown, or **"Moving away"**.

**Perimeter:**
- Icons ride a `PerimeterTrack` built from the Watch screen's rounded rectangle (inset ~6 pt, corner radius taken from the display), placed by `PerimeterPlanner.plan(...)` at their compass bearing, rotated to their real track. Plane vs. helicopter glyph, same as iOS.
- The Watch has room for less: **at most 8 icons** (nearest first) and **mile labels on the nearest 4 only** (all 8 at 45 mm+). `iconSpacing`/`labelOffset` go through the existing `scale` parameter (≈0.55).
- The top-left gear and the clock in the top-right count as `obstacles`, so icons avoid them, as they avoid the Dynamic Island on iPhone.
- A small **N** marker on the edge shows north.

**Rotation:**
- With a compass and wrist **heading** available, the whole perimeter rotates so "up" is where the top of the Watch faces (smoothed with `continuousRotation`, same as iOS).
- Without a compass, or with the **North up** setting on, the radar stays north-up.
- Accuracy dot: when heading accuracy is worse than 30°, show a faint "±" under the N marker and suggest the figure-8 calibration once.

**Focus rules (same as the Working Spec):** the nearest aircraft owns the centre until it leaves the radius or you send focus back to nearest. All of it is `FocusPolicy`, nothing new:
- **Crown** steps to the next-farther / next-nearer aircraft (`focusNext` / `focusPrevious`), one crown detent click per step.
- **Double tap** (`handGestureShortcut(.primaryAction)`, Series 9+/Ultra 2) and the **Nearest** toolbar button: back to the nearest aircraft (`focusNearest`).
- **Long press on the hero** pins the aircraft (`togglePin`), shown by a pin glyph by the identifier.
- **Tap the hero** opens details.
- **Tap a perimeter icon** focuses it, as on iPhone.

**Empty / error states:** "Clear skies within 10 mi" with the radar sweep; "Waiting for GPS…"; feed errors reuse `FeedError` copy plus a Retry button. Status is a small coloured dot (live / loading / error) in the corner.

**Always-On (wrist down):** when `isLuminanceReduced` is true, stop polling and the sweep. Redraw once a minute (`TimelineView(.everyMinute)`) with dead-reckoned positions, at reduced brightness: identifier, distance and icons only. Polling resumes on wrist raise.

### 5.2 Flight details

A vertical scroll page, pushed from the hero, a list row, a notification or a complication.

1. Header: notable badge, operator `headline`, identifier, route with city names (`AirportCatalog`).
2. **Route progress bar** (`RouteProgress`): flown / to go in miles, plus "1h 05m to go" when it's meaningful.
3. Live block (updates every second): distance and cardinal direction, altitude with ▲/▼ trend, ground speed, closest pass (miles + countdown).
4. Aircraft: type name, registration with country flag, photo thumbnail with the photographer credit (hidden when `showPhotos` is off).
5. "Seen 3 times before · first Oct 2" (`Logbook.seenBeforeSummary`).
6. Actions:
   - **Find in the Sky**: opens Point & Find (§5.3) for this aircraft.
   - **Open on iPhone**: Handoff `NSUserActivity` that opens `whattheflight://flight/<id>` (`AppRouter` already handles it).
   - **Pin / Unpin**.

### 5.3 Point & Find (the signature feature)

The Watch's take on Sky View: raise your arm, point your hand at the sky, and the Watch guides you to the aircraft by feel.

**How it works**
- Core Motion `deviceMotion` gives the Watch's attitude. The **forearm axis** (the screen axis that runs toward your fingers) is the pointing direction. Which device axis that is, and its sign, comes from `WKInterfaceDevice.wristLocation` and `crownOrientation`.
- The pointing azimuth and elevation are compared with the target's azimuth (`RadarContact.bearing`) and elevation (`GeoMath.elevationDegrees`).
- The screen shows a large arrow toward the target (left/right/up/down), the angle off, and the aircraft's identifier.
- **Haptic guidance**: clicks that speed up as you get closer ("warmer"), and a distinct `.success` when you're within ~8°. The screen then shows "That's it — DL570, 30,000 ft". It works without looking at the Watch, because your eyes are on the sky.
- The target is the focused aircraft, or the one picked from details. Turning the crown switches to the next-nearest aircraft.

**Fallback:** if the true-north attitude reference frame isn't available (see Risk R1), take azimuth from `CLHeading` and elevation from the gravity vector alone. That's less precise, but enough for "warmer/colder".

**Core logic** goes in `Core/WristPointing.swift`: attitude matrix + wrist config → (azimuth, elevation), plus an angular-error helper. Unit tests cover all four wrist/crown combinations.

### 5.4 Nearby list

All in-range aircraft, nearest first. Each row: plane/heli glyph with a bearing arrow, identifier, miles, altitude, and a notable dot. Rows are coloured with `Palette.color(for:)`. Tap opens details. The footer shows "+N outside radius" when the feed returned more. This is also the accessible fallback when the radar is too dense to read (§9).

### 5.5 Complications & Smart Stack (Watch widget extension)

All families fetch with `NearbyTraffic.latestSnapshot`, around the observer the Watch app last wrote to its own `SharedRadarStore`, and fall back to the stored snapshot.

| Family | Content |
|---|---|
| `accessoryCircular` | Bearing arrow around a ring + whole miles of the nearest aircraft ("2"), with a plane/heli glyph. |
| `accessoryCorner` | Plane glyph, curved label "DL570 · 2 mi NE". |
| `accessoryRectangular` | Identifier + route, "2 mi NE · 30,000 ft", and **"Closest in 0:48"** as a live `Text(date, style: .timer)`. |
| `accessoryInline` | "✈ DL570 2 mi NE". |
| Smart Stack (`.accessoryRectangular` in the stack) | Same as rectangular, plus "+5 more in range". |

**Keeping complications current despite refresh limits:** a Watch complication may only reload a few times an hour. Each timeline therefore carries **one entry per minute for the next 5 minutes**, built by dead reckoning the fetched contacts forward (`RadarContact(flight:observer:at:)` with a 5-minute extrapolation cap). The closest-pass countdown uses the timer text style, so it ticks without new entries. Entries after 5 minutes switch to "Open to refresh" rather than showing made-up positions.

**Relevance:** `TimelineEntryRelevance` scores high when an aircraft's closest pass is under 3 minutes away or something notable is in range, so the Smart Stack pushes the widget up. If the watchOS 26 Smart Stack relevance APIs suit this, use them too (verify).

Tapping a complication opens the app on that flight (`whattheflight://flight/<id>`).

### 5.6 Notifications & Live Activity (driven by the iPhone)

The phone's **Sky Watch** already runs alerts in the background for up to two hours. On the Watch:

- **Overhead / notable notifications** are mirrored to the Watch whenever the phone is locked; time-sensitive overhead alerts tap the wrist. New: a **custom long-look** for category `wtf.traffic`. It shows a mini radar dial with the aircraft's bearing arrow, the identifier, the route, altitude, and "Closest in 0:48". Actions: **Find in the Sky** (opens Point & Find on the Watch) and **Open on iPhone**.
- **Sky Watch Live Activity** shows in the Watch Smart Stack (watchOS 11 does this for iPhone Live Activities). New: a `.small` supplemental layout: identifier, bearing arrow, miles, pass countdown and in-range count.
- A "Start Sky Watch on iPhone" button in Watch settings sends a WatchConnectivity message. The phone starts Sky Watch if its app can do so in the background; otherwise the Watch shows "Open WhatTheFlight on your iPhone to start". (Starting a Live Activity from the background has limits; Risk R4.)

### 5.7 Wrist alerts while the app is open

While the app is in the foreground, `RadarModel.onAlert` turns `TrafficAlertEngine` alerts into a haptic plus a banner over the radar:

| Event | Haptic | Visual |
|---|---|---|
| Overhead soon | `.directionUp` | Banner "DL570 overhead in 0:48 — look NE" |
| Overhead now | `.notification` | Hero chip pulses OVERHEAD |
| Notable in range | `.notification` | Banner with the tag colour |
| Badge unlocked | `.success` | Full-screen badge card (`Achievement.symbol`, title) |
| Crown step | detent click | — |
| Point & Find | `.click` cadence → `.success` | Arrow / "That's it" |

All haptics are gated by the existing `hapticsEnabled` setting.

### 5.8 Logbook on the Watch

- Recording: `RadarModel.logbook` is set on the Watch, live traffic only (never demo), and respects `keepLogbook`, exactly as on iPhone.
- Page 3 shows **Today / Total / Closest** stat tiles (`LogbookStats`), the 20 most recent sightings, and badges as a grid of progress rings (`Achievement.fraction`). Tapping a badge shows its `about` text and the sighting that unlocked it.
- Merging with the iPhone: §6.3.

### 5.9 Siri & Shortcuts

- A watchOS version of **"What's That Plane?"** answers using the Watch's current location (or the iPhone's spot, depending on the location setting). It uses the shared sentence helper and a compact snippet. Raise to Speak: "What's that plane?" gets a spoken answer with no app launch.
- **"Find that plane"** opens Point & Find on the nearest aircraft.
- Both are listed as App Shortcuts, so they can appear in the Smart Stack and on the Action button (Ultra).

---

## 6. Data & sync

### 6.1 Where the Watch watches from

`wtf.watch.locationSource`:
- **Here** (default): Watch GPS via `WatchLocationService`, `kCLAccuracyNearestTenMeters`, distance filter 40 m, started only while the app is in the foreground.
- **iPhone's spot**: the observer the iPhone last sent (custom place or the iPhone's GPS), with its place name shown under the radar. Handy for "what's over my house?" from work.

The Watch app writes whichever observer it uses into its own `SharedRadarStore`, so the complications follow.

### 6.2 WatchConnectivity (`WatchSync`, compiled for iOS + watchOS)

| Direction | Transport | Payload |
|---|---|---|
| iPhone → Watch | `updateApplicationContext` (latest wins) | `observer` lat/lon + place name, `radiusMiles`, `showHelicopters`, alert rules (`overheadAlerts`, `overheadAlertMiles`, `notableAlerts`), `keepLogbook`, `demoTraffic`, `sentAt` |
| Watch → iPhone | `transferUserInfo` (queued, guaranteed) | New/updated `Sighting`s since the last ack, in batches of ≤200 |
| iPhone → Watch | `transferUserInfo` | Sightings logged on the phone (opt-in, see Q3) |
| Watch → iPhone | `sendMessage` (reachable only) | `startSkyWatch` request |

Payloads are `Codable` structs in `WatchSync.Payload`, encoded with JSON, versioned with `v: 1`, and round-trip tested in `Package.swift`, like `TVLink.Payload`.

**Settings ownership:** the iPhone owns the shared preferences; the Watch applies what arrives. Watch-only settings (§8) never sync. If the Watch user changes the radius, it's stored as `wtf.watch.radius` and overrides the phone's value on the Watch only (Q2).

### 6.3 Logbook merge

- A sighting's `id` is the feed's flight-leg ID, the same on both devices, so a flight seen on both merges into one row.
- `Sighting.merged(with:)`: earliest `firstSeen`, latest `lastSeen`; smallest `closestMiles`, and that side's altitude and speed at closest; union of `tags`; keep the first non-nil `placeName`.
- `Logbook.merge(_:)` applies the incoming batch, rebuilds the index, marks the logbook dirty and saves. Achievements then recompute from the merged sightings on their own.
- Badge unlocks caused by merged sightings post a quiet notice ("Unlocked on Apple Watch: Rotorhead") instead of a full celebration.

---

## 7. Lifecycle, battery, network

### 7.1 Foreground

- `scenePhase == .active`: `RadarModel.start()`, GPS + heading on, polling every `refreshSeconds` (default 10 s; the Watch clamps it to a minimum of 10 s).
- `.inactive` (wrist down, Always-On): `RadarModel.stop()`; the Always-On view keeps dead-reckoning from the last fetch.
- `.background`: everything stopped, `logbook.flush()`, snapshot written to `SharedRadarStore`, `WidgetCenter.shared.reloadAllTimelines()` (rate-limited to once per 5 min).

### 7.2 Network

- The Watch calls Flightradar24 itself through `FlightRadarFeed`; the query box is small, so the response stays small.
- With iPhone and Watch both open, FR24 sees twice the requests. **Phase 2 optimisation:** when `WCSession.isReachable` and the phone's radar is live, the phone relays its contacts with `sendMessage`, and the Watch skips its own polling.
- Backoff and rate-limit handling come from `RadarModel.pollOnce` unchanged.

### 7.3 Background (what the Watch cannot do)

watchOS gives an app like this no continuous background runtime: the extended-runtime session types are for workouts, mindfulness, physical therapy and alarms, and borrowing one for plane spotting risks App Review rejection. So:
- Background **alerts** come from the iPhone's Sky Watch (§5.6).
- Background **freshness** comes from complication timelines (§5.5) and `WKApplicationRefreshBackgroundTask` (about 4 an hour, best effort), which refreshes the snapshot.
- Background **logging** on the Watch happens only while the app is open. That's fine, because the phone logs during Sky Watch and the logbooks merge.

---

## 8. Settings (Watch)

Kept short, as a list with crown-adjustable pickers:

| Setting | Key | Default | Notes |
|---|---|---|---|
| Location | `wtf.watch.locationSource` | Here | Here / iPhone's spot |
| Radius | `wtf.watch.radius` | follows iPhone (fallback 10 mi) | Picker: 2, 5, 10, 15, 20, 30, 50 mi |
| North up | `wtf.watch.northUp` | off | Forced on when there's no compass |
| Helicopters | `wtf.showHelicopters` | synced | |
| Overhead haptics | `wtf.overheadAlerts` | synced | |
| Notable haptics | `wtf.notableAlerts` | synced | |
| Haptics | `wtf.haptics` | on | |
| Aircraft photos | `wtf.showPhotos` | on | Saves data on cellular when off |
| Keep logbook | `wtf.keepLogbook` | synced | |
| Start Sky Watch on iPhone | — | — | Action button (§5.6) |
| Demo traffic | `wtf.demoTraffic` | off | |
| About | — | — | FR24 disclaimer, OpenFlights / OurAirports / Planespotters credits |

On the iPhone, **Settings → Apple Watch** (new, shown only when a Watch is paired) gets two items: "Send my spot to Apple Watch" and "Sync logbook from Watch".

---

## 9. Design & accessibility

- **Look:** the dark "night radar" palette from `Theme.swift` (paper `#0A0E14`, ink `#A8A4FF`, signal `#FF6B5E`, blips `#72AAFF`), SF Mono throughout, faint range rings, and the radar sweep (off under Reduce Motion and in Always-On). Topographic background off by default on the Watch; it costs legibility at this size.
- **VoiceOver:** the hero reads "Delta DL570, San Francisco to Atlanta, 1 mile north-east, 30,000 feet, closest pass in 48 seconds". Perimeter icons are grouped into one element, "8 more aircraft, swipe for the list", which jumps to the Nearby list.
- **Dynamic Type:** the hero scales. At accessibility sizes the perimeter hides and the radar page becomes hero + "N more nearby".
- **Reduce Motion:** no sweep, no pulse, no rotation animation (snap instead).

---

## 10. Testing & debug

**Unit tests (added to `swift test` via `Package.swift`):**
- `WristPointingTests`: azimuth/elevation from known attitudes for left/right wrist × crown left/right; angular error wraps across 0/360.
- `SightingMergeTests`: closest wins, tags union, first/last seen, idempotent re-merge.
- `WatchSyncPayloadTests`: encode/decode round trip; an unknown `v` is ignored.
- `ComplicationTimelineTests`: the 5-entry projection moves aircraft along their track; a contact that leaves the radius drops out.
- `PerimeterPlannerTests`: an 8-icon cap and no overlaps on a 162×197 rect with corner obstacles.

**Manual / device:**
- Simulator: `-wtf.demoTraffic YES -wtf.hasSeenWelcome YES`, plus Watch debug launch args mirroring iOS: `-wtf.debugScreen detail|list|logbook|settings|find`, `-wtf.debugFocus <flight>`.
- On a real Watch: compass rotation, Point & Find accuracy outdoors against a known flight, battery over a 30-minute session (target ≤ 10%), launch time with the catalogs (target ≤ 1.5 s to first frame).

---

## 11. Phases

| Phase | Scope | Exit criteria |
|---|---|---|
| **1 · Wrist Radar** | Watch target, Theme branch, `WatchLocationService`, radar, details, Nearby list, settings, demo mode, Always-On | Standalone on a cellular Watch; demo and live traffic look right at 40 and 46 mm |
| **2 · Glance** | Widget extension + complications with projected timelines, `WatchSync` (settings + observer), Watch logbook + merge, background refresh | Complication countdown correct for 5 min; a sighting logged on the Watch appears on the iPhone |
| **3 · Alerts** | `wtf.traffic` category + long-look, Live Activity `.small` layout, in-app wrist alerts, Siri intent, Handoff | Phone-locked Sky Watch alert shows the custom long-look; "What's that plane?" answers on the Watch |
| **4 · Point & Find** | `WristPointing`, guidance UI and haptics, crown target switching | Finds a real overhead flight within ~10° on Series 5+ hardware |
| **5 · Polish** | Phone→Watch relay to halve FR24 calls, badge-unlock celebrations, Ultra Action button | — |

---

## 12. Risks & things to verify

| # | Risk | Mitigation |
|---|---|---|
| R1 | The true-north attitude frame may not exist on the Watch, or may be noisy | Spike first in Phase 4 (`CMMotionManager.availableAttitudeReferenceFrames()` on Series 5+ hardware). Fallback: `CLHeading` + gravity. |
| R2 | Which way "heading" points on a Watch, and how it depends on wrist/crown setup | Verify on device in Phase 1; the North-up setting is always available. |
| R3 | Catalog static data (~14.6k rows) slows launch or uses too much memory | Measure in Phase 1. If slow, lazy-load from a bundled JSON/plist on first lookup. |
| R4 | The phone can't start a Live Activity when the Watch asks while the app is in the background | Use the "open the iPhone app" fallback message; investigate push-to-start later. |
| R5 | Unofficial FR24 endpoint; the Watch doubles request volume | Same backoff and rate-limit handling; Phase 5 relay. |
| R6 | Too many icons for the small screen | Hard cap of 8, labels on the nearest 4, and the Nearby list as the overflow. |
| R7 | The Watch may move the crown/double-tap rules on watchOS updates | Keep the Nearest toolbar button as the always-available path. |

---

## 13. Open questions for review

1. **Crown on the radar page**: step through aircraft (proposed) or scroll pages?
2. **Radius**: should the Watch follow the iPhone's radius, or keep its own default (a tighter 10 mi suits a small screen and standing outside)?
3. **Logbook direction**: Watch → iPhone only (proposed for v1), or full two-way so the Watch shows your whole history and badges?
4. **Point & Find in v1?** It's the most distinctive feature but has the most hardware risk. Ship it last (proposed), or spike it first to decide whether it leads the release?
5. **Photos on cellular**: show them by default, or only on Wi-Fi?
