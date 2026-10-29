//
//  LogbookAchievements.swift
//  WhatTheFlight
//
//  Badges, worked out from the sightings every time the logbook changes. Nothing is stored,
//  so regrouping them or changing levels never loses one. One-off badges unlock once; most
//  have levels (Plane Spotter at 100 / 1,000 / 10,000 / 100,000 / 1,000,000), and the top
//  level is meant to be hard: a lot of calendar time, travel, or luck, not just a radar left
//  running. Grouped as Milestones, Rare Birds, Moments, Collections and Sky View.
//

import Foundation
import CoreLocation

struct Achievement: Identifiable, Equatable, Sendable {
    enum Group: String, CaseIterable, Sendable {
        case milestones, rareBirds, moments, collections, skyView

        var title: String {
            switch self {
            case .milestones: return String(localized: "Milestones")
            case .rareBirds: return String(localized: "Rare Birds")
            case .moments: return String(localized: "Moments")
            case .collections: return String(localized: "Collections")
            case .skyView: return String(localized: "Sky View")
            }
        }
    }

    let id: String
    let title: String
    let group: Group
    /// What the next level takes ("Log 5,000 aircraft"); once maxed, what the top one took.
    let detail: String
    /// A little more about it, for the badge's own page.
    let about: String
    let symbol: String
    /// How far along: aircraft, photos, days in a row, helicopters, the highest altitude…
    let progress: Int
    /// What each level takes, lowest first. One entry for a one-off badge.
    let tiers: [Int]
    /// The sighting that reached the latest level.
    let unlockedBy: Sighting?
    /// When the latest level was reached.
    let unlockedAt: Date?
    /// The most recent qualifying sightings, newest first. For the "different airlines /
    /// types" badges, one per airline or type.
    let examples: [Sighting]
    /// What each level is called when it isn't a plain count ("45,000 ft", "¼ mi").
    var tierLabels: [String]? = nil
    /// Where it stands, when that reads better than "3 of 5" ("Highest 47,000 ft").
    var progressLabel: String? = nil
    /// Progress is a best-ever value (highest, fastest, closest), not a tally. The ring shows
    /// levels earned rather than distance to the next, and it's never "next up": beating a
    /// record is luck, not something you work toward.
    var isRecord = false

    /// Levels earned.
    var level: Int { tiers.filter { progress >= $0 }.count }
    var isUnlocked: Bool { level > 0 }
    var isMaxed: Bool { level == tiers.count }
    var hasLevels: Bool { tiers.count > 1 }
    /// The next level's target, or the top one once maxed.
    var target: Int { isMaxed ? (tiers.last ?? 1) : tiers[level] }
    var remaining: Int { max(0, target - progress) }
    /// Toward the next level (1 once maxed).
    var fraction: Double {
        if isMaxed { return 1 }
        if isRecord { return Double(level) / Double(tiers.count) }
        return min(1, Double(progress) / Double(max(target, 1)))
    }

    /// The next level's name ("49,000 ft", "1,000"), or the top one's once maxed.
    var targetLabel: String { tierLabels?[min(level, tiers.count - 1)] ?? RadarFormat.wholeNumber(target) }
    /// "1,234 of 5,000", or the badge's own wording.
    var progressText: String {
        progressLabel ?? "\(RadarFormat.wholeNumber(min(progress, target))) of \(RadarFormat.wholeNumber(target))"
    }

    /// "Level 2 of 3".
    var levelText: String? { hasLevels ? "Level \(level) of \(tiers.count)" : nil }

    /// The radar's notice when it's just been earned: "Badge unlocked: Mayday",
    /// "Plane Spotter · level 3".
    var unlockNotice: String {
        hasLevels && level > 1 ? "\(title) · level \(level)" : "Badge unlocked: \(title)"
    }

    static let exampleLimit = 30

    // Aircraft types some badges look for (ICAO type designators).
    static let jumboTypes: Set<String> = ["B741", "B742", "B743", "B744", "B748", "B74S", "BLCF", "VC25"]
    /// The five giant freighters, each family counted once.
    static let giantFamilies: [String: String] = [
        "A124": "An-124", "A225": "An-124", "C5": "C-5", "C5M": "C-5", "C17": "C-17",
        "A3ST": "Beluga", "A337": "Beluga", "BLCF": "Dreamlifter",
    ]
    static let bomberTypes: Set<String> = ["B52", "B1", "B2"]
    static let tiltrotorTypes: Set<String> = ["V22"]
    /// Second World War aircraft still flying.
    static let warbirdTypes: Set<String> = [
        "DC3", "B17", "B24", "B25", "B29", "P38", "P40", "P47", "P51", "SPIT", "HURI", "CORS", "T6", "JU52", "A26", "C46",
    ]
    /// What makes a photo a Rare Shot, besides a notable tag.
    static let rareTypes: Set<String> = jumboTypes.union(["A388"]).union(giantFamilies.keys).union(bomberTypes)
        .union(tiltrotorTypes).union(warbirdTypes)

    /// `sightings` oldest first, as `Logbook.sightings` keeps them.
    static func all(for sightings: [Sighting], calendar: Calendar = .current) -> [Achievement] {
        func matching(_ predicate: (Sighting) -> Bool) -> [Sighting] { sightings.filter(predicate) }
        func type(_ codes: Set<String>) -> [Sighting] { matching { codes.contains($0.typeCode ?? "") } }
        /// The first sighting of each distinct key, in the order they were first seen.
        func distinct(_ key: (Sighting) -> String?) -> [Sighting] {
            var seen = Set<String>()
            return sightings.filter { s in
                guard let k = key(s) else { return false }
                return seen.insert(k).inserted
            }
        }
        /// Like `distinct`, for sightings that can bring in more than one key (both ends of a
        /// route): one entry per new key, so a sighting can appear twice.
        func distinctMany(_ keys: (Sighting) -> [String]) -> [Sighting] {
            var seen = Set<String>()
            var result: [Sighting] = []
            for s in sightings {
                for k in keys(s) where seen.insert(k).inserted { result.append(s) }
            }
            return result
        }
        /// Newest first, each sighting once, at most `exampleLimit`.
        func newest(_ list: [Sighting]) -> [Sighting] {
            var ids = Set<String>()
            var result: [Sighting] = []
            for s in list.reversed() where ids.insert(s.id).inserted {
                result.append(s)
                if result.count == exampleLimit { break }
            }
            return result
        }
        func number(_ n: Int) -> String { RadarFormat.wholeNumber(n) }
        // Badge levels stay in miles, feet and knots; only their wording follows the units.
        func distance(_ miles: Int) -> String { RadarFormat.wholeDistance(Double(miles)) }
        let metric = Units.isMetric
        let aMile = metric ? "1.6 km" : "a mile"

        /// A badge counted by qualifying sightings: level n unlocks with the tiers[n]-th one.
        func make(_ id: String, _ title: String, _ group: Group, _ symbol: String, tiers: [Int] = [1],
                  _ qualifying: [Sighting], examples: [Sighting]? = nil,
                  detail: (Int) -> String, about: String) -> Achievement {
            custom(id, title, group, symbol, tiers: tiers, progress: qualifying.count,
                   reached: { qualifying[$0 - 1] }, examples: examples ?? newest(qualifying),
                   detail: detail, about: about)
        }

        /// Any badge: `reached(target)` is the sighting that first got progress to `target`.
        func custom(_ id: String, _ title: String, _ group: Group, _ symbol: String, tiers: [Int] = [1],
                    tierLabels: [String]? = nil, progress: Int, progressLabel: String? = nil, isRecord: Bool = false,
                    reached: (Int) -> Sighting?, reachedAt: ((Int) -> Date?)? = nil,
                    examples: [Sighting], detail: (Int) -> String, about: String) -> Achievement {
            let level = tiers.filter { progress >= $0 }.count
            let target = level == tiers.count ? (tiers.last ?? 1) : tiers[level]
            let top = level > 0 ? tiers[level - 1] : nil
            let by = top.flatMap(reached)
            return Achievement(id: id, title: title, group: group, detail: detail(target), about: about, symbol: symbol,
                               progress: progress, tiers: tiers, unlockedBy: by,
                               unlockedAt: top.flatMap { reachedAt?($0) } ?? by?.firstSeen,
                               examples: examples, tierLabels: tierLabels, progressLabel: progressLabel, isRecord: isRecord)
        }

        /// A best-ever badge: progress is the highest `value` so far ("Highest 47,000 ft"), and
        /// each level is reached by the first sighting to get there.
        func best(_ id: String, _ title: String, _ group: Group, _ symbol: String, tiers: [Int], format: (Int) -> String, word: String,
                  value: (Sighting) -> Int?, detail: (Int) -> String, about: String) -> Achievement {
            let values = sightings.map(value)
            let top = values.compactMap { $0 }.max() ?? 0
            return custom(id, title, group, symbol, tiers: tiers, tierLabels: tiers.map(format),
                          progress: top, progressLabel: top > 0 ? "\(word) \(format(top))" : nil, isRecord: true,
                          reached: { target in sightings.indices.first { (values[$0] ?? 0) >= target }.map { sightings[$0] } },
                          examples: newest(sightings.indices.filter { (values[$0] ?? 0) >= tiers[0] }.map { sightings[$0] }),
                          detail: detail, about: about)
        }

        // Calendar: each sighting's day and hour, then days, months and hours of the clock.
        var clock = DayClock(calendar)
        var dayOf: [Date] = []
        var hourOf: [Int] = []
        dayOf.reserveCapacity(sightings.count)
        hourOf.reserveCapacity(sightings.count)
        for s in sightings {
            dayOf.append(clock.day(of: s.firstSeen))
            hourOf.append(clock.hour(of: s.firstSeen))
        }
        var daysSeen = Set<Date>(), dayFirsts: [Sighting] = []
        var monthOfDay: [Date: Int] = [:], monthsSeen = Set<Int>(), monthFirsts: [Sighting] = []
        var hoursSeen = Set<Int>(), hourFirsts: [Sighting] = []
        var hoursByDay: [Date: Set<Int>] = [:], bestDayHours = 0, fullDay: Sighting?
        for (i, s) in sightings.enumerated() {
            let day = dayOf[i], hour = hourOf[i]
            if daysSeen.insert(day).inserted { dayFirsts.append(s) }
            let month = monthOfDay[day] ?? calendar.component(.month, from: day)
            monthOfDay[day] = month
            if monthsSeen.insert(month).inserted { monthFirsts.append(s) }
            if hoursSeen.insert(hour).inserted { hourFirsts.append(s) }
            hoursByDay[day, default: []].insert(hour)
            let hoursToday = hoursByDay[day]?.count ?? 0
            bestDayHours = max(bestDayHours, hoursToday)
            if hoursToday == 24, fullDay == nil { fullDay = s }
        }
        /// Sightings first seen in these hours of the day.
        func hours(_ range: Range<Int>) -> [Sighting] { sightings.indices.filter { range.contains(hourOf[$0]) }.map { sightings[$0] } }
        /// The first sighting in these hours on each day: one per night or morning.
        func firstPerDay(hours range: Range<Int>) -> [Sighting] {
            var days = Set<Date>()
            return sightings.indices.filter { range.contains(hourOf[$0]) && days.insert(dayOf[$0]).inserted }.map { sightings[$0] }
        }
        let newYear = sightings.indices.filter { i in
            hourOf[i] == 0 && monthOfDay[dayOf[i]] == 1 && calendar.component(.day, from: dayOf[i]) == 1
        }.map { sightings[$0] }

        // Days in a row: progress is the longest run.
        let runs = LogbookMath.dayRuns(sightings, calendar: calendar)
        let bestRun = runs.max { $0.length < $1.length }
        let streak = custom(
            "streak", "On a Roll", .milestones, "flame.fill", tiers: [7, 30, 100, 365],
            progress: bestRun?.length ?? 0,
            reached: { target in runs.first { $0.length >= target }?.firstOfDay[target - 1] },
            examples: Array((bestRun?.firstOfDay ?? []).suffix(exampleLimit).reversed()),
            detail: { "Spot something \($0) days in a row" },
            about: "One aircraft a day keeps the streak alive. Leave the radar running on an Apple TV or an iPad and the days add up; the top level takes a whole year without a blank day.")

        let roundTheClock = custom(
            "roundclock", "Round the Clock", .moments, "clock.fill", tiers: [12, 18, 24, 48],
            tierLabels: ["12 hours", "18 hours", "All 24", "24 in a day"],
            progress: hoursSeen.count < 24 ? hoursSeen.count : 24 + bestDayHours,
            progressLabel: hoursSeen.count < 24 ? "\(hoursSeen.count) of 24 hours" : "Best day \(bestDayHours) of 24 hours",
            reached: { $0 <= 24 ? hourFirsts[$0 - 1] : fullDay },
            examples: Array(hourFirsts.reversed()),
            detail: { $0 <= 24 ? "Log aircraft in \($0) different hours of the day" : "Log an aircraft in every hour of a single day" },
            about: "Each hour of the clock counts once, on any day. The last level needs all 24 in one day: the radar running overnight, and traffic even at 3 am, when most hubs go quiet.")

        // Where you watch from: your usual spot is the busiest 7-mile square.
        func square(_ c: CLLocationCoordinate2D, perDegree: Double) -> Int {
            (Int((c.latitude * perDegree).rounded()) + Int(90 * perDegree)) * 1_000_000 + Int((c.longitude * perDegree).rounded()) + Int(180 * perDegree)
        }
        var squares: [Int: (count: Int, latitude: Double, longitude: Double)] = [:]
        for s in sightings {
            guard let c = s.observerCoordinate else { continue }
            let entry = squares[square(c, perDegree: 10)] ?? (0, 0, 0)
            squares[square(c, perDegree: 10)] = (entry.count + 1, entry.latitude + c.latitude, entry.longitude + c.longitude)
        }
        func center(_ e: (count: Int, latitude: Double, longitude: Double)) -> CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: e.latitude / Double(e.count), longitude: e.longitude / Double(e.count))
        }
        let home = squares.max { ($0.value.count, $1.key) < ($1.value.count, $0.key) }.map { center($0.value) }
        let milesFromHome = home.map { home in squares.mapValues { Int(GeoMath.distanceMiles(from: home, to: center($0))) } } ?? [:]
        let farFromHome = best(
            "farfromhome", "Far From Home", .milestones, "suitcase.fill", tiers: [100, 1_000, 5_000], format: distance, word: "Farthest",
            value: { s in s.observerCoordinate.flatMap { milesFromHome[square($0, perDegree: 10)] } },
            detail: { "Log aircraft \(RadarFormat.spokenDistance(Double($0))) from your usual spot" },
            about: "Measured from where you log the most aircraft. Take your iPhone on holiday: the radar works wherever you are, and everything you see goes in the same logbook.")

        // Airports you've watched beside: each place you watched from, about 0.7 mi across,
        // looked up once.
        var airportAtSpot: [Int: String?] = [:]
        var fenceAirports = Set<String>(), fenceFirsts: [Sighting] = []
        for s in sightings {
            guard let c = s.observerCoordinate else { continue }
            let key = square(c, perDegree: 100)
            let iata: String?
            if let known = airportAtSpot[key] {
                iata = known
            } else {
                iata = AirportCatalog.nearest(to: c, withinMiles: 2)?.iata
                airportAtSpot[key] = iata
            }
            if let iata, fenceAirports.insert(iata).inserted { fenceFirsts.append(s) }
        }

        // Photos: counted by photo, filed under their sightings.
        // Sky View's own photos; ones added from the camera roll don't count.
        let photos = sightings.flatMap { s in s.spotPhotos.filter { !$0.isFromLibrary }.map { (sighting: s, photo: $0) } }
            .sorted { $0.photo.takenAt < $1.photo.takenAt }
        func photoBadge(_ id: String, _ title: String, _ symbol: String, tiers: [Int], _ shots: [(sighting: Sighting, photo: SpotPhoto)],
                        detail: (Int) -> String, about: String) -> Achievement {
            custom(id, title, .skyView, symbol, tiers: tiers, progress: shots.count,
                   reached: { shots[$0 - 1].sighting }, reachedAt: { shots[$0 - 1].photo.takenAt },
                   examples: newest(shots.map(\.sighting)), detail: detail, about: about)
        }
        var photoTypes = Set<String>()
        let typeShots = photos.filter { $0.photo.typeCode.map { photoTypes.insert($0).inserted } ?? false }

        // Devices: an iPhone, an iPad and an Apple TV.
        let kinds: Set<LogDevice> = [.iPhone, .iPad, .appleTV]
        var seenKinds = Set<LogDevice>()
        var firstPerKind: [Sighting] = []
        for s in sightings {
            let new = Set(s.loggedOn).intersection(kinds).subtracting(seenKinds)
            guard !new.isEmpty else { continue }
            seenKinds.formUnion(new)
            firstPerKind.append(s)
        }
        let fullHouse = custom(
            "fullhouse", "Full House", .milestones, "rectangle.on.rectangle", tiers: [3],
            progress: seenKinds.count,
            reached: { _ in seenKinds.count >= 3 ? firstPerKind.last : nil },
            examples: firstPerKind.reversed(),
            detail: { _ in "Log aircraft on an iPhone, an iPad and an Apple TV" },
            about: "The logbook syncs through iCloud, so every device you watch from adds to the same book.")

        // Busiest hour, close in: the most first seen within sixty minutes, of the aircraft
        // that passed within 5 miles (so a wider radius doesn't make it easier).
        let near = sightings.filter { $0.closestMiles <= 5 }.sorted { $0.firstSeen < $1.firstSeen }
        let windows = LogbookMath.hourWindows(near)
        let peak = LogbookMath.peakHour(near)
        let busy = custom(
            "busy", "Busy Sky", .moments, "chart.bar.fill", tiers: [25, 50, 100],
            progress: windows.max() ?? 0,
            reached: { target in windows.firstIndex { $0 >= target }.map { near[$0] } },
            examples: peak?.sightings ?? [],
            detail: { "Log \($0) aircraft within \(RadarFormat.spokenDistance(5)) in one hour" },
            about: "Rush hour in the sky. Only aircraft that pass within \(RadarFormat.spokenDistance(5)) count, so a bigger radar radius doesn't help: you need to be under a hub's approach at its busiest.")

        // The same airframe: again and again, and back after a long time away.
        var visits: [String: [Sighting]] = [:]
        var firstToReach: [Int: Sighting] = [:]
        var firstVisit: [String: Date] = [:]
        var longestAway = 0
        var firstAway: [Int: Sighting] = [:]
        var returns: [String: Sighting] = [:]
        let awayTiers = [30, 180, 365]
        for s in sightings {
            guard let airframe = s.airframe else { continue }
            visits[airframe, default: []].append(s)
            let n = visits[airframe]!.count
            if firstToReach[n] == nil { firstToReach[n] = s }
            guard let first = firstVisit[airframe] else {
                firstVisit[airframe] = s.firstSeen
                continue
            }
            let days = Int(s.firstSeen.timeIntervalSince(first) / 86_400)
            longestAway = max(longestAway, days)
            for t in awayTiers where days >= t && firstAway[t] == nil { firstAway[t] = s }
            if days >= awayTiers[0] { returns[airframe] = s }
        }
        let regular = visits.values.max { ($0.count, $0.last!.firstSeen) < ($1.count, $1.last!.firstSeen) } ?? []
        let regularBadge = custom(
            "regular", "Regular", .moments, "arrow.triangle.2.circlepath", tiers: [10, 25, 50, 100, 250],
            progress: regular.count,
            reached: { firstToReach[$0] },
            examples: Array(regular.suffix(exampleLimit).reversed()),
            detail: { "See the same aircraft \($0) times" },
            about: "Airlines fly the same airframes on the same routes day after day. Listed here: every visit from the aircraft you've seen most.")
        let awayWords = [30: "30 days", 180: "six months", 365: "a year"]
        let oldFriend = custom(
            "oldfriend", "Old Friend", .moments, "hand.wave.fill", tiers: awayTiers,
            tierLabels: ["30 days", "6 months", "1 year"],
            progress: longestAway, progressLabel: longestAway > 0 ? "Back after \(number(longestAway)) days" : nil,
            reached: { firstAway[$0] },
            examples: Array(returns.values.sorted { $0.firstSeen > $1.firstSeen }.prefix(exampleLimit)),
            detail: { "See an aircraft again \(awayWords[$0] ?? "\($0) days") after you first logged it" },
            about: "The same airframe, by its registration, coming back long after you first saw it. Listed here: each returning aircraft's latest visit.")

        // The same airline flight number on many days.
        var flightDays: [String: (days: Int, last: Date)] = [:]
        var mostDays = 0, mostDaysFlight: String?
        var firstToDays: [Int: Sighting] = [:]
        for (i, s) in sightings.enumerated() where s.isAirline {
            guard let callsign = s.callsign, !callsign.isEmpty else { continue }
            let entry = flightDays[callsign] ?? (0, .distantPast)
            guard entry.last != dayOf[i] else { continue }
            flightDays[callsign] = (entry.days + 1, dayOf[i])
            if firstToDays[entry.days + 1] == nil { firstToDays[entry.days + 1] = s }
            if entry.days + 1 > mostDays {
                mostDays = entry.days + 1
                mostDaysFlight = callsign
            }
        }
        var clockworkDays = Set<Date>()
        let clockworkExamples = sightings.indices.reversed()
            .filter { sightings[$0].isAirline && sightings[$0].callsign == mostDaysFlight && clockworkDays.insert(dayOf[$0]).inserted }
            .prefix(exampleLimit).map { sightings[$0] }
        let clockwork = custom(
            "clockwork", "Clockwork", .moments, "clock.arrow.circlepath", tiers: [7, 30, 100],
            progress: mostDays,
            reached: { firstToDays[$0] },
            examples: clockworkExamples,
            detail: { "See the same flight number on \($0) different days" },
            about: "Airline flight numbers run to a timetable: the same DAL1234 at the same time most days. Only airline flights count. Listed here: each day you saw the flight you've seen most.")

        // Out and back: the same airframe flying A → B, then B → A, on the same day.
        var routesFlown: [String: Set<String>] = [:]
        var boomerangs: [Sighting] = []
        for (i, s) in sightings.enumerated() {
            guard let airframe = s.airframe, let from = s.originIATA, let to = s.destinationIATA, from != to else { continue }
            let key = "\(airframe)|\(dayOf[i].timeIntervalSinceReferenceDate)"
            if routesFlown[key]?.contains("\(to)>\(from)") == true { boomerangs.append(s) }
            routesFlown[key, default: []].insert("\(from)>\(to)")
        }

        // Right overhead: levels for ever-closer passes.
        let passes: [(miles: Double, label: String, words: String)] = metric
            ? [0.5, 0.25, 0.1, 0.05].map { miles in
                let label = RadarFormat.shortDistance(miles)
                return (miles, label, label.replacingOccurrences(of: " m", with: " meters"))
            }
            : [
                (0.5, "½ mi", "half a mile"), (0.25, "¼ mi", "a quarter of a mile"),
                (0.1, "0.1 mi", "0.1 mi (about 530 ft)"), (0.05, "0.05 mi", "0.05 mi (about 260 ft)"),
            ]
        let closest = sightings.map(\.closestMiles).min()
        let overhead = custom(
            "overhead", "Right Overhead", .moments, "scope", tiers: [1, 2, 3, 4], tierLabels: passes.map(\.label),
            progress: closest.map { c in passes.filter { c < $0.miles }.count } ?? 0,
            progressLabel: closest.map { "Closest \(metric ? RadarFormat.shortDistance($0) : String(format: "%.2f mi", $0))" }, isRecord: true,
            reached: { level in sightings.first { $0.closestMiles < passes[level - 1].miles } },
            examples: newest(matching { $0.closestMiles < 0.5 }),
            detail: { "Have an aircraft pass within \(passes[$0 - 1].words)" },
            about: "Measured from where you were watching to the closest point of the aircraft's track. The last levels mean living right under an approach path, or a helicopter passing straight over.")

        let silhouettes = AircraftSilhouette.allCases.count
        let airlineInitial: (Sighting) -> String? = { s in
            // The ICAO code that starts an airline flight number: DAL in DAL1234.
            guard s.isAirline, let c = s.callsign, c.count > 3, c.dropFirst(3).first?.isNumber == true else { return nil }
            let code = c.prefix(3)
            guard code.allSatisfy({ ("A"..."Z").contains($0) }) else { return nil }
            return String(code.prefix(1))
        }
        let isTestFlight: (Sighting) -> Bool = { s in
            // Boeing's and Airbus's own test and delivery callsigns: BOE1, AIB01.
            guard let c = s.callsign, c.count > 3, c.dropFirst(3).first?.isNumber == true else { return false }
            return c.hasPrefix("BOE") || c.hasPrefix("AIB")
        }
        var compassSeen = Set<Int>()
        let compassFirsts = sightings.filter { s in
            guard s.closestMiles <= 1, let track = s.trackAtClosest else { return false }
            let degrees = (track.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
            return compassSeen.insert(Int(degrees / 10)).inserted
        }

        return [
            // Milestones
            make("first", "First Contact", .milestones, "airplane", sightings,
                 detail: { _ in "Log your first aircraft" },
                 about: "Every logbook starts somewhere. Any aircraft that comes inside your radius counts."),
            make("spotter", "Plane Spotter", .milestones, "binoculars.fill", tiers: [100, 1_000, 10_000, 100_000, 1_000_000], sightings,
                 detail: { "Log \(number($0)) aircraft" },
                 about: "Leave the radar running near a window and they add up, especially under a busy approach path. A million takes years, even with an Apple TV watching all day."),
            make("logkeeper", "Log Keeper", .milestones, "book.closed.fill", tiers: [7, 30, 100, 365, 1_000], dayFirsts,
                 detail: { "Log aircraft on \(number($0)) different days" },
                 about: "Every day with at least one aircraft counts. Unlike On a Roll, a day off doesn't reset it, but there's no hurrying it either."),
            streak,
            make("seasons", "Four Seasons", .milestones, "calendar", tiers: [3, 6, 12], monthFirsts,
                 detail: { $0 == 12 ? "Log aircraft in every month of the year" : "Log aircraft in \($0) different months of the year" },
                 about: "January to December, in any year. However busy your sky, the last level takes a full year."),
            make("places", "Home & Away", .milestones, "mappin.and.ellipse", tiers: [5, 15, 50], distinct(\.placeName),
                 detail: { "Log aircraft from \($0) different places" },
                 about: "Each town or neighbourhood you watch from counts once. Take the radar on your travels."),
            farFromHome,
            make("fence", "Fence Spotter", .milestones, "airplane.arrival", tiers: [1, 5, 25], fenceFirsts,
                 detail: { $0 == 1 ? "Watch from within \(RadarFormat.spokenDistance(2)) of an airport" : "Watch from beside \($0) different airports" },
                 about: "The airport fence and the end of the runway are spotters' favourite places. Any airport within \(RadarFormat.spokenDistance(2)) of where you're watching counts, once each."),
            fullHouse,

            // Rare birds
            make("queen", "Queen of the Skies", .rareBirds, "crown.fill", tiers: [1, 10, 50], type(jumboTypes),
                 detail: { $0 == 1 ? "Spot a Boeing 747" : "Spot \($0) Boeing 747s" },
                 about: "The Boeing 747 first flew in 1969. Most passenger 747s have now retired, so these days you're most likely to catch a freighter."),
            make("superjumbo", "Superjumbo", .rareBirds, "airplane.circle.fill", tiers: [1, 5, 25], type(["A388"]),
                 detail: { $0 == 1 ? "Spot an Airbus A380" : "Spot \($0) Airbus A380s" },
                 about: "The Airbus A380 is the largest passenger airliner ever built, with two full-length decks."),
            make("heavy", "Heavy Lifter", .rareBirds, "shippingbox.fill", tiers: [1, 3, 5],
                 distinct { giantFamilies[$0.typeCode ?? ""] }, examples: newest(matching { giantFamilies[$0.typeCode ?? ""] != nil }),
                 detail: {
                     switch $0 {
                     case 1: return "Spot a giant freighter (An-124, C-5, C-17, Beluga or Dreamlifter)"
                     case 5: return "Spot all five giant freighters: An-124, C-5, C-17, Beluga and Dreamlifter"
                     default: return "Spot \($0) of the five giant freighters"
                     }
                 },
                 about: "The giants of air cargo: Antonov An-124s, Lockheed C-5 Galaxies, Boeing C-17s, Airbus Belugas and the Boeing Dreamlifter that ferries 787 parts. Each counts once."),
            make("military", "Top Brass", .rareBirds, "shield.lefthalf.filled", tiers: [1, 10, 50, 250], matching { $0.tags.contains(.military) },
                 detail: { $0 == 1 ? "Spot a military aircraft" : "Spot \(number($0)) military aircraft" },
                 about: "Picked out by a military callsign (REACH is US Air Force Air Mobility Command) or by an airframe only air forces fly."),
            make("government", "Diplomatic", .rareBirds, "building.columns.fill", tiers: [1, 10, 50], matching { $0.tags.contains(.government) },
                 detail: { $0 == 1 ? "Spot a government aircraft" : "Spot \($0) government aircraft" },
                 about: "Heads of state, ministers and officials, picked out by their government operators. SAM flights are the US Air Force's VIP fleet."),
            make("medical", "Guardian Angel", .rareBirds, "cross.case.fill", tiers: [1, 10, 50, 250], matching { $0.tags.contains(.medical) },
                 detail: { $0 == 1 ? "Spot an air ambulance" : "Spot \(number($0)) air ambulances" },
                 about: "Medical flights, usually helicopters flying low and fast to a hospital, recognized by callsigns like LIFE or LIFEGUARD."),
            make("bomber", "Bomber", .rareBirds, "bolt.shield.fill", tiers: [1, 3],
                 distinct { bomberTypes.contains($0.typeCode ?? "") ? $0.typeCode : nil }, examples: newest(type(bomberTypes)),
                 detail: { $0 == 1 ? "Spot a strategic bomber (B-52, B-1 or B-2)" : "Spot all three bombers: a B-52, a B-1 and a B-2" },
                 about: "Bombers seldom broadcast their position, so they rarely show on the radar at all. Flypasts and airshows are your best chance."),
            make("tiltrotor", "Tiltrotor", .rareBirds, "rotate.3d", tiers: [1, 10], type(tiltrotorTypes),
                 detail: { $0 == 1 ? "Spot a V-22 Osprey" : "Spot \($0) V-22 Ospreys" },
                 about: "Half helicopter, half aeroplane: the Osprey's rotors tilt forward once it's airborne. Flown by the US Marines, Air Force and Navy."),
            make("warbird", "Warbird", .rareBirds, "star.circle.fill", tiers: [1, 3, 5],
                 distinct { warbirdTypes.contains($0.typeCode ?? "") ? $0.typeCode : nil }, examples: newest(type(warbirdTypes)),
                 detail: { $0 == 1 ? "Spot a Second World War aircraft" : "Spot \($0) different Second World War aircraft" },
                 about: "DC-3s, B-17s, Mustangs, Spitfires and Texans still flying 80 years on. Airshow season is the time to look. Each type counts once."),
            make("testflight", "Test Flight", .rareBirds, "testtube.2", matching(isTestFlight),
                 detail: { _ in "Spot a Boeing or Airbus test flight" },
                 about: "New aircraft fly under their maker's own callsign before delivery: BOE for Boeing, AIB for Airbus. Live near Seattle, Charleston, Toulouse or Hamburg and you'll see plenty."),
            best("highflier", "High Flier", .rareBirds, "arrow.up.to.line", tiers: [45_000, 49_000, 51_000], format: { RadarFormat.altitudeText($0) }, word: "Highest",
                 value: { $0.altitudeAtClosestFeet },
                 detail: { "Spot an aircraft at \(RadarFormat.altitudeText($0)) or higher" },
                 about: "Airliners rarely go above \(RadarFormat.altitudeText(41_000)). Business jets like the Gulfstream G650 and the Global 7500 are certified to \(RadarFormat.altitudeText(51_000)), but seldom fly that high."),
            best("speed", "Speed Demon", .rareBirds, "gauge.with.dots.needle.100percent", tiers: [600, 650, 675], format: { RadarFormat.speedText($0) }, word: "Fastest",
                 value: { $0.speedKnots },
                 detail: { "Spot an aircraft doing \(RadarFormat.speedText($0)) or more" },
                 about: "Ground speed, not airspeed: a winter jet stream behind an eastbound airliner can push it well past \(RadarFormat.speedText(600)) over the ground. The record is just under \(RadarFormat.speedText(700))."),

            // Moments
            overhead,
            make("emergency", "Mayday", .moments, "exclamationmark.triangle.fill", tiers: [1, 3, 10], matching { $0.tags.contains { $0.isEmergency } },
                 detail: { $0 == 1 ? "Witness an emergency squawk" : "Witness \($0) emergency squawks" },
                 about: "A transponder set to 7700 (general emergency), 7600 (lost radio contact) or 7500 (unlawful interference). Most end with a safe landing."),
            make("night", "Night Owl", .moments, "moon.stars.fill", tiers: [1, 10, 50, 100], firstPerDay(hours: 0..<4),
                 examples: newest(hours(0..<4)),
                 detail: { $0 == 1 ? "Spot an aircraft between midnight and 4 am" : "Spot aircraft between midnight and 4 am on \($0) nights" },
                 about: "The small hours belong to cargo flights and the occasional late-running airliner. Each night counts once."),
            make("earlybird", "Early Bird", .moments, "sunrise.fill", tiers: [1, 10, 50, 100], firstPerDay(hours: 5..<7),
                 examples: newest(hours(5..<7)),
                 detail: { $0 == 1 ? "Spot an aircraft between 5 and 7 am" : "Spot aircraft between 5 and 7 am on \($0) mornings" },
                 about: "First departures and overnight long-hauls arriving: the early bank is when a hub wakes up. Each morning counts once."),
            make("newyear", "Happy New Year", .moments, "party.popper.fill", newYear,
                 detail: { _ in "Spot an aircraft in the first hour of New Year's Day" },
                 about: "Midnight to 1 am on January 1, wherever you are. Most of the world is celebrating; a few crews are working."),
            roundTheClock,
            busy,
            regularBadge,
            oldFriend,
            clockwork,
            make("boomerang", "Boomerang", .moments, "arrow.uturn.left.circle.fill", tiers: [1, 10, 50], boomerangs,
                 detail: { $0 == 1 ? "See an aircraft fly out and back on the same day" : "See \($0) out-and-back trips" },
                 about: "The same airframe flying A to B, then B back to A, on the same day: a short-haul shuttle's day in miniature."),

            // Collections
            make("airlines", "Globetrotter", .collections, "globe.americas.fill", tiers: [15, 30, 60, 120, 250],
                 distinct { $0.isAirline ? $0.operatorName : nil },
                 detail: { "Spot \($0) different airlines" },
                 about: "Each airline counts once, however many of its flights you see. Your local sky runs out after a while; the top levels mean watching near big international airports. Listed here: the first flight you logged from each."),
            make("alphabet", "Alphabet", .collections, "textformat.abc", tiers: [13, 20, 26], distinct(airlineInitial),
                 detail: { $0 == 26 ? "Spot an airline for every letter, A to Z" : "Spot airlines whose codes start with \($0) different letters" },
                 about: "Counted by the three-letter ICAO code at the start of the flight number: DAL for Delta, BAW for British Airways, QTR for Qatar Airways. Q, X and Z are the hard ones."),
            make("types", "Type Collector", .collections, "square.stack.3d.up.fill", tiers: [25, 50, 100, 200, 350], distinct(\.typeCode),
                 detail: { "Spot \($0) different aircraft types" },
                 about: "Counted by ICAO type code, so an A320 and an A321 are different types. Listed here: the first of each you logged."),
            make("rotor", "Rotorhead", .collections, "fan.fill", tiers: [10, 100, 1_000, 5_000, 25_000], matching { $0.kind == .helicopter },
                 detail: { "Spot \(number($0)) helicopters" },
                 about: "News, police, medical and tour helicopters mostly fly low and slow, so they're often the closest traffic you'll log."),
            make("countries", "Around the World", .collections, "flag.fill", tiers: [10, 25, 50, 100], distinct(\.registrationCountry),
                 detail: { "Spot aircraft registered in \($0) countries" },
                 about: "Told by the tail number's prefix: N for the United States, G for the UK, D for Germany, A6 for the UAE. Listed here: the first from each country."),
            make("airports", "Departure Board", .collections, "signpost.right.fill", tiers: [100, 250, 500, 1_000],
                 distinctMany { [$0.originIATA, $0.destinationIATA].compactMap { $0 } },
                 detail: { "See flights to or from \(number($0)) different airports" },
                 about: "Every origin and destination on the flights you log counts once, from the hub down the road to the far end of a long-haul."),
            make("continents", "Six Continents", .collections, "globe.asia.australia.fill", tiers: [3, 5, 6],
                 distinctMany { [$0.origin?.continent, $0.destination?.continent].compactMap { $0?.rawValue } },
                 detail: { $0 == 6 ? "See flights to or from all six inhabited continents" : "See flights to or from \($0) continents" },
                 about: "Africa, Asia, Europe, North America, South America and Oceania, by the airports at either end of the flights you log. From most places, Oceania and Africa are the hard ones."),
            make("silhouettes", "Silhouette Set", .collections, "square.grid.2x2.fill", tiers: [silhouettes],
                 distinct { $0.typeCode == nil ? nil : $0.silhouette.rawValue },
                 detail: { _ in "Spot every radar silhouette: airliners, wide-bodies, jumbos, regionals, bizjets, props, light aircraft, fighters, military transports and helicopters" },
                 about: "Every aircraft on the radar is drawn as one of \(silhouettes) shapes. Listed here: the first of each you logged."),
            best("longhaul", "Long Haul", .collections, "globe.europe.africa.fill", tiers: [5_000, 7_000, 9_000], format: distance, word: "Longest",
                 value: { $0.routeMiles.map { Int($0) } },
                 detail: { "Spot a flight whose route is \(distance($0)) or longer" },
                 about: "Measured airport to airport along the great circle. Atlanta to Johannesburg is about \(distance(8_400)); Singapore to New York, the world's longest, about \(distance(9_500))."),
            make("compass", "Compass Rose", .collections, "safari.fill", tiers: [12, 24, 36], compassFirsts,
                 detail: { $0 == 36 ? "Have aircraft pass within \(aMile) on every 10° of the compass" : "Have aircraft pass within \(aMile) heading \($0) different ways" },
                 about: "Each 10° slice of the compass counts once, for aircraft passing within \(aMile). Under an approach path most traffic lines up with the runway, so the crosswind directions take a long time."),

            // Sky View
            photoBadge("shutterbug", "Shutterbug", "camera.fill", tiers: [1, 10, 50, 250, 1_000], photos,
                       detail: { $0 == 1 ? "Take a photo in Sky View" : "Take \(number($0)) photos in Sky View" },
                       about: "Lift your iPhone to the sky, line up the label and press the shutter. Every photo is filed under its aircraft, with a boarding pass to share."),
            photoBadge("paparazzi", "Paparazzi", "camera.aperture", tiers: [5, 25, 100], typeShots,
                       detail: { "Photograph \($0) different aircraft types" },
                       about: "Each aircraft type you photograph in Sky View counts once. Listed here: the first photo of each."),
            photoBadge("rareshot", "Rare Shot", "star.square.on.square.fill", tiers: [1, 10, 25],
                       photos.filter { !$0.photo.tags.isEmpty || rareTypes.contains($0.photo.typeCode ?? "") },
                       detail: { $0 == 1 ? "Photograph a rare aircraft" : "Photograph \($0) rare aircraft" },
                       about: "A 747, an A380, a giant freighter, a bomber, a warbird, or anything the radar flags as notable: military, government, air ambulance or an emergency."),
            photoBadge("closeup", "Close-up", "plus.magnifyingglass", tiers: [1, 10, 50],
                       photos.filter { $0.photo.distanceMiles <= 1 && $0.photo.altitudeFeet <= 3_000 },
                       detail: { $0 == 1 ? "Photograph an aircraft within \(aMile) and below \(RadarFormat.altitudeText(3_000))" : "Take \($0) close-ups: within \(aMile) and below \(RadarFormat.altitudeText(3_000))" },
                       about: "Near an airport, arrivals pass low enough to fill the frame. Distance and height come from the radar at the moment of the shutter."),
        ]
    }
}
