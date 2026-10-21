//
//  Whereabouts.swift
//  WhatTheFlight
//
//  "Where is it now?" for an aircraft that has left the radius: what it's doing, how far
//  from you, and whether it's still on the flight you saw. Built from one worldwide feed
//  lookup (`FlightRadarFeed.locate`).
//

import Foundation
import CoreLocation

struct Whereabouts: Equatable, Sendable {
    let flight: Flight
    /// Dead-reckoned to when it was asked for.
    let coordinate: CLLocationCoordinate2D
    let distanceMiles: Double?
    let bearing: Double?
    /// On the ground: the airport it's sitting at, when one is close by.
    let airport: Airport?
    /// The leg you saw (or are looking at). `nil` skips the "still on…" comparison.
    let seenFlightID: String?

    init(flight: Flight, observer: CLLocationCoordinate2D?, seenFlightID: String? = nil, at date: Date = Date()) {
        self.flight = flight
        self.seenFlightID = seenFlightID
        let position = flight.isOnGround ? flight.coordinate : flight.predictedCoordinate(at: date)
        coordinate = position
        distanceMiles = observer.map { GeoMath.distanceMiles(from: $0, to: position) }
        bearing = observer.map { GeoMath.bearing(from: $0, to: position) }
        airport = flight.isOnGround ? AirportCatalog.nearest(to: position, withinMiles: 5) : nil
    }

    static func == (lhs: Whereabouts, rhs: Whereabouts) -> Bool {
        lhs.flight == rhs.flight && lhs.distanceMiles == rhs.distanceMiles
    }

    /// Still flying the leg you saw, rather than a later one.
    var isSameFlight: Bool { seenFlightID == flight.id }

    /// "In the air", "On the ground at ATL".
    var headline: String {
        guard flight.isOnGround else { return "In the air" }
        guard let airport else { return "On the ground" }
        return "On the ground at \(airport.iata)"
    }

    /// "Still on DL1199 · ATL → ORD", "Now flying DL3161 · ATL → DFW", or the airport's name
    /// when it's parked.
    var detail: String? {
        if flight.isOnGround, let airport { return "\(airport.name) · \(airport.city)" }
        let route = flight.hasRoute ? " · \(flight.originIATA ?? "") → \(flight.destinationIATA ?? "")" : ""
        guard seenFlightID != nil else { return flight.hasRoute ? String(route.dropFirst(3)) : nil }
        return "\(isSameFlight ? "Still on" : "Now flying") \(flight.displayIdentifier)\(route)"
    }

    /// "1,240 mi NE of you".
    var distanceText: String? {
        guard let distanceMiles, let bearing else { return nil }
        if distanceMiles < 0.5 { return "Right above you" }
        return "\(RadarFormat.wholeNumber(Int(distanceMiles.rounded()))) mi \(GeoMath.cardinal(bearing)) of you"
    }

    static let notFoundText = "Not on Flightradar24 right now. It's probably parked with its transponder off, or flying somewhere without coverage."
}
