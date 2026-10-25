# Apple Watch enhancements — spec

Everything left from the October 25, 2026 review of the Watch app
(`WhatTheFlightWatch/`, `WhatTheFlightWatchWidgets/`) after the battery pass that day
(listed at the end). Read `CLAUDE.md` and `Apple Watch Spec.md` first. Items that belong to
the cross-platform `Enhancements Spec.md` (metric units, watchlist, the iPhone half of
Smart Stack) stay there and are only cross-referenced here.

How to use this: every item stands alone and says where it lives, what is wrong or
missing, the change, and how to know it is done. Line numbers were correct when this was
written; search by symbol if one has drifted. Run `cd WhatTheFlight && swift test` after
anything that touches `Core/`, `Radar/` or `Services/WatchSync.swift`, and build the Watch:
`xcodebuild -project WhatTheFlight.xcodeproj -scheme WhatTheFlightWatch -destination 'generic/platform=watchOS Simulator' build`.
Mark finished items with the same green marker as `Enhancements Spec.md`.

Priority tags: **P1** fix before the next release · **P2** next · **P3** when convenient.

Suggested order: A1 → A2 → A3 (an afternoon, no visible change), then B3 → B2 → B1 (what
you touch and see), A4 (measure first), C2 → C3 → C1 (settings), B4 → B6 when convenient.
C5 is its own project and waits for `LogbookSync` to be steady on iPhone and TV. C6 and C7
can go any time. A6 last: it needs both apps open and a proxy to prove it.

---

## Part A — Performance and battery

### A1 · P2 · Watch views read `Flight` computed properties every tick
- Where: `WhatTheFlightWatch/WatchNearbyList.swift` `row(_:)` (~56–97: `f.notable` ~58,
  `f.kind` ~60 and ~63, `f.typeName` / `f.operatorInfo` ~97);
  `WatchFlightDetail.swift` `header` (~76–95: `f.notable`, `f.operatorInfo.headline`,
  `f.origin?.city`, `f.destination?.city`) and `aircraft` (~174 `f.typeName`);
  `IdentifyView.swift` `card` (~158–161) and `subtitle` (~199–200);
  `PointAndFindView.swift` (~70 `target?.flight.silhouette`).
- What happens: `CLAUDE.md`'s rule is that per-tick code and views read
  `RadarContact.profile` (operator, notable tags, type, silhouette, built once per flight
  per feed by `RadarModel`); Enhancements Spec B1 did that for the iPhone and TV. These
  Watch sites still go through the `Flight` computed properties, each a catalog lookup
  plus string work (`OperatorInfo`, `NotableTraffic.classify`), re-run on every one-second
  tick for every row on screen, on the slowest CPU in the family. `WatchFlightDetail`
  also resolves `model.contact(id:)` three times per tick (~28, ~41, ~43).
- Change: swap each for `contact.profile.notable` / `.operatorInfo` / `.typeName` /
  `.kind` / `.silhouette`. Airports aren't in the profile: look `origin` / `destination`
  up once per detail view (`@State`, keyed by the IATA codes) rather than per tick. In
  `WatchFlightDetail` resolve the contact once at the top of `body` and pass it down.
- Done when: `grep -n "f\.\(notable\|operatorInfo\|typeName\|kind\)\|flight\.silhouette" WhatTheFlightWatch/*.swift`
  finds only the tour, and Time Profiler on the Nearby page with eight contacts shows no
  `AirlineCatalog` or `NotableTraffic` frames on the tick.

### A2 · P2 · Identify recomputes `visible` on every access
- Where: `IdentifyView.swift` ~35, `visible` filters `model.allContacts` through
  `WristPointing.isIdentifiable` (elevation maths per contact). It is read in `body`
  (~84 `visible.isEmpty`, ~140 `marks`) and in the 10 Hz `track()` loop (~219 for the
  candidates, ~222 for the lead), so the same filter runs four or more times a second
  per aircraft in the box.
- Change: compute it once per `track()` pass into a local; store it in `@State` only when
  the set of ids changes, and have `body` read the state. The loop can also wait on the
  pointer instead of sleeping 100 ms blind: with the redraw gate from the battery pass,
  `pointer.pointing` only changes when the arm has moved, so `track()` can skip a pass
  when it hasn't.
- Done when: `visible` is built once per pass and `body` no longer filters contacts;
  `IdentifyTests` still pass.

### A3 · P3 · Coarser compass filter on the radar
- Where: `WatchSensors.swift` ~50, `manager.headingFilter = 2`.
- What happens: every two degrees of wrist movement re-runs `PerimeterPlanner.plan`, the
  `CompassBezel` Canvas (72 ticks and four letters, each a binary search on the track)
  and the springs on every blip and label. Walking, that is a full redraw many times a
  second.
- Change: tie it to `WatchLocationService.precision` (from the battery pass): 4° for
  `.radar` and `.coarse`, since `interactiveSpring` already hides the steps; keep 2° for
  `.pointing`, where the compass-only fallback uses the heading as the azimuth.
- Done when: a one-minute walk logs about half the heading updates it did, and the radar
  still turns smoothly.

### A4 · P2 · The widget extension parses the airport catalog it never uses <span style="color:#FFB300; font-weight:900; font-size:1.2em">◐ PARTLY IMPLEMENTED</span>
- Where: `WhatTheFlightWatchWidgets/WatchComplications.swift` ~56, `Catalogs.warmUp()` in
  `getTimeline`; `Data/AircraftTypeCatalog.swift` ~352–364, `warmUp()` touches
  `AirportCatalog.airport(iata: "ATL")` (~358), which builds the 8,800-row `table` and
  `grid` (`Data/AirportCatalog.swift` ~79–107). Also the timeline policy, ~57: `.atEnd`
  after `steps = 6` minutes.
- What happens: the complication shows IATA codes only (`SnapshotFlight.route`), and
  `FlightProfile` needs airlines, types and registration prefixes but no airports, yet the
  whole airport catalog is parsed inside the widget process, whose memory ceiling is far
  below the app's. Separately, `.atEnd` asks WidgetKit for a reload every seven minutes;
  watchOS allows a few an hour, so on a busy day the timeline runs dry and the face shows
  "Open to refresh" for long stretches.
- Change: `Catalogs.warmUp(airports: Bool = true)`, and the widget passes `false`. Log
  reload budget messages from Console for a day before changing the policy; if they
  show throttling, project ten entries and use `.after(now + 15 min)`, leaning on
  `WatchBackgroundRefresh` and the app's `ComplicationPublisher` for the rest.
- Done when: Allocations on the widget extension shows no `AirportCatalog` tables, and a
  day of wearing rarely shows "Open to refresh".
- *As built:* `Catalogs.warmUp(airports:)`; `SkyProvider` passes `false`, and nothing on the
  complication path looks up an airport, so the table is never built. The three traffic
  complications share one fetch (`ComplicationTraffic`, reused for 45 s), so the reload
  budget pays for one request, not three. The `.atEnd` policy is unchanged: that waits on
  a day of reload-budget logs, as above.

### A5 · P3 · Skip the snapshot write when nothing changed
- Where: `WatchRootView.swift`, `ComplicationPublisher.publish` (~345–360): every poll
  encodes a `RadarSnapshot` to JSON and writes it to the App Group defaults.
- Change: remember what was last written (nearest id, in-range count, the nearest's whole
  miles) and skip when it matches. The `reloadAllTimelines` throttle stays as it is.
- Done when: in an empty sky the App Group plist's modification date stops moving
  between polls.

### A6 · P2 · iPhone → Watch traffic relay
- Where: `Services/WatchSync.swift` (`Context` ~19, `Reply` ~46; the Watch side has no
  `didReceiveMessage`); `WatchRootView` always runs its own polling. Apple Watch Spec §7.2
  phase 2 and §11 phase 5.
- What happens: with both apps open, Flightradar24 sees two pollers for the same box, and
  the Watch's radio (Bluetooth proxy, Wi-Fi or cellular) carries every response.
- Change: when `WCSession.isReachable` and the iPhone's radar is live, the phone sends its
  raw `flights` array after each poll (`sendMessage`, JSON, with the box it queried). On
  the Watch a `RelayFeed: FlightFeed` returns the latest relayed array; `RadarModel` uses
  it while the relayed data is younger than `staleAfter` and the phone's box covers the
  Watch's (radius × 1.5 + 3 or the Identify floor, whichever is larger), and goes back to
  `FlightRadarFeed` otherwise. Keep `PollingPolicy` unchanged; the relay only replaces the
  network call.
- Done when: with both apps open a proxy shows no `feed.js` requests from the Watch and
  its log says "relayed"; closing the iPhone app resumes direct polling within one
  interval.

### A7 · P3 · Unused logbook types ship in the Watch binary
- Where: `WhatTheFlight.xcodeproj/project.pbxproj`, the Watch exception set (~193–197:
  `Radar/LogbookAchievements.swift`, `LogbookDigest.swift`, `LogbookSky.swift`,
  `SpotPhoto.swift`). Nothing in `WhatTheFlightWatch/` creates a `Logbook`.
- Change: decide with C5. If C5 goes ahead they stay and get used; if not, remove them
  (`Logbook.swift` itself stays, `RadarModel.logbook` and `Sighting` need it).
- Done when: either C5 is in, or the Watch binary is smaller and CI's watchOS build is
  still green.

---

## Part B — UI

### B1 · P2 · Heading accuracy hint
- Where: `WatchSensors.swift` ~28 `headingAccuracy` is stored (~109) and never read.
  Apple Watch Spec §5.1, "Accuracy dot".
- What happens: an uncalibrated compass turns the whole radar the wrong way with no sign
  of it. Identify and Find already say "Waiting for the compass" in the compass-only
  fallback; the radar says nothing.
- Change: in `WatchRadarView`, when `headingAccuracy > 30`, draw a faint "±" under the
  bezel's N (`Palette.caption`), and once per launch show a small caption under the hero
  for about six seconds: "Compass needs a figure eight" (`wtf.watch.calibrationHintShown`
  resets each launch). VoiceOver: add "compass uncalibrated" to the hero's label.
- Done when: on a Watch with the compass upset (near a magnet), the ± shows and clears
  after a figure eight; the simulator never shows it.

### B2 · P2 · Always-On minimal layout
- Where: `WatchRadarView.swift`, `WatchFlightHero` (~296) under `isLuminanceReduced`: only
  the Nearest button and the glow are gated; the operator line, route, speed and chip
  still draw. Apple Watch Spec §5.1 Always-On: identifier, distance and icons only.
- Change: pass `isDimmed` to the hero. Dimmed: identifier and the altitude · miles line
  only, no chip, route, operator or speed, text at `Palette.ink.opacity(0.85)`; the
  perimeter stays at 0.6 with its labels. The stale chip never shows there (already so).
- Done when: wrist down shows two lines in the centre and the icons; wrist up restores
  the full hero without a layout jump.

### B3 · P2 · Blip tap targets are too small
- Where: `UI/PerimeterLayer.swift`, `AircraftBlip` ~141–142:
  `.frame(width: 44 * scale, height: 44 * scale).contentShape(Circle())`. The Watch passes
  `blipScale` 0.56 (40–42 mm) or 0.62, so the hit circle is 25–27 pt; `WatchPerimeterLayer`
  (~511–516) attaches the tap to it.
- Change: give `AircraftBlip` a `hitSize: CGFloat?` that overrides the frame used for the
  content shape (default `44 * scale`), and have `WatchPerimeterLayer` pass 40. Icons
  are spaced `iconSpacing * scale` ≈ 22–25 pt apart, so neighbouring hit circles overlap
  a little; the nearer centre wins, which is what a finger expects.
- Done when: tapping just outside a blip's drawn edge still focuses it on a 41 mm Watch.

### B4 · P3 · Double tap opens Identify when already on the nearest
- Where: `WatchRadarView.swift` ~376, `.handGestureShortcut(.primaryAction)` sits on the
  Nearest button, which only exists while `showNearest`. On the nearest aircraft the
  gesture does nothing.
- Change: one view carries the shortcut at a time: the Nearest button when it shows, the
  pointer button otherwise (`isOnNearest`). Update the tour's "Tap, hold, double tap" row
  and the pointer button's accessibility hint.
- Done when: on the nearest aircraft double tap opens Identify; on any other it returns
  to the nearest.

### B5 · P3 · Nearby list rows
- Where: `WatchNearbyList.swift` `row(_:)` (~56–93): a generic `airplane` / `fan.fill`
  symbol (~60), no row actions.
- Change: the aircraft's own `AircraftGlyph(silhouette: contact.profile.silhouette,
  size: 16)` turned like the radar's; `.swipeActions` with Pin (`model.focus(on:)` then
  `togglePin`) and Find (`open(.find(id))`). Optional: an "Approaching first" order
  (`isApproaching`, then distance) as a toolbar menu, remembered in `WatchSettings`.
- Done when: rows show the right silhouette and a left swipe offers Pin and Find.

### B6 · P3 · Detail page polish
- Where: `WatchFlightDetail.swift`: the Pin button (~204–213) decides "Pin" vs "Unpin" from
  `model.focus.focusedID == contact.id && model.focus.isPinned`, so a pinned aircraft
  that isn't the focus reads "Pin to Center"; the "Look" stat (~152) shows the cardinal
  with no arrow while Distance has one.
- Change: `model.isPinned(contact.id)` for the button; give Look the same rotating
  `location.north.fill` arrow as Distance (or drop Distance's, not both). "Seen before"
  arrives with C5.
- Done when: a pinned, unfocused aircraft's page says Unpin; the two stats agree.

---

## Part C — Options and features

### C1 · P2 · Battery saver
- Where: `WatchSettingsView.swift` Radar section (~41–58); `PollingPolicy.interval`
  (distance-based, no refresh setting any more; `lowPower` stretches it); `RadarModel.pollFloor` is
  10 s on watchOS; `WatchLocationService.precision`; `settings.radarSweep`.
- Change: one toggle, `wtf.watch.batterySaver`, in `WatchSettings`. On: polling stretched
  further than Low Power Mode (a multiplier on `PollingPolicy.interval`), sweep off, compass filter 6° (A3), blip and label
  springs off (as Reduce Motion does), `precision` `.radar` stays as is (pointing still
  gets `.pointing`: it is the point of the feature). Off restores the normal interval and the sweep.
  Footer: "Updates less often; the radar still moves between updates."
- Done when: two 30-minute sessions on the same sky, saver on and off, show a clear
  difference in Settings → Battery; the hero keeps dead-reckoning at 1 Hz either way.

### C2 · P2 · Alert distance and lead time on the Watch
- Where: `WatchSettingsView.swift` Wrist alerts section (~72–80) has only the Overhead,
  Notable and Haptics toggles. `overheadAlertMiles` (`RadarSettings.swift` ~174) arrives
  only through `WatchSync.Context` (`WatchSettings.apply` ~64–76);
  `overheadAlertLeadSeconds` (~176) is not in the context at all, so the Watch always
  uses 150 s.
- What happens: a standalone Watch user can never change when the wrist taps.
- Change: a "Within" picker (1 / 1.5 / 2 / 3 mi) and an "Ahead" picker (1 / 2 / 3 / 5 min)
  in the section. Add `overheadAlertLeadSeconds` to `WatchSync.Context` as an optional
  field (stays `v: 1`; absent → keep the Watch's value). Rule, as in Apple Watch Spec
  §6.2: the phone's values apply when a context arrives; Watch edits hold until then.
- Done when: 3 mi on the Watch makes the demo's overhead haptic fire at 3 mi; a new
  context from the phone updates the pickers.

### C3 · P2 · Identify range and precision
- Where: `Core/WristPointing.swift` ~172 `identifyRangeMiles = 15`, ~179 `identifyCone = 10`,
  ~15 `lockDegrees = 8`; `WatchRootView.swift` ~118 sets
  `queryRadiusFloor = identifyRangeMiles + 1`; `IdentifyView` uses
  `IdentifyTracker.keepCone` (15). `candidates(…, cone:rangeMiles:)` and
  `isIdentifiable(_:rangeMiles:)` already take parameters.
- What happens: over a hub a 10° cone holds three aircraft at once; in open country 15 mi
  misses the contrail you can plainly see.
- Change: Settings → Identify & Find: "Range" (10 / 15 / 25 mi, `wtf.watch.identifyRange`)
  and "Precision" (Tight 6° / Normal 10° / Wide 15°, `wtf.watch.identifyCone`). Thread
  them through `candidates`, `isIdentifiable`, `IdentifyTracker.keepCone` (cone + 5), the
  query floor, and `lead`'s span (3 × cone). Find keeps `lockDegrees`.
- Done when: Wide names an aircraft 14° off the arm; 25 mi lists aircraft the 10 mi radar
  hides; `IdentifyTests` cover both parameters.

### C4 · P3 · Read aloud only with headphones
- Where: `WatchSensors.swift`, `IdentifySpeaker` (~317–339): `.playback` with `.voicePrompt`
  and `.duckOthers`, so with nothing connected it talks through the Watch speaker.
- What happens: a Watch announcing "Delta 570, a Boeing 757" at full volume in a quiet
  park is not what everyone wants; the only alternative is turning Read aloud off.
- Change: `wtf.watch.speakVia` = Speaker and headphones / Headphones only. Before
  speaking, check `AVAudioSession.sharedInstance().currentRoute.outputs` for
  `.bluetoothA2DP`, `.bluetoothLE` or `.headphones`; with "Headphones only" and none,
  skip the speech (the `.success` haptic still plays).
- Done when: with Headphones only and no AirPods, Identify locks silently; connect them
  and it speaks.

### C5 · P1 · Logbook on the Watch
- Where: `Radar/Logbook.swift`, `LogbookDigest`, `LogbookSky` and `LogbookAchievements` are
  already in the Watch membership list; `Services/LogbookSync.swift` is not;
  `RadarModel.logbook` is never set on the Watch (`WatchRootView`). Apple Watch Spec §5.8
  and §6.3 (deferred on Oct 20); Enhancements Spec C2 (watchlist) wants the logbook on
  every device.
- What happens: a flight seen with only the Watch along is never logged; "Seen before"
  and badges don't exist on the wrist.
- Change:
  1. Add `Services/LogbookSync.swift` to the Watch target; `CKSyncEngine` runs on watchOS
     10+. The Watch entitlements need the iCloud container
     `iCloud.SargeyWargey.WhatTheFlight` and CloudKit, next to the kvstore id already
     there. Photo records: the Watch never downloads a `SpotPhoto` asset (no gallery), so
     skip `downloadPhoto` paths; sightings carry the photo ids and that is enough.
  2. `WatchRootView`: `@LazyState logbook = Logbook()`, `model.logbook = logbook` only
     while `watchSettings.locationSource == .here` (`RadarModel.isLogging` keys on
     `locationMode == .device`, which the Watch always is, so "iPhone's spot" would
     otherwise log the phone's sky under the Watch's name). `logbook.flush()` on
     `.background`. `LogDevice.watch` already exists. `keepLogbook` and `iCloudLogbook`
     join `WatchSync.Context` as optional fields.
  3. UI: "Seen 3× before · first Oct 2" on `WatchFlightDetail` from
     `Logbook.summary(airframe:)`; a Today / Total row at the top of the settings page;
     `logbook.onBadgeUnlocked` → `.success` haptic and a short full-screen card
     (symbol, title), Apple Watch Spec §5.7. No stats pages on the Watch.
- Done when: a flight seen on the Watch alone appears in the iPhone logbook within a
  minute with device Apple Watch; a regular's detail page says "Seen before"; a badge
  earned on the Watch taps the wrist and shows its card.

### C6 · P2 · More complications and date-window relevance <span style="color:#00E676; font-weight:900; font-size:1.2em">✅ IMPLEMENTED</span>
- Where: `WatchComplications.swift` has one kind, `WatchOverhead` (~89–100); relevance is
  `TimelineEntryRelevance` (~81–86), which is what Enhancements Spec C6's Watch half was
  closed with.
- Change:
  - `IdentifyComplication`, corner and circular, static, `widgetURL` `whattheflight://sky`:
    one tap from the face to pointing.
  - An "In range" circular: `inRangeCount` in a ring, same provider.
  - `WidgetRelevance` (watchOS 11, the app's minimum): implement
    `relevance() async -> WidgetRelevance<Void>` on `OverheadProvider` with
    `WidgetRelevanceAttribute(context: .date(from: now, to: pass))` when a closest pass
    is within five minutes, so the Smart Stack lifts the card before the pass rather than
    scoring entries after the fact. Keep `TimelineEntryRelevance` alongside.
- Done when: the Identify complication opens Identify directly; during a demo pass the
  Overhead card rises in the Smart Stack before the pass.
- *As built:* four kinds (`WatchComplicationKind`): **Nearest Aircraft** (the old
  `WatchOverhead` kind, redrawn: the aircraft's silhouette on a north-up ring at its
  bearing, nose along its track, miles inside; the card adds a little radar on 45 mm and
  up), **Sky Radar** (new, `WatchRadar`: every aircraft on a north-up scope, the nearest
  picked out; corner label and inline give the in-range count, which stands in for the
  "In range" circular), **Next Overhead** (new, `WatchNextOverhead`: counts down to the
  next aircraft passing within the overhead alert's distance, with a ring that drains
  over the last five minutes and "overhead now" for a minute as it goes over; tap opens
  Find on it) and **Identify** (`WatchIdentify`: circular, corner and inline, static,
  `whattheflight://sky`). `NearbyTraffic.timeline` adds a moment at each pass and as it
  clears. `SkyProvider.relevance()` returns a date window from five minutes before each
  pass to a minute after for Nearest and Next Overhead (`date(interval:kind:)` on
  watchOS 26, `date(from:to:)` before that); `TimelineEntryRelevance` stays. The Watch
  app calls `invalidateRelevance` whenever it reloads timelines. A demo pass can't show
  this: the complications fetch live traffic, never demo traffic. Not yet checked on a
  real face or in the Smart Stack; the DEBUG gallery (`-wtf.debugScreen complications`)
  shows the designs.

### C7 · P2 · "Find that plane" intent, for Siri and the Action button
- Where: `WatchIntents.swift` has `WatchWhatsOverheadIntent` (~12) and
  `IdentifyPlaneIntent` (~35). `CLAUDE.md` names a `FindThatPlaneIntent` that doesn't
  exist. `WatchRouter.Route.find(id)` already opens Find.
- Change: `FindThatPlaneIntent` (`openAppWhenRun = true`): fetch
  `NearbyTraffic.contacts` around the shared observer, set
  `WatchRouter.shared.pending = .find(nearest.id)`, or `.identify` when the sky is
  empty. Add it to `WatchShortcuts` ("Find that plane", "Where's that plane"). Ultra
  owners bind it to the Action button in the Shortcuts app; nothing else needed. Fix the
  `CLAUDE.md` mention.
- Done when: "Find that plane" opens Find on the nearest aircraft from Siri and from the
  Action button.

---

## Done in the October 25 battery pass
- `WatchRootView` reads nothing per tick: the centre state lives in `WatchRadarView`, the
  settings page's count in `WatchNearbyCount`.
- `WristPointer` publishes `pointing` only once the arm has moved
  `WristPointing.redrawDegrees` (0.5°), at the 30 Hz sampling rate underneath.
- `WatchLocationService.precision`: `radar` (100 m, 150 m filter), `pointing` (10 m) while
  Identify or Find is open, `coarse` (3 km) in iPhone's-spot mode for true north only.
- The approach chip's glow and the focused blip's pulse stop under `isLuminanceReduced`.
- `RadarModel.isStale` (a failed poll, or none for 75 s, with a grace after `start()`):
  the hero and detail chips become "NO SIGNAL · 1:32" (tap retries), an empty radar
  shows No signal + Retry, never in Always-On.
- Point with the wrist judged down: speech session set up on open plus the `audio`
  background mode, the lock as a wrist-tap notification (`WristTapNotification`), dimmed
  layouts for Identify and Find, Return to Clock guidance in settings and the tour.

## Not in this spec
- Metric units: Enhancements Spec C10 (cross-platform; the Watch follows).
- Watchlist and "new to your logbook" alerts: Enhancements Spec C2 (after C5 here).
- The iPhone half of Smart Stack and the countdown widget: Enhancements Spec C6.
- Sky View on the Watch, Watch-only background monitoring, TV control: Apple Watch Spec
  non-goals.
