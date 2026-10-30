//
//  LogbookSnapshot+Digest.swift
//  WhatTheFlight
//
//  Builds the widgets' `LogbookSnapshot` from the logbook's digest. Kept apart from the
//  snapshot itself, which the widget extension compiles without the logbook.
//

import Foundation
import CoreLocation

extension LogbookSnapshot {
    /// `observer` picks the sky: where you are, as the Stats tab would open on it.
    init(digest: LogbookDigest, observer: CLLocationCoordinate2D?, calendar: Calendar = .current) {
        let now = digest.builtAt
        let stats = digest.stats
        builtAt = now
        total = stats.total
        airframes = stats.uniqueAirframes
        types = stats.uniqueTypes
        airlines = stats.uniqueAirlines
        countries = digest.countryCount
        notable = stats.notable
        helicopters = stats.helicopters
        photos = digest.photoCount

        let cutoff = calendar.date(byAdding: .day, value: -(Self.recentSpan - 1), to: calendar.startOfDay(for: now)) ?? now
        recentDays = digest.days.filter { $0.day >= cutoff }.reversed().map { DayCount(day: $0.day, count: $0.count) }
        bestDay = digest.busiestDay.map { DayCount(day: $0.day, count: $0.count) }

        // The latest run of days in a row, wherever it ended; the widget decides whether it's
        // still alive on the day it's showing.
        bestStreak = digest.streak.best
        lastDay = digest.days.first?.day
        var run = 0
        var expected = lastDay
        for day in digest.days {
            guard day.day == expected else { break }
            run += 1
            expected = calendar.date(byAdding: .day, value: -1, to: day.day)
        }
        lastRun = run

        let recap = digest.today
        today = recap.isEmpty ? nil : Today(
            day: recap.day,
            notable: recap.notable.count,
            newTypes: recap.newTypes.map { $0.typeName ?? $0.typeCode ?? $0.displayIdentifier },
            newAirlines: recap.newAirlines,
            closest: recap.closest.map { "\($0.closestPreciseText) · \($0.displayIdentifier)" }
        )

        records = digest.records.map { r in
            Record(id: r.id, title: r.title, value: r.value, symbol: r.symbol,
                   flight: [r.sighting.displayIdentifier, r.sighting.typeName].compactMap { $0 }.joined(separator: " · "),
                   date: r.sighting.firstSeen)
        }
        topAirlines = stats.topAirlines.prefix(3).map { Rank(name: $0.name, count: $0.count) }
        topTypes = stats.topTypes.prefix(3).map { Rank(name: $0.name, count: $0.count) }

        badges = digest.achievements.map { a in
            Badge(id: a.id, title: a.title, group: a.group.rawValue, groupTitle: a.group.title, symbol: a.symbol,
                  detail: a.detail, level: a.level, levels: a.tiers.count, fraction: a.fraction,
                  progressText: a.progressText, targetLabel: a.targetLabel, isRecord: a.isRecord,
                  unlockedAt: a.unlockedAt, unlockedBy: a.unlockedBy?.displayIdentifier)
        }
        nextUp = digest.nextUp(6).map(\.id)
        recent = digest.recentlyUnlocked(6).map(\.id)

        let choice = digest.sky(nil, near: observer)
        sky = choice.sky.count == 0 ? nil : Sky(
            place: choice.spot?.name, count: choice.sky.count, hourly: choice.sky.hourly, headings: choice.sky.headings,
            showsTimes: choice.sky.showsTimes, showsHeadings: choice.sky.showsHeadings
        )
    }
}
