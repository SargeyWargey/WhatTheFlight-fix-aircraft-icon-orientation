//
//  PollingPolicy.swift
//  WhatTheFlight
//
//  How long the radar waits before asking the feed again. Positions are dead-reckoned in
//  between, so a poll only corrects drift, and the same drift is a few degrees of bearing at
//  20 mi but a quarter turn at 1 mi: the wait grows with the distance to the nearest aircraft.
//

import Foundation

enum PollingPolicy {
    /// Never poll faster than this. Apple Watch passes a higher floor.
    static let fastestSeconds: TimeInterval = 5
    /// Within this distance it's always the fastest.
    static let overheadMiles: Double = 1
    /// Beyond that, each mile to the nearest aircraft adds this much to the wait.
    static let secondsPerMile: TimeInterval = 1
    /// The longest wait while anything at all is around (20 mi or more away).
    static let farthestSeconds: TimeInterval = 25
    /// The wait when the feed reported nothing: short enough to catch an aircraft entering
    /// the query box before it reaches the radius.
    static let emptySkySeconds: TimeInterval = 30
    /// A closer pass counts if it comes within this long.
    static let lookaheadSeconds: TimeInterval = 90
    /// Low Power Mode stretches every wait by this much, and never polls faster than
    /// `lowPowerFloor`.
    static let lowPowerStretch: Double = 1.5
    static let lowPowerFloor: TimeInterval = 10

    /// `contacts` are in range, `outside` the rest of the query box (and far-away pins).
    /// `fastest` (Sky View, the Watch's Identify and Find) puts labels on real aircraft, so
    /// it polls at the floor whatever the distance, Low Power Mode or not.
    static func interval(contacts: [RadarContact], outside: [RadarContact], floor: TimeInterval = fastestSeconds,
                         fastest: Bool = false, lowPower: Bool = false) -> TimeInterval {
        if fastest { return floor }
        var interval: TimeInterval
        if let nearest = (contacts + outside).map(closestSoon).min() {
            interval = nearest <= overheadMiles
                ? fastestSeconds
                : min(farthestSeconds, fastestSeconds + nearest * secondsPerMile)
        } else {
            interval = emptySkySeconds
        }
        if lowPower { interval = max(lowPowerFloor, interval * lowPowerStretch) }
        return max(floor, interval)
    }

    /// The closest the aircraft is now or comes within the next 90 s, in miles.
    static func closestSoon(_ contact: RadarContact) -> Double {
        let cpa = contact.closestApproach
        guard cpa.isAhead, cpa.secondsFromNow <= lookaheadSeconds else { return contact.distanceMiles }
        return min(contact.distanceMiles, cpa.distanceMiles)
    }
}
