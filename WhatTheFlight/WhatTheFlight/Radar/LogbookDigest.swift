//
//  LogbookDigest.swift
//  WhatTheFlight
//
//  Everything the logbook screens show, worked out in one pass whenever the logbook changes
//  (`Logbook.digest` caches it): today, the headline numbers, records, every day and month,
//  what you've seen most (aircraft, airlines, types, routes, airports, countries, places),
//  the sky charts (by hour, weekday, heading, altitude) for everywhere and for each spot you
//  watch from (`LogbookSky.swift`), and streaks. The iPhone, iPad and Apple TV screens only
//  lay it out, so they always agree.
//

import Foundation
import CoreLocation

// MARK: - Sighting helpers

extension Sighting {
    /// Great-circle miles from origin to destination, when both airports are known.
    var routeMiles: Double? {
        guard let a = origin?.coordinate, let b = destination?.coordinate else { return nil }
        return GeoMath.distanceMiles(from: a, to: b)
    }

    /// "ATL-LGA", for grouping by route.
    var routeKey: String? {
        guard let originIATA, let destinationIATA else { return nil }
        return "\(originIATA)-\(destinationIATA)"
    }

    /// ISO country of registration, from the tail number's prefix.
    var registrationCountry: String? { RegistrationCountry.countryCode(forRegistration: registration) }

    var timeInRange: TimeInterval { max(0, lastSeen.timeIntervalSince(firstSeen)) }

    /// "0.2 mi" (one decimal under ten miles) for records and summaries; rows keep the radar's
    /// whole miles.
    var closestPreciseText: String { LogbookFormat.preciseMiles(closestMiles) }
}

enum LogbookFormat {
    static func preciseMiles(_ miles: Double) -> String {
        miles < 10 ? String(format: "%.1f mi", miles) : "\(RadarFormat.wholeNumber(Int(miles.rounded()))) mi"
    }

    /// "6 min", "1 h 05 min", "Under a min".
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 1 { return "Under a min" }
        if minutes < 60 { return "\(minutes) min" }
        return String(format: "%d h %02d min", minutes / 60, minutes % 60)
    }

    /// "7 AM", "12 PM".
    static func hour(_ hour: Int) -> String {
        switch hour % 24 {
        case 0: return "12 AM"
        case 12: return "12 PM"
        case let h where h < 12: return "\(h) AM"
        case let h: return "\(h - 12) PM"
        }
    }

    /// "7–8 AM", "11 AM–12 PM".
    static func hourRange(_ hour: Int) -> String {
        let start = Self.hour(hour), end = Self.hour(hour + 1)
        let sameHalf = (hour % 24 < 12) == ((hour + 1) % 24 < 12) && (hour + 1) % 24 != 12
        return sameHalf ? "\(start.split(separator: " ")[0])–\(end)" : "\(start)–\(end)"
    }

    /// "N", "NNE" … for a 16-point compass sector.
    static let sectorNames = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                              "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]

    /// Eight-way names for "mostly westbound".
    static func direction(_ degrees: Double) -> String {
        ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"][Int(((GeoMath.normalize(degrees) + 22.5) / 45).rounded(.down)) % 8]
    }
}

// MARK: - Pieces

/// One day in the logbook.
struct LogbookDay: Identifiable, Sendable {
    let day: Date
    /// Newest first.
    let sightings: [Sighting]
    let notable: Int
    /// Sightings of a type never logged before (not counted on the logbook's first day).
    let newTypes: Int
    let photos: Int
    /// Where you watched from, in the order you were there.
    let places: [String]

    var id: Date { day }
    var count: Int { sightings.count }

    /// "Atlanta, GA" or "Atlanta, GA + 2 more".
    var placeSummary: String? {
        guard let first = places.first else { return nil }
        return places.count == 1 ? first : "\(first) + \(places.count - 1) more"
    }
}

/// A calendar month of days.
struct LogbookMonth: Identifiable, Sendable {
    let month: Date
    /// Newest first.
    let days: [LogbookDay]

    var id: Date { month }
    var count: Int { days.reduce(0) { $0 + $1.count } }
    var notable: Int { days.reduce(0) { $0 + $1.notable } }
    var newTypes: Int { days.reduce(0) { $0 + $1.newTypes } }
    var photos: Int { days.reduce(0) { $0 + $1.photos } }
    var places: [String] {
        var seen = Set<String>()
        return days.reversed().flatMap(\.places).filter { seen.insert($0).inserted }
    }
}

/// A record and the sighting that holds it.
struct LogbookRecord: Identifiable, Sendable {
    let id: String
    let title: String
    let value: String
    let symbol: String
    let sighting: Sighting
}

/// What you've seen most, ranked.
enum LogbookRanking: String, CaseIterable, Identifiable, Hashable, Sendable {
    case aircraft, airlines, types, routes, airports, countries

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aircraft: return "Aircraft"
        case .airlines: return "Airlines"
        case .types: return "Types"
        case .routes: return "Routes"
        case .airports: return "Airports"
        case .countries: return "Countries"
        }
    }

    var symbol: String {
        switch self {
        case .aircraft: return "airplane"
        case .airlines: return "building.2"
        case .types: return "square.stack.3d.up"
        case .routes: return "point.topleft.down.to.point.bottomright.curvepath"
        case .airports: return "mappin.and.ellipse"
        case .countries: return "flag"
        }
    }

    /// The sightings one entry stands for.
    func filter(for key: String) -> LogbookFilter {
        switch self {
        case .aircraft: return .airframe(key)
        case .airlines: return .airline(key)
        case .types: return .type(key)
        case .routes: return .route(key)
        case .airports: return .airport(key)
        case .countries: return .country(key)
        }
    }
}

/// One ranked entry: an airframe, airline, type, route, airport, country or place.
struct LogbookRank: Identifiable, Hashable, Sendable {
    /// The key: registration, airline name, type code, "ATL-LGA", IATA, ISO country, place.
    let id: String
    let title: String
    let subtitle: String?
    let count: Int
    let lastSeen: Date
    /// The latest sighting, for its silhouette.
    let latest: Sighting
}

/// A subset of the logbook: a quick filter on the Sightings tab, or a ranked entry's sightings.
enum LogbookFilter: Hashable, Sendable {
    case notable, photographed, helicopters, military, newTypes
    case airframe(String), airline(String), type(String), route(String), airport(String), country(String), place(String)

    /// The quick filters, in chip order.
    static let quick: [LogbookFilter] = [.notable, .photographed, .helicopters, .military, .newTypes]

    var title: String {
        switch self {
        case .notable: return "Notable"
        case .photographed: return "Photographed"
        case .helicopters: return "Helicopters"
        case .military: return "Military"
        case .newTypes: return "New types"
        case .airframe(let key): return key
        case .airline(let key): return key
        case .type(let key): return AircraftTypeCatalog.name(forTypeCode: key) ?? key
        case .route(let key): return key.replacingOccurrences(of: "-", with: " → ")
        case .airport(let key): return AirportCatalog.airport(iata: key).map { "\($0.iata) · \($0.city)" } ?? key
        case .country(let key): return RegistrationCountry.countryName(forCode: key)
        case .place(let key): return key
        }
    }

    func matches(_ s: Sighting, firstOfType: Set<String>) -> Bool {
        switch self {
        case .notable: return !s.tags.isEmpty
        case .photographed: return !s.spotPhotos.isEmpty
        case .helicopters: return s.kind == .helicopter
        case .military: return s.tags.contains(.military)
        case .newTypes: return firstOfType.contains(s.id)
        case .airframe(let key): return s.airframe == key
        case .airline(let key): return s.isAirline && s.operatorName == key
        case .type(let key): return s.typeCode == key
        case .route(let key): return s.routeKey == key
        case .airport(let key): return s.originIATA == key || s.destinationIATA == key
        case .country(let key): return s.registrationCountry == key
        case .place(let key): return s.placeName == key
        }
    }
}

struct LogbookStreak: Equatable, Sendable {
    /// Days in a row up to today (or yesterday, if nothing's logged yet today).
    var current = 0
    var best = 0
}

/// The most aircraft in any sixty minutes.
struct LogbookPeak: Sendable {
    let count: Int
    let start: Date
    /// Newest first.
    let sightings: [Sighting]
}

// MARK: - Digest

struct LogbookDigest: Sendable {
    let stats: LogbookStats
    let today: DailyRecap
    let achievements: [Achievement]
    let records: [LogbookRecord]
    /// Every day with a sighting, newest first.
    let days: [LogbookDay]
    let rankings: [LogbookRanking: [LogbookRank]]
    let places: [LogbookRank]
    /// The sky charts, every sighting together.
    let sky: LogbookSky
    /// Where you've watched from, each with its own sky, most sightings first.
    let spots: [LogbookSpot]
    let devices: [(device: LogDevice, count: Int)]
    let streak: LogbookStreak
    let busiestDay: LogbookDay?
    let busiestHour: LogbookPeak?
    /// Sightings that were the first of their type (not counting the logbook's first day).
    let firstOfType: Set<String>
    let photoCount: Int
    let countryCount: Int
    let builtAt: Date

    init(_ sightings: [Sighting], now: Date = Date(), calendar: Calendar = .current) {
        builtAt = now
        stats = LogbookStats(sightings, now: now, calendar: calendar)
        today = DailyRecap(sightings, day: now, calendar: calendar)
        achievements = Achievement.all(for: sightings, calendar: calendar)
        records = Self.records(sightings)

        // Each sighting's day, in one pass.
        var clock = DayClock(calendar)
        let dayOf = sightings.map { clock.day(of: $0.firstSeen) }

        // First of each type, walking oldest first; the first day doesn't count.
        let firstDay = dayOf.first
        var knownTypes = Set<String>()
        var firsts = Set<String>()
        for (i, s) in sightings.enumerated() {
            guard let code = s.typeCode, knownTypes.insert(code).inserted else { continue }
            if dayOf[i] != firstDay { firsts.insert(s.id) }
        }
        firstOfType = firsts

        // Days, newest first.
        var byDay: [Date: [Sighting]] = [:]
        for (i, s) in sightings.enumerated() { byDay[dayOf[i], default: []].append(s) }
        days = byDay.keys.sorted(by: >).map { day in
            let items = byDay[day]!.sorted { $0.firstSeen > $1.firstSeen }
            var seen = Set<String>()
            return LogbookDay(
                day: day, sightings: items,
                notable: items.filter { !$0.tags.isEmpty }.count,
                newTypes: items.filter { firsts.contains($0.id) }.count,
                photos: items.reduce(0) { $0 + $1.spotPhotos.count },
                places: items.reversed().compactMap(\.placeName).filter { seen.insert($0).inserted }
            )
        }
        busiestDay = days.max { ($0.count, $0.day) < ($1.count, $1.day) }

        rankings = Self.rankings(sightings)
        places = Self.rank(sightings, key: \.placeName) { key, _ in (key, nil) }
        countryCount = rankings[.countries]?.count ?? 0
        photoCount = sightings.reduce(0) { $0 + $1.spotPhotos.count }

        sky = LogbookSky(sightings, calendar: calendar)
        spots = LogbookSpot.spots(sightings, calendar: calendar)

        var deviceCounts: [LogDevice: Int] = [:]
        for s in sightings {
            for d in s.loggedOn { deviceCounts[d, default: 0] += 1 }
        }
        devices = deviceCounts.sorted { $0.key < $1.key }.map { (device: $0.key, count: $0.value) }

        streak = LogbookMath.streak(sightings, now: now, calendar: calendar)
        busiestHour = LogbookMath.peakHour(sightings)
    }

    // MARK: Views of the data

    /// The last seven calendar days with sightings, newest first.
    func thisWeek(now: Date = Date(), calendar: Calendar = .current) -> [LogbookDay] {
        let cutoff = Self.weekStart(now: now, calendar: calendar)
        return days.filter { $0.day >= cutoff }
    }

    /// Older days, by month, newest first.
    func earlierMonths(now: Date = Date(), calendar: Calendar = .current) -> [LogbookMonth] {
        let cutoff = Self.weekStart(now: now, calendar: calendar)
        return Self.months(days.filter { $0.day < cutoff }, calendar: calendar)
    }

    /// Every month, newest first.
    func allMonths(calendar: Calendar = .current) -> [LogbookMonth] {
        Self.months(days, calendar: calendar)
    }

    func day(_ date: Date, calendar: Calendar = .current) -> LogbookDay? {
        let start = calendar.startOfDay(for: date)
        return days.first { $0.day == start }
    }

    func month(_ date: Date, calendar: Calendar = .current) -> LogbookMonth? {
        allMonths(calendar: calendar).first { calendar.isDate($0.month, equalTo: date, toGranularity: .month) }
    }

    /// Aircraft per day for the last `count` days, oldest first, empty days included.
    func recentDays(_ count: Int, now: Date = Date(), calendar: Calendar = .current) -> [(day: Date, count: Int)] {
        let today = calendar.startOfDay(for: now)
        let byDay = Dictionary(days.map { ($0.day, $0.count) }, uniquingKeysWith: +)
        return (0..<count).reversed().compactMap { back in
            calendar.date(byAdding: .day, value: -back, to: today).map { ($0, byDay[$0] ?? 0) }
        }
    }

    /// Aircraft per month since the first, oldest first, empty months included.
    func monthlyCounts(calendar: Calendar = .current) -> [(month: Date, count: Int)] {
        let months = allMonths(calendar: calendar)
        guard let first = months.last?.month, let last = months.first?.month else { return [] }
        let byMonth = Dictionary(months.map { ($0.month, $0.count) }, uniquingKeysWith: +)
        var result: [(month: Date, count: Int)] = []
        var m = first
        while m <= last {
            result.append((m, byMonth[m] ?? 0))
            guard let next = calendar.date(byAdding: .month, value: 1, to: m) else { break }
            m = next
        }
        return result
    }

    func sightings(matching filter: LogbookFilter, in all: [Sighting]) -> [Sighting] {
        all.filter { filter.matches($0, firstOfType: firstOfType) }
    }

    /// Locked badges and unfinished levels closest to done, most nearly there first. Records
    /// (highest, fastest, closest) never count: beating one is luck.
    func nextUp(_ limit: Int = 3) -> [Achievement] {
        Array(achievements.filter { !$0.isMaxed && $0.progress > 0 && !$0.isRecord }
            .sorted { ($0.fraction, -$0.remaining) > ($1.fraction, -$1.remaining) }
            .prefix(limit))
    }

    /// Badges (and levels) most recently earned, newest first.
    func recentlyUnlocked(_ limit: Int = 3) -> [Achievement] {
        Array(achievements.filter { $0.unlockedAt != nil }
            .sorted { $0.unlockedAt! > $1.unlockedAt! }
            .prefix(limit))
    }

    var unlockedCount: Int { achievements.filter(\.isUnlocked).count }
    /// Levels still to earn across every badge.
    var levelsToGo: Int { achievements.reduce(0) { $0 + $1.tiers.count - $1.level } }

    /// Where an airframe stands among those seen more than once (1 = seen most).
    func regularRank(airframe: String?) -> Int? {
        guard let airframe, let list = rankings[.aircraft] else { return nil }
        return list.firstIndex { $0.id == airframe }.map { $0 + 1 }
    }

    // MARK: Building

    private static func weekStart(now: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now
    }

    private static func months(_ days: [LogbookDay], calendar: Calendar) -> [LogbookMonth] {
        let byMonth = Dictionary(grouping: days) { calendar.dateInterval(of: .month, for: $0.day)?.start ?? $0.day }
        return byMonth.keys.sorted(by: >).map { LogbookMonth(month: $0, days: byMonth[$0]!.sorted { $0.day > $1.day }) }
    }

    private static func records(_ sightings: [Sighting]) -> [LogbookRecord] {
        var records: [LogbookRecord] = []
        if let s = sightings.min(by: { $0.closestMiles < $1.closestMiles }) {
            records.append(.init(id: "closest", title: "Closest pass", value: s.closestPreciseText, symbol: "scope", sighting: s))
        }
        if let s = sightings.max(by: { $0.altitudeAtClosestFeet < $1.altitudeAtClosestFeet }) {
            records.append(.init(id: "highest", title: "Highest", value: "\(RadarFormat.wholeNumber(s.altitudeAtClosestFeet)) ft", symbol: "arrow.up.to.line", sighting: s))
        }
        if let s = sightings.max(by: { $0.speedKnots < $1.speedKnots }) {
            records.append(.init(id: "fastest", title: "Fastest", value: "\(RadarFormat.wholeNumber(s.speedKnots)) kts", symbol: "gauge.with.dots.needle.100percent", sighting: s))
        }
        if let s = sightings.filter({ $0.isAirline && $0.altitudeAtClosestFeet > 0 }).min(by: { $0.altitudeAtClosestFeet < $1.altitudeAtClosestFeet }) {
            records.append(.init(id: "lowest", title: "Lowest airline flight", value: "\(RadarFormat.wholeNumber(s.altitudeAtClosestFeet)) ft", symbol: "arrow.down.to.line", sighting: s))
        }
        if let s = sightings.max(by: { $0.timeInRange < $1.timeInRange }), s.timeInRange >= 60 {
            records.append(.init(id: "longest", title: "Longest in range", value: LogbookFormat.duration(s.timeInRange), symbol: "clock", sighting: s))
        }
        let routed = sightings.compactMap { s in s.routeMiles.map { (sighting: s, miles: $0) } }
        if let best = routed.max(by: { $0.miles < $1.miles }) {
            records.append(.init(id: "route", title: "Longest route", value: "\(RadarFormat.wholeNumber(Int(best.miles.rounded()))) mi", symbol: "globe.americas", sighting: best.sighting))
        }
        return records
    }

    private static func rankings(_ sightings: [Sighting]) -> [LogbookRanking: [LogbookRank]] {
        var result: [LogbookRanking: [LogbookRank]] = [:]
        // Aircraft: only airframes you've seen more than once.
        result[.aircraft] = rank(sightings, key: \.airframe) { _, latest in
            (latest.registration ?? latest.hex?.uppercased() ?? latest.displayIdentifier,
             [latest.operatorName, latest.typeName ?? latest.typeCode].compactMap { $0 }.joined(separator: " · "))
        }.filter { $0.count > 1 }
        result[.airlines] = rank(sightings, key: { $0.isAirline ? $0.operatorName : nil }) { key, _ in (key, nil) }
        result[.types] = rank(sightings, key: \.typeCode) { key, latest in (latest.typeName ?? key, key) }
        result[.routes] = rank(sightings, key: \.routeKey) { key, latest in
            let cities = [latest.origin?.city, latest.destination?.city]
            return (key.replacingOccurrences(of: "-", with: " → "),
                    cities.allSatisfy { $0 != nil } ? cities.compactMap { $0 }.joined(separator: " → ") : nil)
        }
        // Airports count every time one was the origin or the destination.
        let ends = sightings.flatMap { s in [s.originIATA, s.destinationIATA].compactMap { $0 }.map { ($0, s) } }
        result[.airports] = rankPairs(ends) { key, _ in
            let airport = AirportCatalog.airport(iata: key)
            return (airport.map { "\(key) · \($0.city)" } ?? key, airport?.name)
        }
        result[.countries] = rank(sightings, key: \.registrationCountry) { key, _ in
            (RegistrationCountry.countryName(forCode: key), RegistrationCountry.flag(forCode: key))
        }
        return result
    }

    static func rank(_ sightings: [Sighting], key: (Sighting) -> String?,
                     label: (String, Sighting) -> (title: String, subtitle: String?)) -> [LogbookRank] {
        rankPairs(sightings.compactMap { s in key(s).map { ($0, s) } }, label: label)
    }

    private static func rankPairs(_ pairs: [(String, Sighting)],
                                  label: (String, Sighting) -> (title: String, subtitle: String?)) -> [LogbookRank] {
        var counts: [String: (count: Int, latest: Sighting)] = [:]
        for (key, s) in pairs {
            if let entry = counts[key] {
                counts[key] = (entry.count + 1, s.lastSeen > entry.latest.lastSeen ? s : entry.latest)
            } else {
                counts[key] = (1, s)
            }
        }
        return counts.map { key, entry in
            let text = label(key, entry.latest)
            return LogbookRank(id: key, title: text.title, subtitle: text.subtitle, count: entry.count,
                               lastSeen: entry.latest.lastSeen, latest: entry.latest)
        }
        .sorted { ($0.count, $0.lastSeen) > ($1.count, $1.lastSeen) }
    }
}

// MARK: - Shared maths

/// Day, hour and weekday of many dates, fast. `Calendar` costs microseconds a call, which adds
/// up over a 10,000-sighting logbook; sightings come in time order, so working the calendar
/// out once per day and reusing it is much quicker.
struct DayClock {
    let calendar: Calendar
    private var start = Date.distantFuture
    private var end = Date.distantPast
    private var currentWeekday = 1
    private var isRegular = true

    init(_ calendar: Calendar) { self.calendar = calendar }

    mutating func day(of date: Date) -> Date {
        move(to: date)
        return start
    }

    mutating func hour(of date: Date) -> Int {
        move(to: date)
        // A 23- or 25-hour day (daylight saving changes) asks the calendar.
        return isRegular ? min(23, Int(date.timeIntervalSince(start) / 3_600)) : calendar.component(.hour, from: date)
    }

    /// 1 (Sunday) to 7.
    mutating func weekday(of date: Date) -> Int {
        move(to: date)
        return currentWeekday
    }

    private mutating func move(to date: Date) {
        guard date < start || date >= end else { return }
        start = calendar.startOfDay(for: date)
        end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        currentWeekday = calendar.component(.weekday, from: start)
        isRegular = end.timeIntervalSince(start) == 86_400
    }
}

enum LogbookMath {
    /// Days in a row with at least one sighting: the run up to today (or yesterday) and the
    /// longest ever.
    static func streak(_ sightings: [Sighting], now: Date, calendar: Calendar) -> LogbookStreak {
        let runs = dayRuns(sightings, calendar: calendar)
        var result = LogbookStreak()
        result.best = runs.map(\.length).max() ?? 0
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        if let last = runs.last, last.end == today || last.end == yesterday {
            result.current = last.length
        }
        return result
    }

    /// Runs of consecutive days, oldest first, each with the first sighting of every day in it.
    static func dayRuns(_ sightings: [Sighting], calendar: Calendar) -> [(end: Date, length: Int, firstOfDay: [Sighting])] {
        var firstOfDay: [Date: Sighting] = [:]
        var clock = DayClock(calendar)
        for s in sightings {
            let day = clock.day(of: s.firstSeen)
            if let existing = firstOfDay[day], existing.firstSeen <= s.firstSeen { continue }
            firstOfDay[day] = s
        }
        var runs: [(end: Date, length: Int, firstOfDay: [Sighting])] = []
        for day in firstOfDay.keys.sorted() {
            if let last = runs.last, calendar.date(byAdding: .day, value: 1, to: last.end) == day {
                runs[runs.count - 1] = (day, last.length + 1, last.firstOfDay + [firstOfDay[day]!])
            } else {
                runs.append((day, 1, [firstOfDay[day]!]))
            }
        }
        return runs
    }

    /// For each sighting (oldest first), how many were first seen in the sixty minutes up to
    /// and including it.
    static func hourWindows(_ sorted: [Sighting]) -> [Int] {
        var counts = Array(repeating: 0, count: sorted.count)
        var left = 0
        for right in sorted.indices {
            while sorted[right].firstSeen.timeIntervalSince(sorted[left].firstSeen) >= 3_600 { left += 1 }
            counts[right] = right - left + 1
        }
        return counts
    }

    static func peakHour(_ sightings: [Sighting]) -> LogbookPeak? {
        let sorted = sightings.sorted { $0.firstSeen < $1.firstSeen }
        let windows = hourWindows(sorted)
        guard let best = windows.max(), let end = windows.firstIndex(of: best) else { return nil }
        let range = (end - best + 1)...end
        return LogbookPeak(count: best, start: sorted[range.lowerBound].firstSeen, sightings: sorted[range].reversed())
    }
}

// MARK: - One airframe

extension AirframeSummary {
    /// Visits by hour of the day, midnight first.
    func hourly(calendar: Calendar = .current) -> [Int] {
        var counts = Array(repeating: 0, count: 24)
        for s in history { counts[calendar.component(.hour, from: s.firstSeen)] += 1 }
        return counts
    }

    /// The hour it most often comes by, once it's been seen at least twice.
    func usualHour(calendar: Calendar = .current) -> Int? {
        guard count > 1 else { return nil }
        let counts = hourly(calendar: calendar)
        guard let max = counts.max(), max > 1 else { return nil }
        return counts.firstIndex(of: max)
    }

    /// The routes it flew past you, most often first: "ATL → LGA", the flight number, how often.
    var routes: [(route: String, flight: String, count: Int)] {
        let grouped = Dictionary(grouping: history.filter { $0.routeText != nil }) { $0.routeText! }
        return grouped.map { route, visits in
            (route, visits.first!.displayIdentifier, visits.count)
        }
        .sorted { ($0.count, $0.route) > ($1.count, $1.route) }
    }

    var registrationCountry: String? { latest?.registrationCountry }
}

extension Sighting {
    /// "ATL → LGA".
    var routeText: String? {
        guard let from = originIATA, let to = destinationIATA else { return nil }
        return "\(from) → \(to)"
    }
}
