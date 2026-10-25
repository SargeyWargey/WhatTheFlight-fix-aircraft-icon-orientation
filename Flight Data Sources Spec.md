# Flight Data Sources — spec

Goal: the radar, the logbook, pins, search and "Where is it now?" run on open data first, with
the Flightradar24 web feed as the last resort, and with no visible loss of performance or
accuracy. This replaces Enhancements Spec C1 ("A second data source with automatic fallback"),
whose candidate list is out of date (see §2).

Research done 2026-10-25 on branch `feed-independence`. The measurements in §1 are single
snapshots, so treat the percentages as rough. Provider terms change often; re-check §2 before
shipping.

---

## 1. What we measured

Same patch of sky, same minute, airborne aircraft only, inside the radius.

| Place (radius) | FR24 | adsb.lol | In both | Only FR24 | Only adsb.lol | Median position age, FR24 / adsb.lol |
|---|---|---|---|---|---|---|
| Atlanta (25 mi) | 47 | 46 | 43 | 1 (+3 with no hex) | 3 | 3.9 s / 0.2 s |
| London Heathrow (25 mi) | 18 | 19 | 17 | 0 | 2 | 2.9 s / 0.1 s |
| Nairobi (40 mi) | 4 | 4 | 4 | 0 | 0 | 4.2 s / 0.7 s |
| São Paulo (25 mi) | 12 | 11 | 10 | 1 | 1 | 3.7 s / 0.4 s |
| **Mumbai (25 mi)** | **7** | **4** | 4 | **3** | 0 | 4.5 s / **15.9 s** |

- **Airborne coverage:** equal in the US, UK, Kenya and Brazil. The open feeds' extra aircraft
  are mostly LADD-flagged ones that FR24 hides (three at Atlanta). Coverage is **thin in India**,
  and probably in other places with few community receivers.
- **Freshness:** open positions are 3–4 s fresher. Dead reckoning already starts from each
  fix's own time, so this makes the radar slightly more accurate, not less.
- **Ground traffic:** an open feed saw 31 of FR24's 50 aircraft on the ground at ATL (LHR: 24 vs
  23). FR24 has airport ground receivers the community lacks. This matters for "on the ground at ATL".
- **Routes:** FR24 gave origin and destination for 37 of 47 at Atlanta and 17 of 18 at Heathrow.
  None of the open position feeds carry routes (§3).
- **Payload:** Atlanta at 25 mi was 6.7 KB gzipped / 35 KB JSON from adsb.lol, against 2.6 KB / 7 KB
  from FR24. Point queries include ground traffic (about half the payload at a hub) and can't
  filter it out server-side. Parsing 35 KB every 10 s is negligible, even on the Watch (10 mi
  radius, much smaller).
- **Latency:** adsb.lol 550–1,100 ms, FR24 about 220 ms. That's hidden behind dead reckoning at
  5–15 s polls.
- **Fields:** airborne readsb records carried everything the radar uses: hex, callsign,
  registration (`r`), type (`t`), track, ground speed, baro rate (or geom rate), squawk, plus
  `category` (A7 = rotorcraft) and `dbFlags` (1 military, 4 PIA, 8 LADD).

## 2. Who can supply positions

| Provider | Usable in a free App Store app? | Limits | Notes |
|---|---|---|---|
| **adsb.lol** | **Yes**, ODbL 1.0, attribution required | Keyless: 4/s, 60/min, **500/day** per IP (headers on every response) | "If you want to use the API for production purposes, please contact me." Key request form at adsb.lol/request asks how you comply with ODbL. Comma lists; exact matches only. About 6,400 feeders. |
| **FlyItalyADSB** | **Yes**, commercial use allowed on every plan, CC BY-SA 4.0 | Free key: 30/min **for the whole product** (all users together), 300k/month. Paid €9–249/month. | API launched Aug 2026; about 3,200 feeders. No multi-aircraft requests. |
| adsb.fi | Only with written permission ("personal, non-commercial use only") | 1/s per IP | Fastest in our tests and carries owner and build year. Worth an email. |
| airplanes.live | No | — | Closed to non-feeders since Aug 2026 (returns 403 "contact us"). |
| ADS-B Exchange | No | Paid (RapidAPI) | Any app made available to others counts as commercial; redistribution prohibited. |
| OpenSky | No, without a written licence | 400–8,000 credits/day | Any live product needs a licence. |
| FR24 official API | Allowed, but doesn't fit | $9–900/month | Can't be mixed with another provider's data, 30-day storage cap (conflicts with the logbook), tokens can't ship in an app. |

**What this means:** adsb.lol is the only open primary, and its keyless limit can't carry real
use. An Apple TV left on at the default 10 s refresh makes about 8,600 radar requests a day,
plus up to 2 every 20 s for pins outside the box. Per-IP limits are also shared by every device
behind one home router. Before shipping we need either an adsb.lol production key, or a
small caching server that makes one upstream request per area and serves every user.
FlyItalyADSB's free key is fine as a failover; its product-wide 30/min can't be a primary
without a paid plan.

## 3. Routes and flight numbers

FR24's routes come from airline schedules. Every open route source is a callsign → airports
table, which is right for most mainline flights and wrong for airlines that reuse flight numbers.

| Source | Verdict |
|---|---|
| **VRS standing data** (github.com/vradarserver/standing-data) | **Use.** CC0, updated daily, 621k routes, one CSV per airline (Delta 110 KB; 4.6 MB gzipped in all). Fetch on demand from a commit-pinned jsDelivr URL or bundle it. |
| adsb.im routeset | Possible second opinion, but it has no published terms; ask first. |
| adsb.lol routeset | Avoid: plausibility code is broken (every route passes), data a month old, often returns empty. |
| adsbdb, hexdb | Avoid: route data may not be copied without permission (adsbdb); stale (hexdb). |
| OpenSky flights | Nightly batch, previous day only. |

How wrong are raw callsign routes? Snapshot of 480 aircraft above 3,000 ft around ORD, ATL and
LHR: VRS had a route for 73%, and 26% of those were geometrically impossible. US mainline was
6–16% impossible, US regionals 21–35%, **Southwest about 90%, Ryanair 88%, easyJet 71%**,
British Airways 0%. A published study found adsbdb right on 29% of US flights against filed
FAA plans and about 79% elsewhere.

**Flight numbers:** IATA airline code + callsign digits works for most US and Asian mainline
flights. It breaks for alphanumeric callsigns (easyJet 85%, Ryanair 82%, Air France 79%, BA 52%
and Lufthansa 41% of their callsigns contain letters, e.g. BA238 flying as BAW29G) and for US
regionals flying for mainline brands (a SkyWest callsign SKW5432 is sold as DL5432 or UA5432).
No open dataset maps these.

**So routes and flight numbers are where "no accuracy impact" can't be fully met from open data
alone.** With strict checks (§4.3) the app would rarely show a wrong route, but at a hub like
Atlanta (Delta, its regionals, Southwest) it would show noticeably fewer routes than today, and
regional flights would read "EDV5079" instead of "DL5079". Everything that reads a route goes
with it: the hero's route line, route progress, airport pins on the map, the logbook's route,
airport and country rankings, and route badges (Six Continents, Long Haul).

## 4. Design

### 4.1 Source ladder
- `ReadsbFeed: FlightFeed` with a base URL, key and parser (`Core/ReadsbParser.swift`, unit tested
  like `FlightFeedParser`). One type serves adsb.lol and FlyItalyADSB (same shape; FlyItaly takes
  km and an `X-Api-Key` header).
  - `positionTime` = response `now` − `seen_pos`, never later than the receive time.
  - Skip records without a position and, for the radar, `alt_baro == "ground"`.
  - `track` falls back to `true_heading`; vertical rate `baro_rate` → `geom_rate`.
  - `category == "A7"` → helicopter when the type code is unknown. `dbFlags & 1` → military
    (feeds `NotableTraffic`).
- `LayeredFeed: FlightFeed` tries adsb.lol → FlyItalyADSB → FR24.
  - Steps down after two consecutive failures or any 429.
  - Retries the source above every five minutes.
  - Reports which source answered (`FeedSource`); `RadarModel` exposes it for the status badge
    ("via adsb.lol").
- **Coverage check (keeps parity in places like Mumbai):** on the first fix at a place, and
  every 30 minutes while the radar runs, make one FR24 request beside the open one and compare
  airborne hex sets (LADD excluded).
  - If the open feed sees under 85% of FR24's aircraft, use FR24 for that ~50 km grid square for
    24 h, remembered on disk.
  - In well-covered places this costs two FR24 requests an hour instead of 360–720.
- One shared rate limiter per host (an actor): honours `x-ratelimit-*` and `Retry-After`, and
  coalesces identical in-flight requests (radar, widget refresh, Siri). The Apple Watch Spec's
  planned phone → Watch relay halves a household's volume again.
- Setting `wtf.dataSource`: **Automatic** (the ladder), **Open data only** (FR24 never called),
  **Flightradar24** (today's behaviour). Settings → Radar on iPhone/iPad and TV; the Watch
  follows Automatic.

### 4.2 Identity (the per-leg id)
FR24 gives every flight leg its own id. ADS-B only has the airframe's hex, which stays the same
across legs and days. The id feeds the logbook, CloudKit records, pins, alerts ("once per flight
per reason"), trails, focus and deep links.
- Use one **source-independent** id for every source, FR24 included:
  `<hex>-<normalised callsign>-<UTC yyyyMMdd>`. Two devices, or a mid-flight switch from adsb.lol
  to FR24, then agree on the id. Without that, a fallback would reset focus and trails and fire
  alerts twice. FR24 rows with no hex keep `fr24-<id>`.
- Logbook: when a known id reappears after more than two hours, start a new sighting (`…-2`).
  When a new id starts within two hours of a sighting with the same hex and callsign, extend that
  sighting instead. This covers flights crossing midnight UTC and GA aircraft whose callsign is
  their registration all day.
- Existing sightings keep their FR24 ids. Pins already match by registration, then callsign.

### 4.3 Routes
- `RouteResolver` actor:
  - Fetches each airline's VRS file on first need from a commit-pinned jsDelivr URL, keeps it on
    disk and refreshes daily (ETag).
  - Parses it into `[callsign: [ICAO airport]]` off the main thread.
  - `AirportCatalog` needs ICAO codes added (`Scripts/generate_catalogs.py`; OurAirports has them).
- Plausibility check, run in the per-feed pass beside `FlightProfile`, never per tick. A leg
  A → B passes when either:
  - the aircraft is within 150 km of A or B and its track fits departing A or arriving at B; or
  - cross-track ≤ max(50 nm, 15% of the leg), it is between the two airports along the track,
    and its track is within ±75° of the bearing to B.

  Below 10,000 ft and far from both airports, reject.
- For multi-stop routes, show only the leg that passes.
- Show a route after two passing updates at least 30 s apart; drop it as soon as one fails.
- Never show routes for SWA, RYR, EZY, EJU, or charter and air-taxi callsigns.
- Cache answers by flight id; the pass/fail verdict is per aircraft, never shared.
- `Logbook.record` fills in `originIATA` / `destinationIATA` (and `displayIdentifier`) when a
  sighting has none and the contact now has a confirmed route. Today they're written only when
  a sighting is created. `Sighting.merged(with:)` prefers the non-nil route.
- Optional FR24 enrichment (decision 2): while an in-radius airline flight has no confirmed
  route, make one FR24 box request at most every two minutes and keep its routes and flight
  numbers by flight id. That's at most 30 an hour instead of 360–720.

### 4.4 Flight numbers
Derive `flightNumber` = airline IATA + callsign suffix only when the suffix is all digits and the
operator isn't a US regional (SKW, ENY, RPA, EDV, JIA, PDT, ASH, GJS, QXE…). Otherwise leave it
nil, and `displayIdentifier` already falls back to the callsign. With FR24 enrichment on,
FR24's flight number wins.

### 4.5 Search, pins and "Where is it now?"
- **Pins:** adsb.lol takes comma lists, so it's one `/v2/reg/A,B,…` and one `/v2/callsign/…`
  request per lookup (hex once the airframe's been seen). FlyItalyADSB needs one request per pin.
- **Search:** open APIs match exactly. Turn "DL570" into "DAL570" (`AirlineCatalog` IATA → ICAO)
  and keep `RegistrationCountry.hyphenatedForms`. Prefix search ("N68") only exists on FR24, so
  use FR24 when the open search finds nothing. It's user-typed and rare.
- **Where is it now?:** open feeds drop an aircraft 60 s after its last message, and ground
  coverage is thinner. Ask the open feed first; if it finds nothing, ask FR24.
- Widgets, Top Shelf, complications and Siri go through `NearbyTraffic`, which takes the same
  `LayeredFeed`.

### 4.6 Credits, privacy and the store
- Settings → About, the website and the store's "About the data":
  - "Contains information from adsb.lol, which is made available under the Open Database
    License (ODbL)."
  - "Flight data: FlyItalyADSB (flyitalyadsb.com), CC BY-SA 4.0."
  - Routes from Virtual Radar Server standing data.
  - Shareable cards are ODbL "produced works" and carry a short credit.
- The privacy label is unchanged ("Data Not Linked to You: Location"), but the explanation in
  `AppStore/3 Privacy and Review.md` now names adsb.lol and FlyItalyADSB as well.
- **LADD:** the open feeds include aircraft whose owners asked the FAA to limit display. FR24
  hides them. Default: hide `dbFlags & 8` too (decision 4).
- As long as any FR24 request ships, Guideline 5.2.2 and the Content Rights question in
  `AppStore/README.md` still apply. Fewer requests lower the chance of a block, not the
  licensing problem. "Open data only" is the setting that removes it.

## 5. Decisions to make
1. **Production access:** email adsb.lol for a production key (only you can), and take
   FlyItalyADSB's free key for failover; or plan a small caching server.
2. **Routes:** open data only (fewer routes, rarely wrong), or open plus the two-minute FR24
   enrichment (close to today's accuracy, 90–95% fewer FR24 requests).
3. **FR24 in the App Store build:** Automatic by default, or ship with "Open data only" and keep
   FR24 for development.
4. **LADD aircraft:** hide like FR24 (recommended) or show.

## 6. Phases
1. `ReadsbParser`, `ReadsbFeed` (adsb.lol) and the per-host limiter.
   - Done when: parser tests pass on recorded responses, and the radar runs on adsb.lol with
     `-wtf.dataSource open`.
2. Source-independent ids plus the logbook's visit split, merge and route fill-in.
   - Done when: unit tests cover midnight UTC, a GA aircraft's two visits, and an FR24 ↔ open
     switch mid-flight.
3. `RouteResolver` (VRS, ICAO airports, plausibility) and derived flight numbers.
   - Done when: unit tests cover each rule; Southwest shows no route; the hero never shows a
     reversed route.
4. `LayeredFeed`, coverage check, `wtf.dataSource`, status badge.
   - Done when: blocking `api.adsb.lol` at the router leaves the radar live via FlyItalyADSB or
     FR24, with the badge saying which; a forced thin-coverage square uses FR24.
5. Search, pins and Where is it now on the ladder; widgets, Top Shelf and Siri through it.
6. FR24 enrichment (if chosen), credits, store and privacy text, CLAUDE.md.

## 7. Cost per user (checked 2026-10-25)

No usage analytics exist. Traffic density comes from the one real logbook (a simulator afternoon
on 2026-10-23, 20 mi radius): about 30 aircraft in range at once at Atlanta, 44 at New York.
Usage levels are assumptions: light 10 min a day (5 h a month), typical 30 min a day (15 h),
heavy an Apple TV on 3 h a day plus the phone (105 h).

**FR24 official API.**
- Live positions are billed **per aircraft returned**: 6 credits each, $0.000222 a credit on
  the $900 Advanced plan. The query box today is 3.5× the radius circle (1.5 × radius + 3 mi
  square); a tight box is 1.27×.
- Per user per month at Atlanta-level traffic:

| Usage | As the app works today (10 s, today's box) | Cut down (30 s, tight box) |
|---|---|---|
| Light | $250 | $31 |
| Typical | $750 | $92 |
| Heavy | $5,200 | $640 |

  A quiet suburb (8 in range) is about a quarter of that.
- Also: 90 queries a minute for the whole app on Advanced (15 devices at once at 10 s); no data
  kept past 30 days (conflicts with the logbook); can't be mixed with open data, which rules
  out the one cheap use (routes via Flight summary light, 1 credit a flight); the token can't
  ship in the app, so it needs a server anyway. Not viable for a consumer radar.

**Open data.**
- adsb.lol: free with a production key.
- Own caching server (Cloudflare Workers Paid): $5 a month including 10M requests (about 1,850
  typical users), then $0.30 a million. That's under $0.01 per user per month, heavy included.
- FlyItalyADSB as primary instead: €49–249 a month flat. At the €249 tier (about 166 devices at
  once) that's roughly €0.08 per typical user and €0.54 per heavy user per month.
- Routes (VRS standing data via jsDelivr): free.
