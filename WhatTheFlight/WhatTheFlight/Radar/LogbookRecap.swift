//
//  LogbookRecap.swift
//  WhatTheFlight
//
//  "Your 2026 in the sky" and "October in the sky": a month or a year of the logbook as a
//  handful of headline numbers, favourites, records and firsts, plus what the cards' charts
//  draw (aircraft per day, the hours and headings, the mix of kinds, the top fives), for the
//  recap cards on the Overview tab and their shareable pictures.
//

import Foundation

struct LogbookRecap: Identifiable, Sendable {
    enum Period: Hashable, Sendable {
        case month(year: Int, month: Int)
        case year(Int)

        /// "October 2026", "2026".
        func title(calendar: Calendar = .current) -> String {
            switch self {
            case .year(let y): return String(y)
            case .month(let y, let m):
                let date = calendar.date(from: DateComponents(year: y, month: m, day: 1)) ?? Date()
                return date.formatted(.dateTime.month(.wide).year())
            }
        }

        /// "October", "2026": how the card names it.
        func shortTitle(calendar: Calendar = .current) -> String {
            switch self {
            case .year(let y): return String(y)
            case .month(let y, let m):
                let date = calendar.date(from: DateComponents(year: y, month: m, day: 1)) ?? Date()
                return date.formatted(.dateTime.month(.wide))
            }
        }

        func interval(calendar: Calendar = .current) -> DateInterval? {
            switch self {
            case .year(let y):
                guard let start = calendar.date(from: DateComponents(year: y, month: 1, day: 1)) else { return nil }
                return calendar.dateInterval(of: .year, for: start)
            case .month(let y, let m):
                guard let start = calendar.date(from: DateComponents(year: y, month: m, day: 1)) else { return nil }
                return calendar.dateInterval(of: .month, for: start)
            }
        }

        var isYear: Bool { if case .year = self { return true } else { return false } }
    }

    struct Favorite: Sendable {
        let title: String
        let subtitle: String?
        let count: Int
        let example: Sighting
    }

    /// A badge, or a level of one, reached in the period.
    struct Badge: Sendable {
        let title: String
        let symbol: String
        /// The level reached, and how many the badge has (1 and 1 for a badge without levels).
        let level: Int
        let levels: Int

        /// "Plane Spotter · level 2".
        var text: String { level > 1 ? "\(title) · level \(level)" : title }
    }

    /// How many aircraft of one kind (airline, cargo, helicopter…).
    struct KindCount: Sendable {
        let kind: FlightKind
        let count: Int
    }

    let period: Period
    var id: Period { period }
    let total: Int
    let daysWatched: Int
    let airframes: Int
    let airlines: Int
    let types: Int
    /// Countries of registration.
    let countries: Int
    let notable: Int
    let photos: Int
    /// The five most seen, busiest first, for the ranking bars. The single favourites
    /// below only count once something was seen twice.
    let airlineRanking: [Favorite]
    let typeRanking: [Favorite]
    var topAirline: Favorite? { airlineRanking.first.flatMap { $0.count >= 2 ? $0 : nil } }
    var topType: Favorite? { typeRanking.first.flatMap { $0.count >= 2 ? $0 : nil } }
    let topAircraft: Favorite?
    let topRoute: Favorite?
    let busiestDay: (day: Date, count: Int)?
    /// Aircraft on each day of the period, its first day first; days still to come are zero.
    let perDay: [Int]
    /// How many of `perDay` have begun: the rest are still to come.
    let daysSoFar: Int
    /// Blank cells before the first day in a calendar laid out from the calendar's first
    /// weekday (0 when the period starts on it).
    let leadingBlanks: Int
    /// The period's hours (each sighting in its own time zone), headings and altitude-speed
    /// scatter.
    let sky: LogbookSky
    /// Aircraft of each kind, in `FlightKind.allCases` order, kinds never seen left out.
    let kinds: [KindCount]
    let closest: Sighting?
    let highest: Sighting?
    let fastest: Sighting?
    let longest: (sighting: Sighting, miles: Double)?
    /// The first of a type ever, logged in this period, oldest first.
    let newTypes: [Sighting]
    /// Badges and badge levels reached in the period.
    let badges: [Badge]

    /// `sightings` oldest first, as `Logbook.sightings` keeps them. Nil when nothing was
    /// logged in the period.
    init?(_ sightings: [Sighting], period: Period, calendar: Calendar = .current, now: Date = Date(), includeBadges: Bool = true) {
        guard let interval = period.interval(calendar: calendar) else { return nil }
        let before = sightings.prefix { $0.firstSeen < interval.start }
        let within = Self.sightings(sightings, in: interval)
        guard !within.isEmpty else { return nil }
        self.period = period
        total = within.count

        var clock = DayClock(calendar)
        var perDay: [Date: Int] = [:]
        for s in within { perDay[clock.day(of: s.firstSeen), default: 0] += 1 }
        daysWatched = perDay.count
        busiestDay = perDay.max { ($0.value, $1.key) < ($1.value, $0.key) }.map { ($0.key, $0.value) }
        // Calendar maths once per day watched (at most 366), not per sighting.
        func dayIndex(_ day: Date) -> Int { calendar.dateComponents([.day], from: interval.start, to: day).day ?? 0 }
        let length = max(1, dayIndex(interval.end))
        var days = Array(repeating: 0, count: length)
        for (day, count) in perDay {
            let i = dayIndex(day)
            if days.indices.contains(i) { days[i] += count }
        }
        self.perDay = days
        daysSoFar = min(length, max(0, dayIndex(calendar.startOfDay(for: now)) + 1))
        leadingBlanks = (calendar.component(.weekday, from: interval.start) - calendar.firstWeekday + 7) % 7
        sky = LogbookSky(within, calendar: calendar)

        airframes = Set(within.compactMap(\.airframe)).count
        airlines = Set(within.filter(\.isAirline).map(\.operatorName)).count
        types = Set(within.compactMap(\.typeCode)).count
        countries = Set(within.compactMap(\.registrationCountry)).count
        notable = within.filter { !$0.tags.isEmpty }.count
        photos = within.reduce(0) { $0 + $1.spotPhotos.count }

        var operatorKinds: [String: FlightKind] = [:]
        var kindCounts: [FlightKind: Int] = [:]
        for s in within {
            let operatorKind = operatorKinds[s.operatorName] ?? FlightKind.classify(operatorName: s.operatorName)
            operatorKinds[s.operatorName] = operatorKind
            kindCounts[FlightKind.resolve(operatorKind, tags: s.tags, isHelicopter: s.kind == .helicopter), default: 0] += 1
        }
        kinds = FlightKind.allCases.compactMap { kind in kindCounts[kind].map { KindCount(kind: kind, count: $0) } }

        func ranking(_ key: (Sighting) -> String?, title: (String, Sighting) -> String, subtitle: (Sighting) -> String? = { _ in nil },
                     limit: Int) -> [Favorite] {
            var counts: [String: (count: Int, latest: Sighting)] = [:]
            for s in within {
                guard let k = key(s) else { continue }
                counts[k] = ((counts[k]?.count ?? 0) + 1, s)
            }
            return counts.sorted { ($0.value.count, $1.key) > ($1.value.count, $0.key) }.prefix(limit).map { best in
                Favorite(title: title(best.key, best.value.latest), subtitle: subtitle(best.value.latest),
                         count: best.value.count, example: best.value.latest)
            }
        }
        func top(_ key: (Sighting) -> String?, title: (String, Sighting) -> String, subtitle: (Sighting) -> String? = { _ in nil }) -> Favorite? {
            ranking(key, title: title, subtitle: subtitle, limit: 1).first.flatMap { $0.count >= 2 ? $0 : nil }
        }
        airlineRanking = ranking({ $0.isAirline ? $0.operatorName : nil }, title: { name, _ in name }, limit: 5)
        typeRanking = ranking(\.typeCode, title: { code, s in s.typeName ?? code }, subtitle: { $0.typeCode }, limit: 5)
        topAircraft = top(\.airframe, title: { reg, _ in reg }, subtitle: { [$0.typeName ?? $0.typeCode, $0.operatorName].compactMap { $0 }.joined(separator: " · ") })
        topRoute = top({ s in s.routeText }, title: { route, _ in route })

        closest = within.min { $0.closestMiles < $1.closestMiles }
        highest = within.max { $0.altitudeAtClosestFeet < $1.altitudeAtClosestFeet }
        fastest = within.max { $0.speedKnots < $1.speedKnots }
        longest = within.compactMap { s in s.routeMiles.map { (sighting: s, miles: $0) } }.max { $0.miles < $1.miles }

        var knownTypes = Set(before.compactMap(\.typeCode))
        var firsts: [Sighting] = []
        for s in within {
            guard let code = s.typeCode, knownTypes.insert(code).inserted else { continue }
            firsts.append(s)
        }
        // A brand-new logbook's every type is a first; that's not news.
        newTypes = before.isEmpty ? [] : firsts

        if includeBadges {
            let earnedBefore = Set(Achievement.all(for: Array(before), calendar: calendar).flatMap { a in a.tiers.prefix(a.level).map { "\(a.id)@\($0)" } })
            let through = Array(before) + within
            badges = Achievement.all(for: through, calendar: calendar).compactMap { a in
                let new = a.tiers.prefix(a.level).filter { !earnedBefore.contains("\(a.id)@\($0)") }
                guard !new.isEmpty else { return nil }
                return Badge(title: a.title, symbol: a.symbol, level: a.level, levels: max(1, a.tiers.count))
            }
        } else {
            badges = []
        }
    }

    /// The mix as `cells` squares of a waffle chart, in `kinds` order: each kind gets its
    /// share rounded by largest remainder, and any kind seen at all gets at least one square.
    func mixCells(_ cells: Int = 100) -> [FlightKind] { Self.waffle(kinds, cells: cells) }

    /// `mixCells` for any counts.
    static func waffle(_ kinds: [KindCount], cells: Int = 100) -> [FlightKind] {
        let total = kinds.reduce(0) { $0 + $1.count }
        guard total > 0 else { return [] }
        let exact = kinds.map { Double($0.count) * Double(cells) / Double(total) }
        var shares = exact.map { max(1, Int($0)) }
        let byRemainder = exact.indices.sorted { exact[$0] - exact[$0].rounded(.down) > exact[$1] - exact[$1].rounded(.down) }
        for i in byRemainder where shares.reduce(0, +) < cells { shares[i] += 1 }
        // The one-square minimum can overspend: take it back from the biggest.
        while shares.reduce(0, +) > cells, let i = shares.indices.max(by: { shares[$0] < shares[$1] }) { shares[i] -= 1 }
        return zip(kinds, shares).flatMap { Array(repeating: $0.kind, count: $1) }
    }

    /// How many aircraft a period holds, without the rest of the recap: what the way in shows.
    static func total(_ sightings: [Sighting], period: Period, calendar: Calendar = .current) -> Int {
        period.interval(calendar: calendar).map { Self.sightings(sightings, in: $0).count } ?? 0
    }

    private static func sightings(_ sightings: [Sighting], in interval: DateInterval) -> [Sighting] {
        sightings.filter { interval.contains($0.firstSeen) && $0.firstSeen < interval.end }
    }

    /// The recaps worth offering now: this year so far (once it spans more than a month, or
    /// all of last year in January), this month so far and last month.
    static func periods(now: Date = Date(), calendar: Calendar = .current) -> [Period] {
        let y = calendar.component(.year, from: now), m = calendar.component(.month, from: now)
        let lastMonth = m == 1 ? Period.month(year: y - 1, month: 12) : Period.month(year: y, month: m - 1)
        var result: [Period] = []
        if m == 1 { result.append(.year(y - 1)) } else { result.append(.year(y)) }
        result.append(.month(year: y, month: m))
        result.append(lastMonth)
        return result
    }
}
