//
//  SkyForecast.swift
//  WhatTheFlight
//
//  Where an aircraft will be in your sky over the next few minutes, flying straight on:
//  the dashed path ahead of the locked aircraft in Sky View, and "Rising soon: DL570 from
//  the SW in 2:10" for aircraft still below the trees (Enhancements Spec C7).
//

import Foundation
import CoreLocation

enum SkyForecast {
    struct Point: Equatable, Sendable {
        let seconds: TimeInterval
        let azimuth: Double
        let elevation: Double
    }

    struct Rise: Equatable, Sendable {
        let seconds: TimeInterval
        /// Where to look for it: its compass direction as it clears `visibleElevation`.
        let azimuth: Double
    }

    /// Below this an aircraft is in the trees and roofs.
    static let lowElevation = 3.0
    /// It's "up" once it's this high.
    static let visibleElevation = 5.0

    /// The aircraft in the sky every `step` from `date` for `horizon`, dead-reckoned along its
    /// track (altitude follows the vertical rate for 90 s, as on the radar).
    static func path(of flight: Flight, observer: CLLocationCoordinate2D, from date: Date, horizon: TimeInterval = 600,
                     step: TimeInterval = 20, observerFeet: Double = 0) -> [Point] {
        guard flight.groundSpeedKnots > 20, !flight.isOnGround else { return [] }
        return stride(from: 0, through: horizon, by: step).map { point(of: flight, observer: observer, from: date, after: $0, observerFeet: observerFeet) }
    }

    /// When an aircraft that's low now climbs into view, within `horizon`. Nil if it's
    /// already up, or won't be. Stops at the first sample that clears the trees.
    static func rise(of flight: Flight, observer: CLLocationCoordinate2D, from date: Date, horizon: TimeInterval = 600,
                     step: TimeInterval = 10, observerFeet: Double = 0) -> Rise? {
        guard flight.groundSpeedKnots > 20, !flight.isOnGround,
              point(of: flight, observer: observer, from: date, after: 0, observerFeet: observerFeet).elevation < lowElevation else { return nil }
        for t in stride(from: step, through: horizon, by: step) {
            let p = point(of: flight, observer: observer, from: date, after: t, observerFeet: observerFeet)
            if p.elevation >= visibleElevation { return Rise(seconds: t, azimuth: p.azimuth) }
        }
        return nil
    }

    /// Worth forecasting for "Rising soon": low now, coming closer, and high enough at its
    /// closest pass to clear the trees (it's highest there, flying level). Cheap, so it can
    /// sort through everything in range before `rise` does the work.
    static func mightRise(_ contact: RadarContact, observerFeet: Double = 0, horizon: TimeInterval = 600) -> Bool {
        guard contact.isApproaching, contact.distanceMiles < 60 else { return false }
        let now = GeoMath.elevationDegrees(groundDistanceMiles: contact.distanceMiles, altitudeFeet: Double(contact.altitudeFeet),
                                           observerAltitudeFeet: observerFeet)
        guard now < lowElevation else { return false }
        // Not past its closest pass within the horizon: judge it where the horizon ends.
        let cpa = contact.closestApproach
        let miles = cpa.secondsFromNow <= horizon
            ? cpa.distanceMiles
            : max(cpa.distanceMiles, contact.distanceMiles - Double(contact.flight.groundSpeedKnots) * 1.15078 * horizon / 3600)
        let best = GeoMath.elevationDegrees(groundDistanceMiles: miles, altitudeFeet: Double(contact.altitudeFeet) + 3_000,
                                            observerAltitudeFeet: observerFeet)
        return best >= visibleElevation
    }

    private static func point(of flight: Flight, observer: CLLocationCoordinate2D, from date: Date, after t: TimeInterval,
                              observerFeet: Double) -> Point {
        let base = max(0, date.timeIntervalSince(flight.positionTime))
        let at = date.addingTimeInterval(t)
        let position = flight.predictedCoordinate(at: at, maxExtrapolation: base + t)
        let miles = GeoMath.distanceMiles(from: observer, to: position)
        let elevation = GeoMath.elevationDegrees(groundDistanceMiles: miles, altitudeFeet: Double(flight.predictedAltitudeFeet(at: at)),
                                                 observerAltitudeFeet: observerFeet)
        return Point(seconds: t, azimuth: GeoMath.bearing(from: observer, to: position), elevation: elevation)
    }
}
