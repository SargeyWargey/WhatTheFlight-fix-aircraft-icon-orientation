//
//  RouteProgress.swift
//  WhatTheFlight
//
//  How far along its route a flight is: miles flown, miles to go and time to go at the
//  current ground speed, measured along great circles via the aircraft's position.
//

import Foundation
import CoreLocation

struct RouteProgress: Equatable, Sendable {
    let origin: Airport
    let destination: Airport
    let flownMiles: Double
    let remainingMiles: Double
    /// At the current ground speed. Nil while climbing out slowly (it would wildly overstate
    /// the time left), unless the flight is nearly there.
    let remainingSeconds: TimeInterval?

    var fraction: Double { flownMiles / max(1, flownMiles + remainingMiles) }

    init?(flight: Flight, position: CLLocationCoordinate2D) {
        guard let origin = flight.origin, let destination = flight.destination,
              let from = origin.coordinate, let to = destination.coordinate else { return nil }
        self.origin = origin
        self.destination = destination
        flownMiles = GeoMath.distanceMiles(from: from, to: position)
        remainingMiles = GeoMath.distanceMiles(from: position, to: to)
        let mph = Double(flight.groundSpeedKnots) * GeoMath.milesPerKnotHour
        let representative = flight.groundSpeedKnots >= 250 || remainingMiles < 60
        remainingSeconds = mph > 30 && representative ? remainingMiles / mph * 3600 : nil
    }

    /// "1h 05m" / "12m".
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int((seconds / 60).rounded()))
        return minutes >= 60 ? "\(minutes / 60)h \(String(format: "%02d", minutes % 60))m" : "\(minutes)m"
    }
}
