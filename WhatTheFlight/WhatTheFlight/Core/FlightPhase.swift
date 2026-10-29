//
//  FlightPhase.swift
//  WhatTheFlight
//
//  What an aircraft is doing, in a few words, for the line under the hero's type: "On
//  approach to ATL · 12 mi out", "Climbing out of ATL", "Cruising · 2h 05m to DFW",
//  "Descending toward DFW". Worked out from its route, vertical trend, altitude and speed
//  (Enhancements Spec C3). Pure, so it's unit-tested.
//

import Foundation
import CoreLocation

enum FlightPhase: Equatable, Sendable {
    /// Near the destination and coming down.
    case approaching(destination: String, miles: Double)
    /// Just off the origin and going up.
    case departing(origin: String)
    case climbing(toward: String?)
    case descending(toward: String?)
    /// Level, with the time left when it's known.
    case cruising(destination: String?, remaining: TimeInterval?)

    /// Destination this close and descending is an approach…
    static let approachMiles = 40.0
    /// …as is anything this low and this close, whatever its vertical rate (level segments).
    static let lowApproachMiles = 25.0
    static let lowApproachFeet = 10_000
    /// Origin this close and climbing is a departure.
    static let departureMiles = 30.0

    /// Nil on the ground, for a helicopter without a route, and for low level flight
    /// without one (a light aircraft pottering about: nothing worth saying).
    init?(flight: Flight, position: CLLocationCoordinate2D, altitudeFeet: Int, kind: AircraftKind? = nil) {
        guard !flight.isOnGround else { return nil }
        let trend = flight.verticalTrend
        let origin = flight.originIATA.flatMap { $0.isEmpty ? nil : $0 }
        let destination = flight.destinationIATA.flatMap { $0.isEmpty ? nil : $0 }
        let toDestination = flight.destination?.coordinate.map { GeoMath.distanceMiles(from: position, to: $0) }
        let fromOrigin = flight.origin?.coordinate.map { GeoMath.distanceMiles(from: position, to: $0) }

        guard flight.hasRoute, let origin, let destination else {
            if (kind ?? flight.kind) == .helicopter { return nil }
            switch trend {
            case .climbing: self = .climbing(toward: nil)
            case .descending: self = .descending(toward: nil)
            case .level:
                guard altitudeFeet >= Self.lowApproachFeet else { return nil }
                self = .cruising(destination: nil, remaining: nil)
            }
            return
        }

        if let miles = toDestination,
           (miles <= Self.approachMiles && trend == .descending) || (miles <= Self.lowApproachMiles && altitudeFeet < Self.lowApproachFeet && trend != .climbing) {
            self = .approaching(destination: destination, miles: miles)
        } else if let miles = fromOrigin, miles <= Self.departureMiles, trend == .climbing {
            self = .departing(origin: origin)
        } else {
            switch trend {
            case .climbing: self = .climbing(toward: destination)
            case .descending: self = .descending(toward: destination)
            case .level:
                let remaining = RouteProgress(flight: flight, position: position)?.remainingSeconds
                self = .cruising(destination: destination, remaining: remaining)
            }
        }
    }

    /// The hero and detail line.
    var text: String {
        switch self {
        case .approaching(let destination, let miles):
            return miles < 1.5 ? "Landing at \(destination)" : "On approach to \(destination) · \(RadarFormat.distanceText(miles)) out"
        case .departing(let origin): return "Climbing out of \(origin)"
        case .climbing(let toward): return toward.map { "Climbing · bound for \($0)" } ?? "Climbing"
        case .descending(let toward): return toward.map { "Descending toward \($0)" } ?? "Descending"
        case .cruising(let destination, let remaining):
            switch (destination, remaining) {
            case let (.some(d), .some(r)): return "Cruising · \(RouteProgress.duration(r)) to \(d)"
            case let (.some(d), nil): return "Cruising · bound for \(d)"
            default: return "Cruising"
            }
        }
    }

    /// The Watch hero: "Approach ATL", "Departing ATL", "Cruise · 2h 05m".
    var short: String {
        switch self {
        case .approaching(let destination, _): return "Approach \(destination)"
        case .departing(let origin): return "Departing \(origin)"
        case .climbing: return "Climbing"
        case .descending(let toward): return toward.map { "Descent \($0)" } ?? "Descending"
        case .cruising(_, let remaining): return remaining.map { "Cruise · \(RouteProgress.duration($0))" } ?? "Cruising"
        }
    }

    /// For sentences: "on approach to Atlanta", "climbing out of San Francisco".
    func spoken(origin: Airport?, destination: Airport?) -> String {
        func city(_ airport: Airport?, _ code: String) -> String { airport?.city ?? SpokenTraffic.spelled(code) }
        switch self {
        case .approaching(let d, _): return "on approach to \(city(destination, d))"
        case .departing(let o): return "climbing out of \(city(origin, o))"
        case .climbing: return "climbing"
        case .descending(let d): return d.map { "descending toward \(city(destination, $0))" } ?? "descending"
        case .cruising(_, let remaining):
            guard let remaining else { return "cruising" }
            let minutes = Int((remaining / 60).rounded())
            if minutes >= 90 { return "cruising, about \(Int((Double(minutes) / 60).rounded())) hours from landing" }
            return minutes < 2 ? "cruising" : "cruising, about \(minutes) minutes from landing"
        }
    }

    /// Worth a sentence's room: where it's coming from or going to, or how long it has left.
    /// Plain "climbing" or "cruising" isn't.
    var isInformative: Bool {
        switch self {
        case .approaching, .departing: return true
        case .descending(let toward): return toward != nil
        case .cruising(_, let remaining): return remaining != nil
        case .climbing: return false
        }
    }

    var symbol: String {
        switch self {
        case .approaching: return "airplane.arrival"
        case .departing: return "airplane.departure"
        case .climbing: return "arrow.up.right"
        case .descending: return "arrow.down.right"
        case .cruising: return "airplane"
        }
    }
}

extension RadarContact {
    /// What it's doing now, from the dead-reckoned position and altitude.
    var phase: FlightPhase? {
        FlightPhase(flight: flight, position: coordinate, altitudeFeet: altitudeFeet, kind: profile.kind)
    }
}
