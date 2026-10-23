# Enhancements — spec

Everything from the October 2026 review of the iPhone, Apple Watch and Apple TV apps,
except the Ambient Map (own spec: `Ambient Map Spec.md`) and the work already in progress
in the tree (iCloud logbook sync via `LogbookSync`, the first-run tours, reverse-geocoded
place names, the app-icon picker). Read `CLAUDE.md` first.

How to use this: every item stands alone and says where it lives, what is wrong or
missing, the change, and how to know it is done. Pick items by the priority tags. Line
numbers were correct when this was written; the tree is moving, so search by symbol if
one has drifted. Run `cd WhatTheFlight && swift test` after anything that touches `Core/`,
`Data/`, `Radar/` or the platform-neutral services; it must stay green.

Priority tags: **P1** fix before the next release · **P2** next · **P3** when convenient.

Suggested order: A1–A5, then B2 → B1 → B3 (they make the Watch cheaper to run), then
B4 → B8, then the features in the order listed. C10 (units) before C4 (share card), because
the card uses the formatters. C2 (watchlist) after `LogbookSync` lands, because "first in
your logbook" should mean across devices.

---

## Part A — Bugs

### A1 · P1 · Watch keeps GPS and polling running after leaving Find / Identify with the wrist down <span style="color:#00E676; font-weight:900; font-size:1.2em">✅ IMPLEMENTED</span>
- *As built:* `WatchRootView.isTracking` (active, or inactive while pointing) drives start/stop, and `isDimmedRadar` keys the once-a-minute clock task.
- Where: `WhatTheFlightWatch/WatchRootView.swift` — `.onChange(of: scenePhase)` (~112) and
  `.task(id: scenePhase)` (~132) both guard on `isPointing` (~171), but only run when the
  scene phase *changes*.
- What happens: open Find or Identify, lower the wrist (phase → `.inactive`, tracking
  continues on purpose), back out of Find while the wrist is still down. `path` changes,
  `scenePhase` does not, so nothing stops the model or GPS. Full-rate polling and
  ten-metre GPS run through the whole Always-On period.
- Change: derive one value, `let tracking = scenePhase == .active || isPointing`, and drive
  start/stop and the once-a-minute `advanceClock()` loop from it:
  `.onChange(of: tracking)` and `.task(id: tracking)`. Keep the `.background` branch as is.
- Done when: with `-wtf.debugScreen find`, lowering the wrist then pressing back leaves
  `model.isRunning == false` and `location` stopped (assert via a debug overlay or log),
  and raising the wrist restarts both.

### A2 · P1 · Sky View camera can be left running after the view closes
- Where: `Services/SkyServices.swift`, `SkyCamera.start()` / `stop()` (~126–170).
- What happens: `stop()` sets `state = .idle` synchronously and queues `stopRunning()`. If
  it lands while `start()` is still awaiting its continuation, `start()` resumes, reads
  `session.isRunning == true` and writes `state = .running` *after* the stop. Raise then
  immediately lower the phone (what `RaiseToSkyDetector` makes easy) and the capture
  session and the green camera indicator stay alive; the next `start()` is refused by its
  `guard state == .idle || .denied`.
- Change: a generation counter. `stop()` increments `generation`; `start()` captures it
  before the await and afterwards does
  `guard generation == captured else { queue.async { session.stopRunning() }; return }`.
  Also honour `Task.isCancelled` after the await, since `.task { await camera.start() }`
  is cancellable.
- Done when: raising and lowering the phone ten times in a row ends with no camera
  indicator, `state == .idle`, and the next raise shows the feed.

### A3 · P1 · Apple TV swallows a first-time location denial
- Where: `Services/PlaceServices.swift`, `TVLocationProvider.locationManagerDidChangeAuthorization` (~184).
- What happens: `locate()` with `.notDetermined` requests permission and sets `wantsFix`.
  The callback only acts when authorised. Tap Don't Allow and `lastError` stays nil, so
  the tile in `TVSettingsView.tvLocationDetail` (~348) shows the generic "Approximate, from
  Wi-Fi" line. The real message appears only on a second tap.
- Change: in the callback, `else if wantsFix, isDenied { lastError = "Location access is off for WhatTheFlight in tvOS Settings."; wantsFix = false }`.
- Done when: fresh install, Use This Apple TV → Don't Allow → the tile explains it at once.

### A4 · P1 · Aircraft photo bytes bypass the compliant session <span style="color:#00E676; font-weight:900; font-size:1.2em">✅ IMPLEMENTED</span>
- Where: `UI/FlightDetailSheet.swift` `PhotoCard` (~314), `UI/TV/TVFlightScreens.swift` (~193),
  `UI/TV/TVLogbookView.swift` (~790). All use `AsyncImage(url:)`.
- What happens: `AircraftPhotoProvider` exists because Planespotters requires a descriptive
  User-Agent, and it already exposes `imageData(for:)`, which the Watch uses
  (`WatchFlightDetail.swift` ~264). On iPhone and TV only the JSON call carries the
  User-Agent; the image itself goes through the default session with no cache tuning.
- Change: one `ProviderPhoto` view (`#if os(iOS) || os(tvOS)`) with the same phase
  behaviour as the current `AsyncImage` closures (placeholder, image, failure) that loads
  through `AircraftPhotoProvider.shared.imageData(for:)` into `@State`. Replace the three
  call sites. Keep the photographer credit.
- Done when: `grep -rn "AsyncImage(" WhatTheFlight/WhatTheFlight` returns nothing, and a
  proxy shows the `WhatTheFlight/2.0` User-Agent on image requests.

### A5 · P1 · Top Shelf fetches photos one at a time
- Where: `WhatTheFlightTopShelf/ContentProvider.swift` (~19–32).
- What happens: one live traffic fetch, then up to eight photo lookups awaited serially,
  each of which can be two requests with a ten-second timeout. Top Shelf has a tight
  budget; on a slow network the row never updates.
- Change: build the items first without images, then fetch all photos in a
  `withTaskGroup` and apply whatever has arrived by an overall deadline of about six
  seconds (race the group against a sleeping task). Return items without images rather
  than nothing.
- Done when: with Network Link Conditioner on "3G", the Top Shelf row still appears with
  titles, and photos fill in on the next load.

### A6 · P2 · Dynamic Type is unsupported
- Where: `UI/Theme.swift:78`, `Font.mono(_:_:)` is `.system(size:weight:design:)`, a fixed
  point size used by every label on every platform.
- Decision: the radar face, the Watch radar and the whole TV stay fixed; they are
  compass layouts and a ten-foot UI. Everything else scales: settings, logbook, flight
  details, search, whereabouts, the tours, Sky View's card.
- Change: add a `ScaledMono` view modifier using `@ScaledMetric(relativeTo:)` on the
  size, exposed as `.monoScaled(15, .semibold, relativeTo: .body)`. Swap it in across
  the sheets listed above. Cap with `.dynamicTypeSize(...DynamicTypeSize.accessibility2)`
  where a row layout breaks, and let `LabeledContent` rows wrap.
- Done when: at Accessibility 3 size the settings, logbook and detail text is visibly
  larger with no clipped labels; the radar hero is unchanged.

### A7 · P2 · Reduce Motion misses the largest motion on screen
- Where: `UI/Theme.swift` `ContinuousRotation` (~111–128) animates every glyph and bezel
  rotation unconditionally; `UI/PerimeterLayer.swift` springs (~30, ~42, ~53);
  `UI/RadarScreen.swift` bezel spring (~45–48); `UI/TV/TVRadarScreen.swift` (~68–80).
  The sweep, pulse, glow and rotor already check `accessibilityReduceMotion`.
- Change: read `@Environment(\.accessibilityReduceMotion)` in each and pass `nil` as the
  animation when it is on (`withAnimation(reduceMotion ? nil : .interactiveSpring(...))`,
  `.animation(reduceMotion ? nil : .smooth(...), value:)`). Shared across iPhone, Watch, TV
  because `PerimeterLayer` and `Theme` are shared.
- Done when: Reduce Motion on → icons, labels and the bezel snap; off → unchanged.

### A8 · P2 · Watch accessibility text sizes hide the perimeter and show nothing in its place
- Where: `WhatTheFlightWatch/WatchRadarView.swift` (~73), `if !perimeterHidden { … }` has no else.
- Change: an else branch with a small capsule button, "N more nearby", that selects the
  Nearby page. That needs the `TabView` selection in `WatchRootView` passed down as a
  binding (today the pages have no selection state).
- Done when: at an accessibility text size the radar shows the hero plus the button, and
  the button lands on the Nearby list.

### A9 · P2 · Watch perimeter is a VoiceOver label with no action
- Where: `WatchRadarView.swift` (~416), `.accessibilityElement(children: .ignore)` plus a
  label "N more aircraft. Use the list for details."
- Change: add `.accessibilityAction(named: "Show nearby list")` using the same selection
  binding as A8. Keep the screen-level Nearest / Next / Previous actions.
- Done when: VoiceOver double-tap on the perimeter element opens the Nearby page.

### A10 · P3 · Watch pointing sits silent when the compass has no heading
- Where: `WhatTheFlightWatch/WatchSensors.swift`, `.compassOnly` case (~218) returns early
  while `heading()` is nil, so `pointing` stays nil and Identify / Find show their normal
  prompt forever. The "No motion sensors" message only covers `.unavailable`.
- Change: a `status` on `WristPointer` (`ready`, `waitingForCompass`, `unavailable`). After
  three seconds in `waitingForCompass`, Identify and Find show "Waiting for the compass.
  Move your arm in a figure eight."
- Done when: in the simulator with `-wtf.debugPointing` unset and no heading, the message
  appears; on hardware it clears as soon as a heading arrives.

### A11 · P3 · Apple TV link cannot retry after advertising fails
- Where: `Services/TVLink.swift`, `TVLinkReceiver.start()` (~79) guards on `advertiser == nil`;
  `didNotStartAdvertisingPeer` (~130) calls `fail(_:)` and leaves the advertiser set.
- What happens: refuse Local Network on first use and "Waiting for iPhone" never changes;
  `start()` from the next foreground is a no-op. Only a background/foreground cycle clears it.
- Change: in `fail(_:)`, stop and nil the advertiser. Add a "Try again" button to the
  failed state in `TVSettingsView` (~283–306) that calls `stop()` then `start()`.
- Done when: deny Local Network, allow it in tvOS Settings, press Try again → "Waiting for iPhone".

### A12 · P3 · iPhone → TV send task outlives the screen <span style="color:#00E676; font-weight:900; font-size:1.2em">✅ IMPLEMENTED</span>
- *As built:* also fixed `waitUntil`, which swallowed the sleep's cancellation and would have spun until its deadline once cancelled.
- Where: `UI/TVLinkSetupView.swift` `send()` (~260) wraps `link.send` in a bare `Task`;
  `.onDisappear` stops the link but never cancels the task, which can wait twenty seconds.
- Change: keep the task in `@State`, cancel it in `onDisappear`, and have
  `TVLinkSender.send` check `Task.isCancelled` between its waits.
- Done when: back out mid-send → no later state change, no log noise.

### A13 · P3 · Apple TV refetches on every radius step <span style="color:#00E676; font-weight:900; font-size:1.2em">✅ IMPLEMENTED</span>
- *As built:* re-filters on every step and re-queries once the chips have been still for 700 ms (`radiusEdits` + `.task(id:)`), without the iPhone pattern's extra fetch at launch.
- Where: `UI/TV/TVRadarRootView.swift:151`, `.onChange(of: settings.radiusMiles) { model.settingsDidChange(refetch: true) }`.
- Change: mirror the iPhone's pattern in `RadarRootView` (`.task(id: settings.radiusMiles)`,
  re-filter now, refetch after 700 ms of quiet).
- Done when: stepping the radius chips five times fast causes one network request.

---

## Part B — Performance and engineering

### B1 · P2 · Resolve per-flight derived data once per feed, not every tick <span style="color:#00E676; font-weight:900; font-size:1.2em">✅ IMPLEMENTED</span>
- Where: `Core/Flight.swift` (`kind`, `silhouette`, `typeName`, `airline`), `Core/OperatorInfo.swift`,
  `Core/NotableTraffic.swift` are computed properties doing catalog lookups and string
  work. `Radar/RadarModel.recompute()` calls them for every contact every second through
  `Logbook.record` and `TrafficAlertEngine.evaluate`; views and `SnapshotFlight` call
  them again.
- Change: `struct FlightProfile: Equatable, Sendable { operatorInfo, notable, kind, silhouette, typeName, airline }`
  built once per flight id in `RadarModel.apply(_:)` (rebuild only when type code,
  callsign, registration, airline or squawk changed). `RadarContact` carries `profile`.
  Logbook, alerts, `SnapshotFlight`, hero, perimeter, search and lists read
  `contact.profile.*`. The `Flight` computed properties stay for widgets, Top Shelf and
  tests.
- Done when: a Time Profiler run on the Watch with 20 demo aircraft shows no
  `NotableTraffic.classify` or `AirlineCatalog.airline` frames under the tick; tests for
  profile reuse in `FocusAndRadarModelTests`.

### B2 · P2 · The perimeter track is rebuilt about seven times per frame <span style="color:#00E676; font-weight:900; font-size:1.2em">✅ IMPLEMENTED</span>
- *As built:* the samples are cached inside `PerimeterTrack` by rect and corner radius (`PerimeterTrack.sampleBuilds` counts real builds), and `RadarLayout` / `WatchRadarLayout` store their tracks, so no `@State` layout was needed.
- Where: `UI/RadarScreen.swift` `RadarLayout.iconTrack` / `bezelTrack` (~146–152) are
  computed properties; each `PerimeterTrack.init` samples 1,440 points with `atan2`
  (`Core/PerimeterTrack.swift` ~13–41). The body reads them through `obstacles`,
  `gearPoint`, `statusPoint` and the planner call every tick. `WatchRadarView.swift`'s
  layout and `TVRadarScreen` have the same shape.
- Change: make `RadarLayout` (and the Watch / TV equivalents) store `let iconTrack` /
  `let bezelTrack` built in `init`, and cache the layout in `@State` keyed on the
  geometry size (`.onChange(of: geo.size, initial: true)`).
- Done when: a debug counter on `PerimeterTrack.init` increments once per size change,
  not per tick.

### B3 · P2 · Warm the catalogs off the main thread <span style="color:#00E676; font-weight:900; font-size:1.2em">✅ IMPLEMENTED</span>
- *As built:* `Catalogs.warmUp()` (end of `Data/AircraftTypeCatalog.swift`), called from the iPhone/TV and Watch `App` inits and at the top of the widget, complication and Top Shelf providers.
- Where: `Data/AirlineCatalog.swift` and `Data/AirportCatalog.swift` parse ~14,600 lines of
  embedded text into dictionaries on first access, which lands inside the first
  `recompute()` on the main actor; `AircraftTypeCatalog` is smaller but the same.
- Change: in each root view's `onAppear` (iPhone, Watch, TV) and at the top of the widget,
  complication and Top Shelf providers, `Task.detached(priority: .utility) { _ = AirlineCatalog.airline(icao: "DAL"); _ = AirportCatalog.airport(iata: "ATL"); _ = AircraftTypeCatalog.name(forTypeCode: "B738") }`.
  Static lets are initialised once and thread-safe. Later, optionally, generate a binary
  plist from `Scripts/generate_catalogs.py` instead of source text.
- Done when: an `os_signpost` around the first recompute shows no catalog cost on the Watch.

### B4 · P2 · Stop compiling the legacy stack into the iPhone and TV apps
- Where: `ContentView.swift`, `Views/FlightDisplayView.swift`, `Views/SettingsView.swift`,
  `Views/iOSComponents.swift`, `Views/tvOSComponents.swift`, `ViewModels/*`,
  `Services/FlightService.swift`, `NetworkManager.swift`, `LocationManager.swift`,
  `SettingsManager.swift`, `AircraftPhotoService.swift`, `AircraftPredictionService.swift`,
  `AirportDatabase.swift`, `IconLayeringManager.swift`, `Models/FlightData.swift`,
  `ConnectionStatus.swift`, `NotificationSettings.swift`, `DisplayPreferences.swift`.
  About 12,400 lines. None are referenced by the v2 code (verified by grep; the only hits
  are `CMMotionManager`). Only macOS still runs `ContentView`.
- Change, phase 1 (safe): move them into `Legacy/` and wrap every file in `#if os(macOS)`.
  Do the same for the legacy tests under `WhatTheFlightTests/` and `WhatTheFlightUITests/`,
  which are why the Xcode test targets do not compile; `WhatTheFlightTests/Radar/` must
  then build and run from Xcode as well as `swift test`.
  Phase 2 (after C11): delete `Legacy/`.
- Also fix the stale line in `CLAUDE.md` saying tvOS runs the legacy stack; it runs `TVRadarRootView`.
- Done when: iOS and tvOS builds contain no legacy symbols (check with `nm` or the link
  map), the Xcode test action runs the radar tests, macOS still launches.

### B5 · P2 · Adaptive polling <span style="color:#00E676; font-weight:900; font-size:1.2em">✅ IMPLEMENTED</span>
- *As built:* "passing close" = within a mile now, or a closest pass under a mile within 90 s (`PollingPolicy.isPassingClose`), so a hub's distant traffic doesn't keep it at 5 s.
- Where: `Radar/RadarModel.pollOnce()` returns `settings.refreshSeconds` on success.
- Change: a pure `PollingPolicy.interval(base:contacts:outside:)` in `Core/`:
  any in-range contact with a closest pass ahead within 90 s or under a mile → `min(base, 5)`;
  nothing in range and nothing outside → `min(60, base * 3)`; otherwise `base`. The Watch
  never goes below 10 s. Keep the error backoff as is.
- Done when: unit tests cover the three branches; the status badge's "updated Ns ago"
  still reads correctly at the long interval.

### B6 · P3 · Keep trails only where they are used
- Where: `RadarModel.updateTrails(with:)` keeps up to 240 points for every flight in the
  query box, which at a 100 mi radius over a hub is hundreds of aircraft.
- Change: keep trails for flights within `radiusMiles * 1.5` plus the focused / pinned
  aircraft. Coordinate with the Ambient Map, which reads trails for in-range aircraft only.
- Done when: memory in the Xcode gauge no longer climbs with radius at 100 mi.

### B7 · P3 · Dead-reckon altitude as well as position
- Where: `Core/Flight.swift` `predictedCoordinate(at:)` moves the position; altitude is
  shown as reported until the next poll.
- Change: `predictedAltitudeFeet(at:)` = altitude + vertical rate × elapsed minutes, capped
  at the same 90 s, floored at 0. Use it in `RadarContact` (new `altitudeFeet`), the hero,
  the detail telemetry, Sky View's elevation, and `SpokenTraffic`.
- Done when: a climbing demo aircraft's altitude ticks between polls.

### B8 · P2 · Continuous integration
- Where: there is no `.github/`.
- Change: `.github/workflows/ci.yml` on `macos-latest`: `cd WhatTheFlight && swift test`,
  then `xcodebuild build` for the `WhatTheFlight` scheme on an iOS simulator and a tvOS
  simulator, and `WhatTheFlightWatch` on a watchOS simulator, all with
  `CODE_SIGNING_ALLOWED=NO`. Cache DerivedData.
- Done when: a pull request shows four green checks.

### B9 · P3 · Index the logbook by airframe <span style="color:#00E676; font-weight:900; font-size:1.2em">✅ IMPLEMENTED</span>
- Where: `Radar/Logbook.swift` `timesSeen`, `history(airframe:)`, `seenBeforeSummary` scan
  all sightings; they run from detail sheets and the hero's "seen before" line.
- Change: `byAirframe: [String: [Int]]` maintained next to `index`, rebuilt in
  `rebuildIndex()`. Coordinate with `LogbookSync` merging.
- Done when: the detail sheet opens without a visible pause at 10,000 sightings.

---

## Part C — Features

### C1 · P1 · A second data source with automatic fallback
- Why first: the feed is an unofficial Flightradar24 endpoint behind a spoofed Safari
  User-Agent (`Services/FlightFeed.swift`). A format change or a block takes all three apps
  down the same hour. `protocol FlightFeed` already makes a second provider cheap.
- Candidates (verify terms and rate limits before choosing; endpoints as understood at
  the time of writing): airplanes.live (`/v2/point/{lat}/{lon}/{radius_nm}`), adsb.lol
  (`/v2/lat/{lat}/lon/{lon}/dist/{nm}`), adsb.fi. All return the readsb JSON shape:
  `hex`, `flight` (callsign), `r` (registration), `t` (type), `lat`, `lon`, `alt_baro`,
  `gs`, `track`, `baro_rate`, `squawk`, `seen_pos`. They do not carry route, flight number
  or airline; the catalogs recover the airline from the callsign.
- Design:
  - `ReadsbFeed: FlightFeed` with a base URL and a parser (`Core/ReadsbParser.swift`, unit
    tested like `FlightFeedParser`). Flight id = `hex`; `positionTime = receivedAt - seen_pos`;
    `isOnGround` from `alt_baro == "ground"`.
  - `FallbackFeed: FlightFeed` wrapping primary and secondary: use the secondary after two
    consecutive primary failures, retry the primary every five minutes, and report which
    source answered (`FeedSource`). `RadarModel` exposes `source` for the status badge
    ("via airplanes.live").
  - Setting `wtf.dataSource`: Automatic (default) / Flightradar24 / the secondary. Settings
    → Radar on iPhone and TV; the Watch follows its own default (Automatic).
  - Logbook ids differ between sources (FR24 flight id vs. hex). Accept a possible
    duplicate sighting across a switch; do not try to merge.
- Done when: blocking `data-cloud.flightradar24.com` at the router leaves the radar live
  with the badge naming the source; unit tests cover the parser and the switch logic.

### C2 · P1 · Watchlist and "new to your logbook" alerts
- What the user sees: Settings → Alerts → Watchlist, a list of rules such as "N685DA",
  "any Boeing 747", "Qatar Airways", "callsign REACH". From a flight's details: "Alert me
  when this aircraft returns" and "Alert me for any <type>". Plus automatic alerts the
  first time a type, airline or airframe appears in the logbook: "First Qatar Airways in
  your logbook", "First 747".
- Design:
  - `WatchlistRule: Codable { kind: registration | type | airline | callsignPrefix; value }`,
    stored as JSON under `wtf.watchlist`, edited in `RadarSettings`. Sent to the Watch in
    `WatchSync.Context` (bump `currentVersion`). The TV keeps its own list.
  - `TrafficAlert.Reason` gains `.watchlist` and `.firstSeen`. `TrafficAlertRules` gains
    `watchlist: [WatchlistRule]`, `firstSeen: Bool` and a closure
    `isNew: (Flight) -> FirstSeenKind?` the model fills from `Logbook` (keep three `Set`s of
    seen type codes, airline names and airframes, maintained in `record` and after a sync
    merge). Once per flight per reason, as today.
  - Spoken forms in `SpokenTraffic`; notification category unchanged; the Watch long-look
    already renders any reason.
- Done when: unit tests for every rule kind and for first-seen; a rule added on iPhone
  fires on the Watch within one context update.

### C3 · P1 · A phase-of-flight line on the hero
- What the user sees, under the type line: "On approach to ATL · 12 mi out",
  "Climbing out of ATL", "Cruising · 2h 05m to DFW", "Descending toward DFW". Short form on
  the Watch hero ("Approach ATL"). Also in details and in `SpokenTraffic.identification`.
- Design: `Core/FlightPhase.swift`, pure, from `RouteProgress`, `verticalTrend`, altitude
  and ground speed: destination within 40 mi and descending, or under 10,000 ft and
  within 25 mi → approaching; origin within 30 mi and climbing → departing; otherwise
  climbing / descending by trend; else cruising with the remaining time when
  `RouteProgress.remainingSeconds` is known. No route → trend only.
- Done when: unit tests for each branch; the line never shows for helicopters without a route.

### C4 · P2 · Shareable sighting card and logbook export
- Card: a 1080 × 1350 image from `ImageRenderer` at 3×: silhouette glyph, identifier,
  operator, route with cities, type, altitude, speed, closest pass, place and date, and a
  map snippet from `MKMapSnapshotter` with the trail. No aircraft photo on the card unless
  Planespotters' terms allow redistribution; the silhouette and map carry it.
  `ShareLink(item:preview:)` with a `Transferable` image. Entry points: the detail sheet's
  share button (keep the text item too) and a logbook sighting's page.
- Export: Logbook → Export, `fileExporter` with a `FileDocument` CSV: first seen, last
  seen, identifier, callsign, registration, hex, type, operator, origin, destination,
  closest miles, altitude, speed, tags, place, device.
- Done when: the card renders in light and dark; the CSV opens in Numbers with headers.

### C5 · P2 · Airframe facts
- What the user sees: "Built 1998 · 28 years" and the manufacturer on the hero's type
  line and in details; a Vintage badge for thirty-year-old airframes.
- Design: `AircraftFactsProvider` actor modelled on `AircraftPhotoProvider` (cache, in-flight
  dedupe, descriptive User-Agent) against a free lookup such as adsbdb
  (`/v0/aircraft/{registration}`); confirm which fields it returns before committing.
  Setting "Aircraft facts" beside "Aircraft photos". Privacy decision: show manufacturer
  and year for everything; show the registered owner only when it is an organisation,
  never a person's name.
- Done when: facts appear within a second on Wi-Fi, never block the hero, and the
  toggle off removes every network call.

### C6 · P2 · Smart Stack relevance and a countdown widget <span style="color:#FFB300; font-weight:900; font-size:1.2em">◐ PARTLY IMPLEMENTED</span>
- <span style="color:#00E676; font-weight:900; font-size:1.5em">✅ IMPLEMENTED</span> Watch: in `WhatTheFlightWatchWidgets/WatchComplications.swift`, implement widget
  relevance so the complication surfaces when a closest pass is within five minutes
  (`WidgetRelevance` with date-interval contexts from `NearbyTraffic.projectedSnapshots`).
- iPhone: a "Next overhead" entry in `WhatTheFlightWidgets` for small and rectangular
  families using `Text(timerInterval:)` counting down to the snapshot's closest pass, so
  it reads right in StandBy. An interactive Start Sky Watch button needs
  `StartSkyWatchIntent` to adopt `LiveActivityIntent`; verify that background location
  can be enabled from that path before promising it, otherwise the button opens the app.
- Done when: the complication appears in the Smart Stack during a demo overhead pass;
  the widget counts down without refreshing.

### C7 · P3 · Sky View extras <span style="color:#FFB300; font-weight:900; font-size:1.2em">◐ PARTLY IMPLEMENTED</span>
- <span style="color:#00E676; font-weight:900; font-size:1.5em">✅ IMPLEMENTED</span> Snapshot: an `AVCapturePhotoOutput` on the existing session; compose the labels over the
  photo with `ImageRenderer` and save with the Photos add-only permission.
- Predicted path: project the ten-minute `projectedPath` through `SkyProjector` and draw a
  dashed `Path` for the locked aircraft.
- Rising soon: aircraft approaching with elevation under 3° listed in the card area:
  "Rising soon: DL570 from the SW in 2:10".
- Done when: a snapshot lands in Photos with readable labels; the path draws only for the
  locked aircraft.

### C8 · P2 · Saved spots
- What the user sees: Settings → Location lists named spots (Home, Office, Airport fence);
  pick one to watch; "Save this spot" from the picker and the TV's place search.
- Design: `SavedSpot: Codable { id, name, latitude, longitude }` as JSON under `wtf.spots`
  in `RadarSettings`; selecting one sets `customCoordinate` and `customPlaceName` as today,
  so the rest of the app is untouched. Include the name in `TVLink.Payload`. Logging rules
  stay: the TV logs its spot, the iPhone does not log a custom spot.
- Done when: three spots round-trip through relaunch on iPhone and TV.

### C9 · P3 · Daily digest
- iPhone only. At app background, compute today's logbook numbers and schedule one
  `UNCalendarNotificationTrigger` for 20:00 local (setting `wtf.digest`, time editable):
  "Today: 142 aircraft · 3 new types · closest N44RH at 0.3 mi". Only when the logbook grew
  today. Tapping opens the logbook via `AppRouter`.
- Done when: a day with sightings produces one notification; a day without produces none.

### C10 · P2 · Metric units
- Design: `wtf.units` = imperial / metric, defaulting from `Locale.current.measurementSystem`.
  `RadarFormat` gains unit-aware `distance`, `altitude`, `speed` returning value and unit;
  every call site goes through them (hero, perimeter labels, details, lists, widgets,
  `SpokenTraffic`, Siri, Watch, TV). Add to `WatchSync.Context`. Internals stay in miles,
  feet and knots.
- Done when: `grep -rn '" mi\| ft"\| kts"'` over the UI finds no remaining literals; the
  radius slider shows km.

### C11 · P3 · Retire the legacy macOS app via Designed for iPad
- After B4. Enable the iPad app on Apple silicon, then check on a Mac: location works
  (no heading → north up, bezel still), Sky View hides when no camera, Multipeer pairing
  works, the window is resizable with the radar centred. Then delete `Legacy/` and the
  macOS-only scene in `WhatTheFlightApp.swift`.
- Done when: the Mac build is the iPad build and the repo has no legacy sources.

---

## Not in this spec
- Ambient Map (`Ambient Map Spec.md`).
- In progress elsewhere: `LogbookSync`, the iPhone / TV / Watch tours, reverse-geocoded
  place names, the app-icon picker.
