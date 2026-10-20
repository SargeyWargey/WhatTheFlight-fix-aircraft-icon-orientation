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

    init(_ contact: RadarContact) {
        let f = contact.flight
        id = f.id
        identifier = f.displayIdentifier
        operatorName = f.operatorInfo.compact
        route = f.hasRoute ? "\(f.originIATA ?? "") → \(f.destinationIATA ?? "")" : nil
        typeName = f.typeName ?? f.typeCode
        distanceMiles = contact.distanceMiles
        bearing = contact.bearing
        altitudeFeet = f.altitudeFeet
        speedKnots = f.groundSpeedKnots
        isHelicopter = f.kind == .helicopter
        let notable = f.notable.first
        notableBadge = notable?.badge
        notableTag = notable?.tag
        closestPassSeconds = contact.isApproaching ? contact.closestApproach.secondsFromNow : nil
        closestPassMiles = contact.isApproaching ? contact.closestApproach.distanceMiles : nil
        registration = f.registration
        hex = f.hex
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

    var snapshot: RadarSnapshot? {
        get { defaults.data(forKey: Key.snapshot).flatMap { try? JSONDecoder().decode(RadarSnapshot.self, from: $0) } }
        nonmutating set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Key.snapshot) }
    }

    private enum Key {
        static let latitude = "wtf.shared.latitude"
        static let longitude = "wtf.shared.longitude"
        static let placeName = "wtf.shared.placeName"
        static let radius = "wtf.shared.radius"
        static let snapshot = "wtf.shared.snapshot"
    }
}

/// A one-shot fetch for extensions: what's flying around a point right now, nearest first.
enum NearbyTraffic {
    static func contacts(around observer: CLLocationCoordinate2D, radiusMiles: Double,
                         feed: FlightFeed = FlightRadarFeed()) async throws -> [RadarContact] {
        let bounds = GeographicBounds.around(center: observer, radiusMiles: radiusMiles + 3)
        let now = Date()
        return try await feed.flights(in: bounds)
            .filter { !$0.isOnGround }
            .map { RadarContact(flight: $0, observer: observer, at: now) }
            .filter { $0.distanceMiles <= radiusMiles }
            .sorted { $0.distanceMiles < $1.distanceMiles }
    }

    /// Fresh traffic around the shared observer, falling back to the app's last snapshot.
    static func latestSnapshot(store: SharedRadarStore = SharedRadarStore()) async -> RadarSnapshot? {
        guard let observer = store.observer else { return store.snapshot }
        do {
            let contacts = try await contacts(around: observer, radiusMiles: store.radiusMiles)
            return RadarSnapshot(placeName: store.placeName, radiusMiles: store.radiusMiles, contacts: contacts)
        } catch {
            return store.snapshot
        }
    }
}
