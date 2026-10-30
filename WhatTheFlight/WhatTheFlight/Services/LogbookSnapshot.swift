//
//  LogbookSnapshot.swift
//  WhatTheFlight
//
//  What the logbook shares with the iPhone and iPad widgets (Logbook, Badges, Your Sky)
//  through the App Group: the headline numbers, the last few weeks day by day, the streak,
//  records, every badge and the sky over where you watch. The app builds it from the digest
//  (`Radar/LogbookSnapshot+Digest.swift`) and `LogbookWidgetPublisher` writes it; widgets
//  only read it, so they never load the logbook itself. Days and streaks are kept raw so a
//  widget can still say "0 today" after midnight without the app running.
//

import Foundation

struct LogbookSnapshot: Codable, Equatable, Sendable {
    struct DayCount: Codable, Equatable, Sendable {
        /// Start of the day, in the calendar the app built it with.
        let day: Date
        let count: Int
    }

    struct Record: Codable, Equatable, Identifiable, Sendable {
        let id: String
        let title: String
        /// "0.2 mi", "47,000 ft", already in the units in use.
        let value: String
        let symbol: String
        /// "DL570 · Boeing 757-200".
        let flight: String
        let date: Date
    }

    struct Rank: Codable, Equatable, Sendable {
        let name: String
        let count: Int
    }

    /// One badge, worded as the logbook words it.
    struct Badge: Codable, Equatable, Identifiable, Sendable {
        let id: String
        let title: String
        /// `Achievement.Group`'s raw value, and its title.
        let group: String
        let groupTitle: String
        let symbol: String
        /// What the next level takes ("Log 5,000 aircraft").
        let detail: String
        let level: Int
        let levels: Int
        /// Toward the next level, 1 once maxed.
        let fraction: Double
        /// "1,234 of 5,000", or the badge's own wording ("Highest 47,000 ft").
        let progressText: String
        /// The next level's name ("5,000", "49,000 ft"), or the top one's.
        let targetLabel: String
        let isRecord: Bool
        let unlockedAt: Date?
        /// The aircraft that reached the latest level: "DL570".
        let unlockedBy: String?

        var isUnlocked: Bool { level > 0 }
        var isMaxed: Bool { level == levels }
        var hasLevels: Bool { levels > 1 }
        /// Every level of a levelled badge: drawn with a filled disc and an outer ring.
        var isTopLevel: Bool { hasLevels && isMaxed }
    }

    /// The hour and heading charts for the spot the Stats tab would open on.
    struct Sky: Codable, Equatable, Sendable {
        /// "Atlanta, GA", or nil for every place together.
        let place: String?
        let count: Int
        /// Aircraft first seen in each hour, local time, midnight first.
        let hourly: [Int]
        /// Tracks at the closest pass, 16 sectors, north first.
        let headings: [Int]
        let showsTimes: Bool
        let showsHeadings: Bool

        var busiestHour: Int? {
            guard let peak = hourly.max(), peak > 0 else { return nil }
            return hourly.firstIndex(of: peak)
        }

        var mainSector: Int? {
            guard let peak = headings.max(), peak > 0 else { return nil }
            return headings.firstIndex(of: peak)
        }

        /// The busiest sector's share of every aircraft with a heading.
        var mainShare: Double {
            let total = headings.reduce(0, +)
            return total == 0 ? 0 : Double(headings.max() ?? 0) / Double(total)
        }
    }

    /// Today's highlights when it was built.
    struct Today: Codable, Equatable, Sendable {
        let day: Date
        let notable: Int
        /// Type names logged for the first time.
        let newTypes: [String]
        let newAirlines: [String]
        /// "0.4 mi · DL570".
        let closest: String?
    }

    var builtAt: Date
    var total: Int
    var airframes: Int
    var types: Int
    var airlines: Int
    var countries: Int
    var notable: Int
    var helicopters: Int
    var photos: Int
    /// Days with sightings in the last `recentSpan` days, oldest first.
    var recentDays: [DayCount]
    var bestDay: DayCount?
    var bestStreak: Int
    /// The latest run of days in a row, ending on `lastDay`.
    var lastRun: Int
    var lastDay: Date?
    var today: Today?
    var records: [Record]
    var topAirlines: [Rank]
    var topTypes: [Rank]
    /// Every badge, in the Badges tab's order.
    var badges: [Badge]
    /// Badge ids closest to their next level, nearest first (records never count).
    var nextUp: [String]
    /// Badge ids most recently earned, newest first.
    var recent: [String]
    var sky: Sky?

    static let recentSpan = 35

    // MARK: As of a moment

    /// Aircraft logged on `date`'s day.
    func count(on date: Date, calendar: Calendar = .current) -> Int {
        let day = calendar.startOfDay(for: date)
        return recentDays.first { $0.day == day }?.count ?? 0
    }

    /// The last `count` days up to `date`'s, oldest first, empty days included.
    func days(_ count: Int, endingOn date: Date, calendar: Calendar = .current) -> [DayCount] {
        let today = calendar.startOfDay(for: date)
        let byDay = Dictionary(recentDays.map { ($0.day, $0.count) }, uniquingKeysWith: +)
        return (0..<max(0, count)).reversed().compactMap { back in
            calendar.date(byAdding: .day, value: -back, to: today).map { DayCount(day: $0, count: byDay[$0] ?? 0) }
        }
    }

    /// Days in a row up to `date` (or the day before, if nothing's logged yet that day).
    func streak(at date: Date, calendar: Calendar = .current) -> Int {
        guard let lastDay else { return 0 }
        let today = calendar.startOfDay(for: date)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }
        return lastDay == today || lastDay == yesterday ? lastRun : 0
    }

    /// The streak is alive but nothing's logged yet on `date`'s day: one more keeps it going.
    func streakNeedsToday(at date: Date, calendar: Calendar = .current) -> Bool {
        streak(at: date, calendar: calendar) > 0 && lastDay != calendar.startOfDay(for: date)
    }

    /// Today's highlights, if they're still today's.
    func highlights(at date: Date, calendar: Calendar = .current) -> Today? {
        guard let today, today.day == calendar.startOfDay(for: date) else { return nil }
        return today
    }

    func badge(id: String) -> Badge? { badges.first { $0.id == id } }

    /// The badge a widget follows: the chosen one if it's still there, else the one closest to
    /// its next level, else the first still to earn.
    func featuredBadge(_ id: String?) -> Badge? {
        if let id, let chosen = badge(id: id) { return chosen }
        return nextUpBadges.first ?? badges.first { !$0.isMaxed && !$0.isRecord } ?? badges.first
    }

    var nextUpBadges: [Badge] { nextUp.compactMap(badge(id:)) }
    var recentBadges: [Badge] { recent.compactMap(badge(id:)) }
    var unlockedCount: Int { badges.filter(\.isUnlocked).count }
    var levelsEarned: Int { badges.reduce(0) { $0 + $1.level } }
    var levelsTotal: Int { badges.reduce(0) { $0 + $1.levels } }

    /// Badges by group, in the Badges tab's order.
    var groups: [(id: String, title: String, badges: [Badge])] {
        var order: [String] = []
        var byGroup: [String: [Badge]] = [:]
        for b in badges {
            if byGroup[b.group] == nil { order.append(b.group) }
            byGroup[b.group, default: []].append(b)
        }
        return order.map { id in (id, byGroup[id]?.first?.groupTitle ?? id, byGroup[id] ?? []) }
    }

    /// The same snapshot built at another moment: for telling whether anything changed.
    func built(at date: Date) -> LogbookSnapshot {
        var copy = self
        copy.builtAt = date
        return copy
    }
}

// MARK: - Shared storage

extension SharedRadarStore {
    /// iPhone and iPad widgets that read the logbook.
    static let logbookKind = "LogbookStats"
    static let badgesKind = "LogbookBadges"
    static let skyClockKind = "LogbookSkyClock"
    static let logbookKinds = [logbookKind, badgesKind, skyClockKind]

    var logbook: LogbookSnapshot? {
        get { defaults.data(forKey: "wtf.shared.logbook").flatMap { try? JSONDecoder().decode(LogbookSnapshot.self, from: $0) } }
        nonmutating set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: "wtf.shared.logbook") }
    }
}
