//
//  RadarModel.swift
//  WhatTheFlight
//
//  The radar's state machine: polls the feed, dead-reckons every aircraft once a second,
//  keeps the in-range list sorted by distance and decides which aircraft owns the centre.
//  It knows nothing about CoreLocation managers or views — the observer position is pushed
//  in — which keeps it fully unit-testable.
//

import Foundation
import CoreLocation
import Observation

struct RadarNotice: Identifiable, Equatable, Sendable {
    let id = UUID()
    let symbol: String
    let text: String
}

@MainActor
@Observable
final class RadarModel {
    enum FeedStatus: Equatable {
        case idle
        case loading
        case live
        case error(String)
    }

    // MARK: Published state

    /// Aircraft inside the radius, nearest first.
    private(set) var contacts: [RadarContact] = []
    /// Aircraft the feed returned that are outside the radius (useful for search / pinning).
    private(set) var outsideContacts: [RadarContact] = []
    private(set) var status: FeedStatus = .idle
    private(set) var lastUpdated: Date?
    private(set) var focus = RadarFocus()
    private(set) var notice: RadarNotice?
    private(set) var observer: CLLocationCoordinate2D?
    private(set) var now = Date()
    private(set) var hasLoadedOnce = false
    /// Bumped whenever the trails change (once per feed, not per tick), so views that draw
    /// them rebuild only then.
    private(set) var trailVersion = 0

    // MARK: Dependencies

    @ObservationIgnored let settings: RadarSettings
    @ObservationIgnored private let liveFeed: FlightFeed
    @ObservationIgnored private let demoFeed: FlightFeed
    @ObservationIgnored private var flights: [Flight] = []
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var lastQueryCenter: CLLocationCoordinate2D?
    @ObservationIgnored private var consecutiveFailures = 0
    @ObservationIgnored private(set) var isRunning = false
    @ObservationIgnored private var queuedNotices: [RadarNotice] = []
    /// Positions the feed reported for each flight while we watched, oldest first.
    @ObservationIgnored private var trails: [String: [TrailPoint]] = [:]
    @ObservationIgnored private var alertEngine = TrafficAlertEngine()
    /// Pinned aircraft found by a worldwide lookup because the main feed's box missed them.
    @ObservationIgnored private var pinnedFlights: [Flight] = []
    @ObservationIgnored private var lastPinLookup = Date.distantPast
    /// Each flight's operator, tags and type, built once per feed instead of every tick.
    @ObservationIgnored private var profiles: [String: FlightProfile] = [:]

    static let maxPins = 5
    /// Apple Watch polls no faster than every 10 s, whatever is overhead (battery).
    #if os(watchOS)
    static let pollFloor: TimeInterval = 10
    #else
    static let pollFloor = PollingPolicy.fastestSeconds
    #endif
    /// Worldwide lookups for far-away pins are a separate request, so they run less often.
    static let pinLookupInterval: TimeInterval = 20

    /// Query at least this far out whatever the radius (Apple Watch's Identify looks 15 mi).
    @ObservationIgnored var queryRadiusFloor: Double = 0
    /// The widest map ring showing this traffic, when wider than the radar's (the Apple TV's
    /// own map range). Trails are kept to 1.5× the wider ring, as far as maps draw them.
    @ObservationIgnored var trailRadiusFloor: Double = 0
    /// Sightings are recorded here: live traffic only, never demo, and never a custom spot
    /// unless `logsCustomSpot` (the Apple TV, whose "custom" spot is where the TV really is).
    @ObservationIgnored var logbook: Logbook?
    @ObservationIgnored var logsCustomSpot = false
    /// "Atlanta, GA" for where you are now, stamped on sightings (set by the app as it
    /// reverse-geocodes the observer).
    @ObservationIgnored var logPlaceName: String?
    /// Called for every new overhead / notable alert. Unset, alerts become notices.
    @ObservationIgnored var onAlert: ((TrafficAlert) -> Void)?

    struct TrailPoint: Equatable, Sendable {
        let latitude: Double
        let longitude: Double
        let altitudeFeet: Int
        let time: Date
        var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    }

    init(settings: RadarSettings, liveFeed: FlightFeed = FlightRadarFeed(), demoFeed: FlightFeed = DemoTrafficFeed()) {
        self.settings = settings
        self.liveFeed = liveFeed
        self.demoFeed = demoFeed
        // Pins saved under an older, higher limit.
        if settings.pinnedAircraft.count > Self.maxPins {
            settings.pinnedAircraft.removeFirst(settings.pinnedAircraft.count - Self.maxPins)
        }
    }

    // MARK: Derived

    var allContacts: [RadarContact] { contacts + outsideContacts }

    var focusedContact: RadarContact? {
        guard let id = focus.focusedID else { return nil }
        return contacts.first { $0.id == id } ?? outsideContacts.first { $0.id == id }
    }

    func contact(id: String) -> RadarContact? {
        contacts.first { $0.id == id } ?? outsideContacts.first { $0.id == id }
    }

    var isDemo: Bool { settings.demoTraffic }

    /// Aircraft the user pinned, oldest first.
    var pins: [PinnedAircraft] { settings.pinnedAircraft }

    var pinnedIDs: Set<String> { Set(settings.pinnedAircraft.map(\.flightID)) }

    func isPinned(_ id: String?) -> Bool {
        guard let id else { return false }
        return settings.pinnedAircraft.contains { $0.flightID == id }
    }

    /// Pinned aircraft outside the radius, however far: still on the radar edge and the map.
    var pinnedOutside: [RadarContact] { outsideContacts.filter { isPinned($0.id) } }

    /// What rides the radar edge: far-away pins first (so the icon cap never drops them),
    /// then everything in range.
    var perimeterContacts: [RadarContact] { pinnedOutside + contacts }

    enum PinState {
        case visible(RadarContact)
        case onGround(Flight)
        /// Not transmitting, or not looked up yet.
        case unseen
    }

    func state(of pin: PinnedAircraft) -> PinState {
        if let contact = contact(id: pin.flightID) { return .visible(contact) }
        if let parked = (flights + pinnedFlights).first(where: { pin.matches($0) && $0.isOnGround }) { return .onGround(parked) }
        return .unseen
    }

    /// Whether what's on the radar now goes into the logbook. Browsing somewhere else (a
    /// custom spot on the iPhone) or demo traffic never does: the book is what you saw.
    var isLogging: Bool {
        settings.keepLogbook && !settings.demoTraffic && (logsCustomSpot || settings.locationMode == .device)
    }

    // MARK: Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        startPolling()
        startTicking()
    }

    func stop() {
        isRunning = false
        pollTask?.cancel()
        tickTask?.cancel()
        pollTask = nil
        tickTask = nil
    }

    /// Re-query immediately (pull to refresh, settings change, retry button…).
    func refreshNow() {
        guard isRunning else { return }
        pollTask?.cancel()
        startPolling()
    }

    /// Call after radius / helicopter / demo settings change.
    func settingsDidChange(refetch: Bool) {
        recompute()
        if refetch {
            if settings.demoTraffic != (lastFeedWasDemo ?? settings.demoTraffic) {
                // Demo aircraft don't exist outside the demo.
                settings.pinnedAircraft.removeAll { $0.flightID.hasPrefix("demo-") }
                pinnedFlights = []
                flights = []
                contacts = []
                outsideContacts = []
                hasLoadedOnce = false
                focus = RadarFocus()
            }
            refreshNow()
        }
    }

    @ObservationIgnored private var lastFeedWasDemo: Bool?

    /// Moves the observer. Re-queries when they've moved far enough that the query box is stale.
    func setObserver(_ coordinate: CLLocationCoordinate2D?) {
        let previous = observer
        observer = coordinate
        if let previous, let coordinate,
           GeoMath.distanceMiles(from: previous, to: coordinate) > settings.radiusMiles {
            // A jump to a different place (e.g. a new custom spot): start fresh rather than
            // announcing that every old aircraft "left the radius".
            flights = []
            focus = RadarFocus()
            hasLoadedOnce = false
            lastQueryCenter = nil
            refreshNow()
        }
        recompute()
        guard let coordinate else { return }
        if let last = lastQueryCenter {
            let moved = GeoMath.distanceMiles(from: last, to: coordinate)
            if moved > max(0.5, settings.radiusMiles * 0.2) { refreshNow() }
        } else if previous == nil {
            refreshNow()
        }
    }

    /// Moves the dead-reckoning clock without polling: Apple Watch's Always-On display
    /// redraws about once a minute while the wrist is down and the model is stopped.
    func advanceClock(to date: Date = Date()) {
        now = date
        recompute()
    }

    // MARK: Focus actions

    /// Swipe right: snap back to the current nearest aircraft.
    func focusNearest() {
        setFocus(FocusPolicy.nearest(contacts))
    }

    /// Swipe left: step outwards to the next-nearest aircraft, then on to far-away pins.
    func focusNext() {
        setFocus(FocusPolicy.next(after: focus, inRange: contacts + pinnedOutside))
    }

    /// Remote ◀: step inwards toward the nearest aircraft.
    func focusPrevious() {
        setFocus(FocusPolicy.previous(before: focus, inRange: contacts + pinnedOutside))
    }

    /// Every focus change goes through here so `focus.isPinned` always says whether the
    /// focused aircraft is one of the pins.
    private func setFocus(_ new: RadarFocus) {
        var new = new
        new.isPinned = isPinned(new.focusedID)
        if new != focus { focus = new }
    }

    /// Shows a transient message (e.g. "Location received from iPhone"). Messages that arrive
    /// while one is showing wait their turn.
    func post(notice text: String, symbol: String) {
        let new = RadarNotice(symbol: symbol, text: text)
        if notice == nil {
            notice = new
        } else if queuedNotices.count < 4 {
            queuedNotices.append(new)
        }
    }

    /// Where the feed has seen this flight so far (thinned to roughly one point per poll).
    func trail(for id: String) -> [TrailPoint] {
        trails[id] ?? []
    }

    /// Tap on a perimeter icon or a search result. Aircraft outside the radius are pinned
    /// automatically, otherwise they'd be replaced on the very next tick.
    func focus(on id: String) {
        if !contacts.contains(where: { $0.id == id }), !isPinned(id), let flight = contact(id: id)?.flight {
            pin(flight)
        }
        setFocus(RadarFocus(focusedID: id))
    }

    /// Pins or unpins the focused aircraft.
    func togglePin() {
        guard let id = focus.focusedID else { return }
        if isPinned(id) {
            unpin(id)
        } else if let flight = contact(id: id)?.flight {
            pin(flight)
        }
    }

    /// Follows this aircraft wherever it goes, with a pin on its icon. Past `maxPins` the
    /// oldest pin makes way, with a notice saying which.
    func pin(_ flight: Flight) {
        var pins = settings.pinnedAircraft.filter { !$0.matches(flight) }
        pins.append(PinnedAircraft(flight))
        let dropped = pins.count > Self.maxPins ? Array(pins.prefix(pins.count - Self.maxPins)) : []
        pins.removeFirst(dropped.count)
        settings.pinnedAircraft = pins
        pinnedFlights.removeAll { f in dropped.contains { $0.matches(f) } }
        if !flights.contains(where: { $0.id == flight.id }) {
            pinnedFlights.removeAll { $0.id == flight.id }
            pinnedFlights.append(flight)
        }
        if let id = focus.focusedID, dropped.contains(where: { $0.flightID == id }), !contacts.contains(where: { $0.id == id }) {
            setFocus(FocusPolicy.nearest(contacts))
        } else {
            setFocus(focus)
        }
        recompute()
        if let first = dropped.first {
            post(notice: "\(first.label) unpinned to make room · \(Self.maxPins) pins max", symbol: "pin.slash")
        }
    }

    func unpin(_ id: String) {
        guard let pin = settings.pinnedAircraft.first(where: { $0.flightID == id }) else { return }
        unpin(pin)
    }

    func unpin(_ pin: PinnedAircraft) {
        settings.pinnedAircraft.removeAll { $0 == pin }
        pinnedFlights.removeAll { pin.matches($0) }
        if let id = focus.focusedID, pin.flightID == id, !contacts.contains(where: { $0.id == id }) {
            // Far away and no longer pinned: hand the centre back without a "left" notice.
            setFocus(FocusPolicy.nearest(contacts))
        } else {
            setFocus(focus)
        }
        recompute()
    }

    /// Pins changed on another device (`PinSync`): drop what's no longer pinned, and go and
    /// find what arrived straight away.
    func pinsDidChangeElsewhere(arrived: [PinnedAircraft]) {
        pinnedFlights.removeAll { f in !settings.pinnedAircraft.contains { $0.matches(f) } }
        if let id = focus.focusedID, !isPinned(id), !contacts.contains(where: { $0.id == id }) {
            setFocus(FocusPolicy.nearest(contacts))
        } else {
            setFocus(focus)
        }
        recompute()
        guard let first = arrived.first else { return }
        post(notice: arrived.count == 1 ? "\(first.label) pinned on another device" : "\(arrived.count) aircraft pinned on another device",
             symbol: "pin.fill")
        lastPinLookup = .distantPast
        refreshNow()
    }

    /// A search result: pin it and bring it to the centre. False when it can't be shown
    /// yet (on the ground, say); it stays pinned and appears once it's airborne.
    @discardableResult
    func track(_ flight: Flight) -> Bool {
        pin(flight)
        guard contact(id: flight.id) != nil else { return false }
        setFocus(RadarFocus(focusedID: flight.id))
        return true
    }

    // MARK: Search

    #if DEBUG
    /// `-wtf.debugPin GXLEB`: searches the world and pins (and centres) the first result.
    func debugPinIfRequested() {
        guard let query = UserDefaults.standard.string(forKey: "wtf.debugPin") else { return }
        Task {
            try? await Task.sleep(for: .seconds(2))
            if let hit = try? await searchAnywhere(query).first { track(hit.flight) }
        }
    }
    #endif

    /// Aircraft anywhere in the world whose tail number, flight number or callsign starts
    /// with `query`: exact matches first, then airborne before parked, then nearest.
    /// Demo traffic searches itself.
    func searchAnywhere(_ query: String) async throws -> [RadarContact] {
        let q = query.uppercased().filter { !$0.isWhitespace }
        guard let observer, q.count >= 3 else { return [] }
        let found = settings.demoTraffic
            ? flights.filter { $0.matches(search: q) }
            : try await liveFeed.search(q)
        let bare = q.replacingOccurrences(of: "-", with: "")
        func isExact(_ f: Flight) -> Bool {
            [f.registration?.replacingOccurrences(of: "-", with: ""), f.flightNumber, f.callsign].contains { $0?.uppercased() == bare }
        }
        let now = Date()
        // Rank first and build contacts (and their profiles) for the 40 kept only.
        let ranked = found
            .map { (flight: $0, miles: GeoMath.distanceMiles(from: observer, to: $0.predictedCoordinate(at: now))) }
            .sorted { a, b in
                let ka = (isExact(a.flight) ? 0 : 1, a.flight.isOnGround ? 1 : 0)
                let kb = (isExact(b.flight) ? 0 : 1, b.flight.isOnGround ? 1 : 0)
                return ka != kb ? ka < kb : a.miles < b.miles
            }
            .prefix(40)
        return ranked.map { RadarContact(flight: $0.flight, observer: observer, at: now, profile: profiles[$0.flight.id]) }
    }

    func dismissNotice(_ id: RadarNotice.ID) {
        guard notice?.id == id else { return }
        notice = queuedNotices.isEmpty ? nil : queuedNotices.removeFirst()
    }

    // MARK: Polling

    private func startPolling() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let delay = await self?.pollOnce() else { return }
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    /// Performs one fetch and returns how long to wait before the next one.
    @discardableResult
    func pollOnce() async -> TimeInterval {
        guard let observer else { return 1 }
        let useDemo = settings.demoTraffic
        let feed = useDemo ? demoFeed : liveFeed
        // Query a little beyond the radius so aircraft are known before they enter it,
        // and pinned aircraft can be followed after they leave.
        let bounds = GeographicBounds.around(center: observer, radiusMiles: max(settings.radiusMiles * 1.5 + 3, queryRadiusFloor))
        if !hasLoadedOnce { status = .loading }
        do {
            let result = try await feed.flights(in: bounds)
            try Task.checkCancellation()
            lastQueryCenter = observer
            lastFeedWasDemo = useDemo
            if consecutiveFailures > 0 { Log.feed.notice("Feed back after \(self.consecutiveFailures) failed polls") }
            consecutiveFailures = 0
            apply(result)
            status = .live
            if !useDemo { await refreshPins() }
            let next = PollingPolicy.interval(base: settings.refreshSeconds, contacts: contacts, outside: outsideContacts,
                                              floor: Self.pollFloor)
            Log.feed.debug("\(self.contacts.count) in range, \(self.outsideContacts.count) outside; next poll in \(next, format: .fixed(precision: 0)) s")
            return next
        } catch is CancellationError {
            return 0
        } catch {
            consecutiveFailures += 1
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            status = .error(message)
            let backoff = settings.refreshSeconds * pow(2, Double(min(consecutiveFailures, 3)))
            let floor = (error as? FeedError) == .rateLimited ? 30.0 : 0
            let delay = min(90, max(floor, backoff))
            Log.feed.error("Poll failed (\(self.consecutiveFailures) in a row): \(message, privacy: .public); retrying in \(delay, format: .fixed(precision: 0)) s")
            return delay
        }
    }

    private func apply(_ result: [Flight]) {
        flights = result
        lastUpdated = Date()
        adoptPinIDs(from: result)
        // A pin the main feed now covers doesn't need its looked-up copy.
        pinnedFlights.removeAll { old in
            !settings.pinnedAircraft.contains { pin in pin.matches(old) && !result.contains(where: pin.matches) }
        }
        updateTrails(with: result)
        pruneProfiles()
        hasLoadedOnce = true
        now = Date()
        recompute()
    }

    // MARK: Profiles

    private func profile(for flight: Flight) -> FlightProfile {
        if let cached = profiles[flight.id], cached.isCurrent(for: flight) { return cached }
        let fresh = FlightProfile(flight)
        profiles[flight.id] = fresh
        return fresh
    }

    /// Forgets flights the feed no longer reports.
    private func pruneProfiles() {
        let live = Set((flights + pinnedFlights).map(\.id))
        profiles = profiles.filter { live.contains($0.key) }
    }

    // MARK: Pins

    /// Pins the main feed didn't include are looked up worldwide, every 20 s or so, and
    /// dead-reckoned in between like everything else.
    private func refreshPins() async {
        let missing = settings.pinnedAircraft.filter { pin in !flights.contains(where: pin.matches) }
        guard !missing.isEmpty else { return }
        guard Date().timeIntervalSince(lastPinLookup) >= max(Self.pinLookupInterval, settings.refreshSeconds) else { return }
        lastPinLookup = Date()
        let registrations = missing.compactMap(\.registration)
        let callsigns = missing.filter { $0.registration == nil }.compactMap(\.callsign)
        guard !registrations.isEmpty || !callsigns.isEmpty else { return }
        let found: [Flight]
        do {
            found = try await liveFeed.lookup(registrations: registrations, callsigns: callsigns)
        } catch {
            Log.feed.info("Pin lookup failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard !Task.isCancelled else { return }
        let located = missing.compactMap { pin in
            found.filter(pin.matches).max { $0.positionTime < $1.positionTime }
        }
        // A pin this lookup missed keeps its last position for a while (patchy coverage).
        let cutoff = Date().addingTimeInterval(-10 * 60)
        let kept = pinnedFlights.filter { old in
            old.positionTime > cutoff && missing.contains { pin in pin.matches(old) && !located.contains(where: pin.matches) }
        }
        pinnedFlights = located + kept
        adoptPinIDs(from: located)
        updateTrails(with: located)
        pruneProfiles()
        recompute()
    }

    /// Flightradar24 gives each leg a new flight id: follow the airframe onto it.
    private func adoptPinIDs(from candidates: [Flight]) {
        var pins = settings.pinnedAircraft
        var changed = false
        for i in pins.indices where !candidates.contains(where: { $0.id == pins[i].flightID }) {
            if let f = candidates.filter(pins[i].matches).max(by: { $0.positionTime < $1.positionTime }) {
                if focus.focusedID == pins[i].flightID { focus.focusedID = f.id }
                pins[i].flightID = f.id
                pins[i].label = f.displayIdentifier
                changed = true
            }
        }
        if changed { settings.pinnedAircraft = pins }
    }

    /// Trails are kept only where a map draws them: out to 1.5× the ring (fringe traffic),
    /// plus the focused and pinned aircraft wherever they are. A wide radius over a hub
    /// otherwise keeps hundreds of trails nobody sees.
    private func updateTrails(with result: [Flight]) {
        let cutoff = Date().addingTimeInterval(-15 * 60)
        for f in result where !f.isOnGround && wantsTrail(f.id, at: f.coordinate) {
            let point = TrailPoint(latitude: f.latitude, longitude: f.longitude, altitudeFeet: f.altitudeFeet, time: f.positionTime)
            var trail = trails[f.id] ?? []
            if trail.last?.time != point.time { trail.append(point) }
            if trail.count > 240 { trail.removeFirst(trail.count - 240) }
            trails[f.id] = trail
        }
        // Judged by where the feed has the aircraft now, not where its trail last reached.
        let now = Dictionary(result.map { ($0.id, $0.coordinate) }, uniquingKeysWith: { first, _ in first })
        trails = trails.filter { id, points in
            guard let last = points.last, last.time > cutoff else { return false }
            return wantsTrail(id, at: now[id] ?? last.coordinate)
        }
        trailVersion += 1
    }

    private func wantsTrail(_ id: String, at coordinate: CLLocationCoordinate2D) -> Bool {
        if id == focus.focusedID || isPinned(id) { return true }
        guard let observer else { return false }
        let reach = max(settings.radiusMiles, trailRadiusFloor) * 1.5
        return GeoMath.distanceMiles(from: observer, to: coordinate) <= reach
    }

    // MARK: Ticking

    private func startTicking() {
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.now = Date()
                self.recompute()
            }
        }
    }

    // MARK: Recompute

    private var visibleFlights: [Flight] {
        let ids = Set(flights.map(\.id))
        return (flights + pinnedFlights.filter { !ids.contains($0.id) })
            .filter { !$0.isOnGround && (settings.showHelicopters || profile(for: $0).kind != .helicopter || isPinned($0.id)) }
    }

    func recompute() {
        guard let observer else {
            contacts = []
            outsideContacts = []
            return
        }
        let previousFocus = focusedContact
        let radius = settings.radiusMiles
        let all = visibleFlights
            .map { RadarContact(flight: $0, observer: observer, at: now, profile: profile(for: $0)) }
            .sorted { $0.distanceMiles < $1.distanceMiles }
        let split = all.firstIndex { $0.distanceMiles > radius } ?? all.count
        contacts = Array(all[..<split])
        outsideContacts = Array(all[split...])

        if hasLoadedOnce {
            if isLogging {
                let customName = settings.locationMode == .custom ? settings.customPlaceName : nil
                logbook?.record(contacts, at: now, observer: observer, placeName: customName ?? logPlaceName)
            }
            for alert in alertEngine.evaluate(contacts, rules: settings.alertRules, now: now) {
                if let onAlert { onAlert(alert) } else { post(notice: alert.title, symbol: alert.symbol) }
            }
        }

        var current = focus
        current.isPinned = isPinned(current.focusedID)
        let (resolved, change) = FocusPolicy.resolve(current, inRange: contacts, available: Set(all.map(\.id)))
        setFocus(resolved)

        let name = previousFocus?.flight.displayIdentifier ?? "That aircraft"
        switch change {
        case .leftRange:
            notice = RadarNotice(symbol: "scope", text: "\(name) left your \(Int(radius)) mi radius")
        case .lost:
            notice = RadarNotice(symbol: "antenna.radiowaves.left.and.right.slash", text: "\(name) dropped off radar")
        case .none, .initial:
            break
        }
    }
}

/// Where a worldwide aircraft search (`RadarModel.searchAnywhere`) has got to, for the
/// search screens.
enum FlightSearchState: Equatable {
    case idle, searching, done
    case failed(String)
}

extension Flight {
    /// Search-box matching: flight, callsign, tail number (with or without its hyphen),
    /// type, airline, airports, squawk.
    func matches(search query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        let haystack: [String?] = [
            flightNumber, callsign, registration, registration?.replacingOccurrences(of: "-", with: ""),
            typeCode, typeName, operatorInfo.title, airline?.iata, airlineICAO, airline?.radioCallsign,
            notable.first?.badge, originIATA, destinationIATA, origin?.city, destination?.city, squawk,
        ]
        return haystack.contains { $0?.lowercased().contains(q) == true }
    }
}
