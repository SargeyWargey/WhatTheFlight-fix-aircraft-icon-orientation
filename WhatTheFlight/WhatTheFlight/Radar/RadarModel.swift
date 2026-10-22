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

    /// Query at least this far out whatever the radius (Apple Watch's Identify looks 15 mi).
    @ObservationIgnored var queryRadiusFloor: Double = 0
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
        focus = FocusPolicy.nearest(contacts)
    }

    /// Swipe left: step outwards to the next-nearest aircraft.
    func focusNext() {
        focus = FocusPolicy.next(after: focus, inRange: contacts)
    }

    /// Remote ◀: step inwards toward the nearest aircraft.
    func focusPrevious() {
        focus = FocusPolicy.previous(before: focus, inRange: contacts)
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
        let inRange = contacts.contains { $0.id == id }
        focus = RadarFocus(focusedID: id, isPinned: !inRange)
    }

    func togglePin() {
        guard focus.focusedID != nil else { return }
        focus.isPinned.toggle()
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
            consecutiveFailures = 0
            apply(result)
            status = .live
            return settings.refreshSeconds
        } catch is CancellationError {
            return 0
        } catch {
            consecutiveFailures += 1
            status = .error((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            let backoff = settings.refreshSeconds * pow(2, Double(min(consecutiveFailures, 3)))
            let floor = (error as? FeedError) == .rateLimited ? 30.0 : 0
            return min(90, max(floor, backoff))
        }
    }

    private func apply(_ result: [Flight]) {
        flights = result
        lastUpdated = Date()
        updateTrails(with: result)
        hasLoadedOnce = true
        now = Date()
        recompute()
    }

    private func updateTrails(with result: [Flight]) {
        let cutoff = Date().addingTimeInterval(-15 * 60)
        for f in result where !f.isOnGround {
            let point = TrailPoint(latitude: f.latitude, longitude: f.longitude, altitudeFeet: f.altitudeFeet, time: f.positionTime)
            var trail = trails[f.id] ?? []
            if trail.last?.time != point.time { trail.append(point) }
            if trail.count > 240 { trail.removeFirst(trail.count - 240) }
            trails[f.id] = trail
        }
        trails = trails.filter { ($0.value.last?.time ?? .distantPast) > cutoff }
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
        flights.filter { !$0.isOnGround && (settings.showHelicopters || $0.kind != .helicopter) }
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
            .map { RadarContact(flight: $0, observer: observer, at: now) }
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

        let (resolved, change) = FocusPolicy.resolve(focus, inRange: contacts, available: Set(all.map(\.id)))
        if resolved != focus { focus = resolved }

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
