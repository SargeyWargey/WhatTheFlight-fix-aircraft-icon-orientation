//
//  Flight.swift
//  WhatTheFlight
//
//  A single aircraft as reported by the live feed, plus the per-observer "contact"
//  derived from it (distance, bearing, closest approach…).
//

import Foundation
import CoreLocation

enum AircraftKind: String, Codable, Sendable {
    case airplane
    case helicopter
}

struct Flight: Identifiable, Hashable, Sendable {
    let id: String
    var hex: String?
    var latitude: Double
    var longitude: Double
    /// Ground track in degrees true.
    var track: Double
    var altitudeFeet: Int
    var groundSpeedKnots: Int
    var verticalRateFPM: Int
    var squawk: String?
    var typeCode: String?
    var registration: String?
    var originIATA: String?
    var destinationIATA: String?
    var flightNumber: String?
    var callsign: String?
    var airlineICAO: String?
    var isOnGround: Bool
    /// When the position was observed.
    var positionTime: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Flight number → callsign → registration → type.
    var displayIdentifier: String {
        for candidate in [flightNumber, callsign, registration, typeCode] {
            if let value = candidate?.trimmingCharacters(in: .whitespaces), !value.isEmpty {
                return value
            }
        }
        return "UNKNOWN"
    }

    var kind: AircraftKind {
        AircraftTypeCatalog.kind(forTypeCode: typeCode)
    }

    var typeName: String? {
        AircraftTypeCatalog.name(forTypeCode: typeCode)
    }

    var airline: Airline? {
        AirlineCatalog.airline(icao: airlineICAO, callsign: callsign, flightNumber: flightNumber)
    }

    var origin: Airport? { originIATA.flatMap(AirportCatalog.airport(iata:)) }
    var destination: Airport? { destinationIATA.flatMap(AirportCatalog.airport(iata:)) }

    var hasRoute: Bool {
        !(originIATA ?? "").isEmpty && !(destinationIATA ?? "").isEmpty
    }

    /// Climbing / descending / level, using a small dead band so cruise noise reads as level.
    var verticalTrend: VerticalTrend {
        if verticalRateFPM > 200 { return .climbing }
        if verticalRateFPM < -200 { return .descending }
        return .level
    }

    enum VerticalTrend: Sendable { case climbing, level, descending }

    /// Position dead-reckoned to `date`. Extrapolation is capped so a stale fix never
    /// sends an icon flying off on its own.
    func predictedCoordinate(at date: Date, maxExtrapolation: TimeInterval = 90) -> CLLocationCoordinate2D {
        let elapsed = min(max(0, date.timeIntervalSince(positionTime)), maxExtrapolation)
        return GeoMath.extrapolate(coordinate, trackDegrees: track, speedKnots: Double(groundSpeedKnots), seconds: elapsed)
    }
}

/// A flight as seen from the observer at a moment in time.
struct RadarContact: Identifiable, Equatable, Sendable {
    let flight: Flight
    let coordinate: CLLocationCoordinate2D
    let distanceMiles: Double
    /// True bearing from the observer to the aircraft.
    let bearing: Double
    let closestApproach: ClosestApproach

    var id: String { flight.id }

    /// Moving toward the observer (the closest point is still ahead).
    var isApproaching: Bool { closestApproach.isAhead }

    /// `maxExtrapolation` caps dead reckoning; complication timelines project further ahead.
    init(flight: Flight, observer: CLLocationCoordinate2D, at date: Date, maxExtrapolation: TimeInterval = 90) {
        self.flight = flight
        let position = flight.predictedCoordinate(at: date, maxExtrapolation: maxExtrapolation)
        self.coordinate = position
        self.distanceMiles = GeoMath.distanceMiles(from: observer, to: position)
        self.bearing = GeoMath.bearing(from: observer, to: position)
        self.closestApproach = GeoMath.closestApproach(
            observer: observer,
            aircraft: position,
            trackDegrees: flight.track,
            speedKnots: Double(flight.groundSpeedKnots)
        )
    }

    static func == (lhs: RadarContact, rhs: RadarContact) -> Bool {
        lhs.flight == rhs.flight
            && lhs.distanceMiles == rhs.distanceMiles
            && lhs.bearing == rhs.bearing
    }
}

// MARK: - Formatting

enum RadarFormat {
    /// Whole miles, per spec. Anything under half a mile reads "<1".
    static func miles(_ value: Double) -> String {
        value < 0.5 ? "<1" : "\(Int(value.rounded()))"
    }

    static func wholeNumber(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    /// "1:05" style countdown.
    static func countdown(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
