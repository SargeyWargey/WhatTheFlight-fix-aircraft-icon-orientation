//
//  PollingPolicy.swift
//  WhatTheFlight
//
//  How long the radar waits before asking the feed again. Faster while something is about
//  to pass right overhead (where a stale fix shows most), slower when the sky is empty;
//  otherwise the user's refresh setting.
//

import Foundation

enum PollingPolicy {
    /// Never poll faster than this. Apple Watch passes a higher floor.
    static let fastestSeconds: TimeInterval = 5
    /// The longest wait when nothing at all is around.
    static let emptySkySeconds: TimeInterval = 60

    /// `contacts` are in range, `outside` the rest of the query box (and far-away pins).
    static func interval(base: TimeInterval, contacts: [RadarContact], outside: [RadarContact],
                         floor: TimeInterval = fastestSeconds) -> TimeInterval {
        let interval: TimeInterval
        if contacts.contains(where: isPassingClose) {
            interval = min(base, fastestSeconds)
        } else if contacts.isEmpty && outside.isEmpty {
            interval = min(emptySkySeconds, base * 3)
        } else {
            interval = base
        }
        return max(floor, interval)
    }

    /// Within a mile now, or coming within a mile in the next 90 seconds.
    static func isPassingClose(_ contact: RadarContact) -> Bool {
        if contact.distanceMiles < 1 { return true }
        let cpa = contact.closestApproach
        return cpa.isAhead && cpa.secondsFromNow <= 90 && cpa.distanceMiles < 1
    }
}
