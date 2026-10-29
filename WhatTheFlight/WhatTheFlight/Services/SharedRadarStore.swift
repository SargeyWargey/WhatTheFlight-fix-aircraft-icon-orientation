//
//  SharedRadarStore.swift
//  WhatTheFlight
//
//  What the app shares with its widgets, Siri and the Apple TV Top Shelf through the App
//  Group: where the radar is watching from, and a snapshot of the traffic it last saw.
//  `NearbyTraffic` lets those extensions fetch fresh traffic on their own.
//

import Foundation
import CoreLocation

/// One aircraft as the widgets show it.
struct SnapshotFlight: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let identifier: String
    let operatorName: String
    let route: String?
    let typeName: String?
    let distanceMiles: Double
    let bearing: Double
    let altitudeFeet: Int
    let speedKnots: Int
    let isHelicopter: Bool
    let notableBadge: String?
    let notableTag: NotableTag?
    /// Seconds from `RadarSnapshot.date` to the closest pass, when still approaching.
    let closestPassSeconds: TimeInterval?
    let closestPassMiles: Double?
    /// For photo lookups (Top Shelf).
    var registration: String?
    var hex: String?
    /// For the Watch complications' little radar: the silhouette, nose along its track.
    /// Snapshots saved before these existed decode without them.
    var track: Double?
    var silhouette: AircraftSilhouette?

    init(_ contact: RadarContact) {
        let f = contact.flight
        let profile = contact.profile
        id = f.id
        identifier = f.displayIdentifier
        operatorName = profile.operatorInfo.compact
        route = f.hasRoute ? "\(f.originIATA ?? "") → \(f.destinationIATA ?? "")" : nil
        typeName = profile.typeName ?? f.typeCode
        distanceMiles = contact.distanceMiles
        bearing = contact.bearing
        altitudeFeet = contact.altitudeFeet
        speedKnots = f.groundSpeedKnots
        isHelicopter = profile.kind == .helicopter
        let notable = profile.notable.first
        notableBadge = notable?.badge
        notableTag = notable?.tag
        closestPassSeconds = contact.isApproaching ? contact.closestApproach.secondsFromNow : nil
        closestPassMiles = contact.isApproaching ? contact.closestApproach.distanceMiles : nil
        registration = f.registration
        hex = f.hex
        track = f.track
        silhouette = profile.silhouette
    }
}

struct RadarSnapshot: Codable, Equatable, Sendable {
    let date: Date
    let placeName: String?
    let radiusMiles: Double
    let inRangeCount: Int
    /// Nearest first, at most a handful.
    let flights: [SnapshotFlight]

    init(date: Date = Date(), placeName: String?, radiusMiles: Double, contacts: [RadarContact], limit: Int = 6) {
        self.date = date
        self.placeName = placeName
        self.radiusMiles = radiusMiles
        inRangeCount = contacts.count
        flights = contacts.prefix(limit).map(SnapshotFlight.init)
    }
}

struct SharedRadarStore {
    static let appGroup = "group.SargeyWargey.WhatTheFlight"
    static let widgetKind = "NearestFlight"
    /// iPhone's Next Overhead widget.
    static let nextOverheadKind = "NextOverhead"

    let defaults: UserDefaults

    init(defaults: UserDefaults? = UserDefaults(suiteName: SharedRadarStore.appGroup)) {
        self.defaults = defaults ?? .standard
    }

    var observer: CLLocationCoordinate2D? {
        get {
            guard defaults.object(forKey: Key.latitude) != nil else { return nil }
            return CLLocationCoordinate2D(latitude: defaults.double(forKey: Key.latitude), longitude: defaults.double(forKey: Key.longitude))
        }
        nonmutating set {
            if let newValue {
                defaults.set(newValue.latitude, forKey: Key.latitude)
                defaults.set(newValue.longitude, forKey: Key.longitude)
            } else {
                defaults.removeObject(forKey: Key.latitude)
                defaults.removeObject(forKey: Key.longitude)
            }
        }
    }

    var placeName: String? {
        get { defaults.string(forKey: Key.placeName) }
        nonmutating set { defaults.set(newValue, forKey: Key.placeName) }
    }

    var radiusMiles: Double {
        get { defaults.object(forKey: Key.radius) == nil ? 20 : defaults.double(forKey: Key.radius) }
        nonmutating set { defaults.set(newValue, forKey: Key.radius) }
    }

    /// What counts as overhead: the overhead alert's distance, so the Watch's Next Overhead
    /// complication counts down to the passes an alert would announce.
    var overheadMiles: Double {
        get { defaults.object(forKey: Key.overheadMiles) == nil ? 1.5 : defaults.double(forKey: Key.overheadMiles) }
        nonmutating set { defaults.set(newValue, forKey: Key.overheadMiles) }
    }

    /// The app's data source choice, so widgets, Siri and Top Shelf fetch the same way.
    var dataSource: DataSourcePreference {
        get { defaults.string(forKey: Key.dataSource).flatMap(DataSourcePreference.init(rawValue:)) ?? .automatic }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.dataSource) }
    }

    /// A feed for an extension's one-shot fetch: layered, following the app's choice.
    var feed: FlightFeed { LayeredFeed(preference: dataSource) }

    var snapshot: RadarSnapshot? {
        get { defaults.data(forKey: Key.snapshot).flatMap { try? JSONDecoder().decode(RadarSnapshot.self, from: $0) } }
        nonmutating set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Key.snapshot) }
    }

    private enum Key {
        static let latitude = "wtf.shared.latitude"
        static let longitude = "wtf.shared.longitude"
        static let placeName = "wtf.shared.placeName"
        static let radius = "wtf.shared.radius"
        static let overheadMiles = "wtf.shared.overheadMiles"
        static let snapshot = "wtf.shared.snapshot"
        static let dataSource = "wtf.shared.dataSource"
    }
}

/// An aircraft that will pass within the overhead distance: what the Next Overhead
/// complication counts down to.
struct SkyPass: Equatable, Sendable {
    /// The aircraft where it is at the moment shown (where to look now).
    let flight: SnapshotFlight
    /// When it passes closest.
    let date: Date
    /// How close it comes.
    let miles: Double

    /// Further ahead than this, a straight-line guess isn't worth a countdown.
    static let maxLead: TimeInterval = 10 * 60
    /// How long a pass stays "overhead now" after its closest point.
    static let linger: TimeInterval = 60
    /// The countdown ring drains over the last five minutes.
    static let ringWindow: TimeInterval = 5 * 60
}

/// What the complications show at one moment: the traffic dead-reckoned to `date`, the next
/// close pass, and one going over right now.
struct SkyMoment: Equatable, Sendable {
    let snapshot: RadarSnapshot
    var nextPass: SkyPass?
    /// At or just past its closest point, for `SkyPass.linger`.
    var passing: SkyPass?

    var date: Date { snapshot.date }

    init(snapshot: RadarSnapshot, nextPass: SkyPass? = nil, passing: SkyPass? = nil) {
        self.snapshot = snapshot
        self.nextPass = nextPass
        self.passing = passing
    }

    /// From a snapshot the app saved: only its handful of flights to go on, so the pass is
    /// the soonest close one among them.
    init(snapshot: RadarSnapshot, overheadMiles: Double) {
        let pass = snapshot.flights
            .compactMap { f -> SkyPass? in
                guard let seconds = f.closestPassSeconds, let miles = f.closestPassMiles,
                      miles <= overheadMiles, seconds <= SkyPass.maxLead else { return nil }
                return SkyPass(flight: f, date: snapshot.date.addingTimeInterval(seconds), miles: miles)
            }
            .min { $0.date < $1.date }
        self.init(snapshot: snapshot, nextPass: pass)
    }
}

/// A one-shot fetch for extensions: what's flying around a point right now, nearest first.
enum NearbyTraffic {
    static func contacts(around observer: CLLocationCoordinate2D, radiusMiles: Double,
                         feed: FlightFeed = SharedRadarStore().feed) async throws -> [RadarContact] {
        let flights = try await flights(around: observer, radiusMiles: radiusMiles, feed: feed)
        return contacts(flights, observer: observer, radiusMiles: radiusMiles, at: Date())
    }

    /// Airborne flights in a box a little wider than the radius, so aircraft about to enter
    /// it are known too (complication timelines project them forward).
    static func flights(around observer: CLLocationCoordinate2D, radiusMiles: Double,
                        feed: FlightFeed = SharedRadarStore().feed) async throws -> [Flight] {
        let bounds = GeographicBounds.around(center: observer, radiusMiles: radiusMiles + 3)
        return try await feed.flights(in: bounds).filter { !$0.isOnGround }
    }

    /// In-range contacts at `date`, nearest first, dead-reckoned up to `maxExtrapolation`.
    static func contacts(_ flights: [Flight], observer: CLLocationCoordinate2D, radiusMiles: Double,
                         at date: Date, maxExtrapolation: TimeInterval = 90,
                         profiles: [String: FlightProfile] = [:]) -> [RadarContact] {
        flights
            .map { RadarContact(flight: $0, observer: observer, at: date, maxExtrapolation: maxExtrapolation, profile: profiles[$0.id]) }
            .filter { $0.distanceMiles <= radiusMiles }
            .sorted { $0.distanceMiles < $1.distanceMiles }
    }

    /// One snapshot per `step` for `count` steps from `start`, each aircraft dead-reckoned
    /// along its track. Complications can only reload a few times an hour, so a timeline of
    /// these keeps them moving in between. Beyond a few minutes turns make this guesswork,
    /// so callers keep the horizon short.
    static func projectedSnapshots(_ flights: [Flight], observer: CLLocationCoordinate2D, radiusMiles: Double,
                                   placeName: String?, start: Date, count: Int, step: TimeInterval) -> [RadarSnapshot] {
        // The same aircraft at every step: work out who they are once.
        let profiles = Dictionary(flights.map { ($0.id, FlightProfile($0)) }, uniquingKeysWith: { first, _ in first })
        return (0..<max(0, count)).map { i in
            let date = start.addingTimeInterval(Double(i) * step)
            let horizon = date.timeIntervalSince(start) + 90
            let inRange = contacts(flights, observer: observer, radiusMiles: radiusMiles, at: date, maxExtrapolation: horizon,
                                   profiles: profiles)
            return RadarSnapshot(date: date, placeName: placeName, radiusMiles: radiusMiles, contacts: inRange)
        }
    }

    /// The Watch complications' timeline: a moment every `step` for `count` steps from
    /// `start`, plus one at each close pass and one as it clears, so "overhead now" shows up
    /// on time rather than at the next whole step. Passes come from every flight fetched,
    /// not only those in range, and snapshots keep `limit` aircraft for the little radar.
    static func timeline(_ flights: [Flight], observer: CLLocationCoordinate2D, radiusMiles: Double,
                         overheadMiles: Double, placeName: String?, start: Date, count: Int, step: TimeInterval,
                         limit: Int = 12) -> [SkyMoment] {
        guard count > 0 else { return [] }
        let profiles = Dictionary(flights.map { ($0.id, FlightProfile($0)) }, uniquingKeysWith: { first, _ in first })
        func contact(_ flight: Flight, at date: Date) -> RadarContact {
            RadarContact(flight: flight, observer: observer, at: date,
                         maxExtrapolation: date.timeIntervalSince(start) + 90, profile: profiles[flight.id])
        }
        // Dead reckoning flies a straight line, so each pass happens at one fixed time.
        let passes: [(flight: Flight, date: Date, miles: Double)] = flights.compactMap { flight in
            let approach = contact(flight, at: start).closestApproach
            guard approach.isAhead, approach.distanceMiles <= overheadMiles else { return nil }
            return (flight, start.addingTimeInterval(approach.secondsFromNow), approach.distanceMiles)
        }
        let end = start.addingTimeInterval(Double(count - 1) * step)
        var dates = (0..<count).map { start.addingTimeInterval(Double($0) * step) }
        for pass in passes {
            dates += [pass.date, pass.date.addingTimeInterval(SkyPass.linger)].filter { $0 <= end }
        }
        dates.sort()
        // A pass a moment after a step would only add an entry nobody sees.
        dates = dates.reduce(into: []) { kept, date in
            if let last = kept.last, date.timeIntervalSince(last) < 1 { return }
            kept.append(date)
        }
        return dates.map { date in
            let all = flights.map { contact($0, at: date) }
            let inRange = all.filter { $0.distanceMiles <= radiusMiles }.sorted { $0.distanceMiles < $1.distanceMiles }
            let snapshot = RadarSnapshot(date: date, placeName: placeName, radiusMiles: radiusMiles,
                                         contacts: inRange, limit: limit)
            func skyPass(_ pass: (flight: Flight, date: Date, miles: Double)) -> SkyPass {
                SkyPass(flight: SnapshotFlight(contact(pass.flight, at: date)), date: pass.date, miles: pass.miles)
            }
            let next = passes
                .filter { $0.date > date && $0.date.timeIntervalSince(date) <= SkyPass.maxLead }
                .min { $0.date < $1.date }
            let passing = passes
                .filter { $0.date <= date && date.timeIntervalSince($0.date) < SkyPass.linger }
                .min { $0.miles < $1.miles }
            return SkyMoment(snapshot: snapshot, nextPass: next.map(skyPass), passing: passing.map(skyPass))
        }
    }

    /// Fresh traffic around the shared observer, falling back to the app's last snapshot.
    static func latestSnapshot(store: SharedRadarStore = SharedRadarStore()) async -> RadarSnapshot? {
        guard let observer = store.observer else { return store.snapshot }
        do {
            let contacts = try await contacts(around: observer, radiusMiles: store.radiusMiles)
            return RadarSnapshot(placeName: store.placeName, radiusMiles: store.radiusMiles, contacts: contacts)
        } catch {
            Log.feed.info("Couldn't fetch traffic, using the app's last snapshot: \(error.localizedDescription, privacy: .public)")
            return store.snapshot
        }
    }
}
