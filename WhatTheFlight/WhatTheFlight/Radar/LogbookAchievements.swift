//
//  LogbookAchievements.swift
//  WhatTheFlight
//
//  Badges, worked out from the sightings every time the logbook changes. Nothing is stored,
//  so regrouping them or adding levels never loses one. One-off badges unlock once; counting
//  badges have levels (Plane Spotter at 100 / 500 / 1,000 / 5,000), so there's always a next
//  step. Grouped as Milestones, Rare Birds, Moments and Collections.
//

import Foundation

struct Achievement: Identifiable, Equatable, Sendable {
    enum Group: String, CaseIterable, Sendable {
        case milestones, rareBirds, moments, collections

        var title: String {
            switch self {
            case .milestones: return "Milestones"
            case .rareBirds: return "Rare Birds"
            case .moments: return "Moments"
            case .collections: return "Collections"
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
    /// How far along: aircraft, photos, days in a row, helicopters…
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

    /// Levels earned.
    var level: Int { tiers.filter { progress >= $0 }.count }
    var isUnlocked: Bool { level > 0 }
    var isMaxed: Bool { level == tiers.count }
    var hasLevels: Bool { tiers.count > 1 }
    /// The next level's target, or the top one once maxed.
    var target: Int { isMaxed ? (tiers.last ?? 1) : tiers[level] }
    var remaining: Int { max(0, target - progress) }
    /// Toward the next level (1 once maxed).
    var fraction: Double { isMaxed ? 1 : min(1, Double(progress) / Double(max(target, 1))) }

    /// "Level 2 of 3".
    var levelText: String? { hasLevels ? "Level \(level) of \(tiers.count)" : nil }

    /// The radar's notice when it's just been earned: "Badge unlocked: Mayday",
    /// "Plane Spotter · level 3".
    var unlockNotice: String {
        hasLevels && level > 1 ? "\(title) · level \(level)" : "Badge unlocked: \(title)"
    }

    static let exampleLimit = 30

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
        func number(_ n: Int) -> String { RadarFormat.wholeNumber(n) }
        var clock = DayClock(calendar)
        let hourOf = sightings.map { clock.hour(of: $0.firstSeen) }
        /// Sightings first seen in these hours of the day.
        func hours(_ range: Range<Int>) -> [Sighting] { zip(sightings, hourOf).filter { range.contains($0.1) }.map(\.0) }

        /// A badge counted by qualifying sightings: level n unlocks with the tiers[n]-th one.
        func make(_ id: String, _ title: String, _ group: Group, _ symbol: String, tiers: [Int] = [1],
                  _ qualifying: [Sighting], detail: (Int) -> String, about: String) -> Achievement {
            custom(id, title, group, symbol, tiers: tiers, progress: qualifying.count,
                   reached: { qualifying[$0 - 1] }, examples: Array(qualifying.suffix(exampleLimit).reversed()),
                   detail: detail, about: about)
        }

        /// Any badge: `reached(target)` is the sighting that first got progress to `target`.
        func custom(_ id: String, _ title: String, _ group: Group, _ symbol: String, tiers: [Int] = [1],
                    progress: Int, reached: (Int) -> Sighting?, reachedAt: ((Int) -> Date?)? = nil,
                    examples: [Sighting], detail: (Int) -> String, about: String) -> Achievement {
            let level = tiers.filter { progress >= $0 }.count
            let target = level == tiers.count ? (tiers.last ?? 1) : tiers[level]
            let top = level > 0 ? tiers[level - 1] : nil
            let by = top.flatMap(reached)
            return Achievement(id: id, title: title, group: group, detail: detail(target), about: about, symbol: symbol,
                               progress: progress, tiers: tiers, unlockedBy: by,
                               unlockedAt: top.flatMap { reachedAt?($0) } ?? by?.firstSeen,
                               examples: examples)
        }

        // Days in a row: progress is the longest run.
        let runs = LogbookMath.dayRuns(sightings, calendar: calendar)
        let bestRun = runs.max { $0.length < $1.length }
        let streak = custom(
            "streak", "On a Roll", .milestones, "flame.fill", tiers: [7, 30],
            progress: bestRun?.length ?? 0,
            reached: { target in runs.first { $0.length >= target }?.firstOfDay[target - 1] },
            examples: Array((bestRun?.firstOfDay ?? []).reversed()),
            detail: { "Spot something \($0) days in a row" },
            about: "One aircraft a day keeps the streak alive. Leave the radar running on an Apple TV or an iPad and the days add up.")

        // Photos: counted by photo, filed under their sightings.
        let photos = sightings.flatMap { s in s.spotPhotos.map { (sighting: s, photo: $0) } }.sorted { $0.photo.takenAt < $1.photo.takenAt }
        var photographed = Set<String>()
        let shutterbug = custom(
            "shutterbug", "Shutterbug", .milestones, "camera.fill", tiers: [1, 10, 50],
            progress: photos.count,
            reached: { photos[$0 - 1].sighting },
            reachedAt: { photos[$0 - 1].photo.takenAt },
            examples: photos.reversed().map(\.sighting).filter { photographed.insert($0.id).inserted }.prefix(exampleLimit).map { $0 },
            detail: { $0 == 1 ? "Take a photo in Sky View" : "Take \($0) photos in Sky View" },
            about: "Lift your iPhone to the sky, line up the label and press the shutter. Every photo is filed under its aircraft, with a boarding pass to share.")

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

        // Busiest hour: the most first seen within sixty minutes.
        let sorted = sightings.sorted { $0.firstSeen < $1.firstSeen }
        let windows = LogbookMath.hourWindows(sorted)
        let peak = LogbookMath.peakHour(sightings)
        let busy = custom(
            "busy", "Busy Sky", .moments, "chart.bar.fill", tiers: [25],
            progress: windows.max() ?? 0,
            reached: { target in windows.firstIndex { $0 >= target }.map { sorted[$0] } },
            examples: peak?.sightings ?? [],
            detail: { "Log \($0) aircraft in one hour" },
            about: "Rush hour in the sky: morning and early-evening banks at a hub airport can put dozens of aircraft through your radius in an hour.")

        // The same airframe again and again.
        var visits: [String: [Sighting]] = [:]
        var firstToReach: [Int: Sighting] = [:]
        for s in sightings {
            guard let airframe = s.airframe else { continue }
            visits[airframe, default: []].append(s)
            let n = visits[airframe]!.count
            if firstToReach[n] == nil { firstToReach[n] = s }
        }
        let regular = visits.values.max { ($0.count, $0.last!.firstSeen) < ($1.count, $1.last!.firstSeen) } ?? []
        let regularBadge = custom(
            "regular", "Regular", .moments, "arrow.triangle.2.circlepath", tiers: [10, 25],
            progress: regular.count,
            reached: { firstToReach[$0] },
            examples: Array(regular.suffix(exampleLimit).reversed()),
            detail: { "See the same aircraft \($0) times" },
            about: "Airlines fly the same airframes on the same routes day after day. Listed here: every visit from the aircraft you've seen most.")

        let silhouettes = AircraftSilhouette.allCases.count

        return [
            // Milestones
            make("first", "First Contact", .milestones, "airplane", sightings,
                 detail: { _ in "Log your first aircraft" },
                 about: "Every logbook starts somewhere. Any aircraft that comes inside your radius counts."),
            make("spotter", "Plane Spotter", .milestones, "binoculars.fill", tiers: [100, 500, 1_000, 5_000], sightings,
                 detail: { "Log \(number($0)) aircraft" },
                 about: "Leave the radar running near a window and they add up, especially under a busy approach path. Five thousand and you know the local traffic better than most people on the ground."),
            streak,
            shutterbug,
            make("places", "Home & Away", .milestones, "mappin.and.ellipse", tiers: [5], distinct(\.placeName),
                 detail: { "Log aircraft from \($0) different places" },
                 about: "Each town or neighbourhood you watch from counts once. Take the radar on your travels."),
            fullHouse,

            // Rare birds
            make("queen", "Queen of the Skies", .rareBirds, "crown.fill",
                 type(["B741", "B742", "B743", "B744", "B748", "B74S", "BLCF", "VC25"]),
                 detail: { _ in "Spot a Boeing 747" },
                 about: "The Boeing 747 first flew in 1969. Most passenger 747s have now retired, so these days you're most likely to catch a freighter."),
            make("superjumbo", "Superjumbo", .rareBirds, "airplane.circle.fill", type(["A388"]),
                 detail: { _ in "Spot an Airbus A380" },
                 about: "The Airbus A380 is the largest passenger airliner ever built, with two full-length decks."),
            make("heavy", "Heavy Lifter", .rareBirds, "shippingbox.fill",
                 type(["A124", "A225", "C5M", "C5", "C17", "BLCF", "A3ST", "A337"]),
                 detail: { _ in "Spot a giant freighter (An-124, C-5, C-17, Beluga, Dreamlifter)" },
                 about: "The giants of air cargo: Antonov An-124s, Lockheed C-5 Galaxies, Boeing C-17s, Airbus Belugas and the Boeing Dreamlifter that ferries 787 parts."),
            make("military", "Top Brass", .rareBirds, "shield.lefthalf.filled", matching { $0.tags.contains(.military) },
                 detail: { _ in "Spot a military aircraft" },
                 about: "Picked out by a military callsign (REACH is US Air Force Air Mobility Command) or by an airframe only air forces fly."),
            make("medical", "Guardian Angel", .rareBirds, "cross.case.fill", matching { $0.tags.contains(.medical) },
                 detail: { _ in "Spot an air ambulance" },
                 about: "Medical flights, usually helicopters flying low and fast to a hospital, recognized by callsigns like LIFE or LIFEGUARD."),
            make("highflier", "High Flier", .rareBirds, "arrow.up.to.line", matching { $0.altitudeAtClosestFeet >= 45_000 },
                 detail: { _ in "Spot an aircraft at 45,000 ft or higher" },
                 about: "Airliners rarely go above 41,000 ft. Up at 45,000 ft and beyond you'll find business jets like the Gulfstream G650 and the Global 7500."),
            make("speed", "Speed Demon", .rareBirds, "gauge.with.dots.needle.100percent", matching { $0.speedKnots >= 600 },
                 detail: { _ in "Spot an aircraft doing 600 kts or more" },
                 about: "Ground speed, not airspeed: a winter jet stream behind an eastbound airliner can push it well past 600 knots over the ground."),

            // Moments
            make("overhead", "Right Overhead", .moments, "scope", matching { $0.closestMiles < 0.5 },
                 detail: { _ in "Have an aircraft pass within half a mile" },
                 about: "About as close as a flight gets: its track passed within half a mile of where you were watching."),
            make("emergency", "Mayday", .moments, "exclamationmark.triangle.fill", matching { $0.tags.contains { $0.isEmergency } },
                 detail: { _ in "Witness an emergency squawk" },
                 about: "A transponder set to 7700 (general emergency), 7600 (lost radio contact) or 7500 (unlawful interference). Most end with a safe landing."),
            make("night", "Night Owl", .moments, "moon.stars.fill",
                 hours(0..<4),
                 detail: { _ in "Spot an aircraft between midnight and 4 am" },
                 about: "The small hours belong to cargo flights and the occasional late-running airliner."),
            make("earlybird", "Early Bird", .moments, "sunrise.fill",
                 hours(5..<7),
                 detail: { _ in "Spot an aircraft between 5 and 7 am" },
                 about: "First departures and overnight long-hauls arriving: the early bank is when a hub wakes up."),
            busy,
            regularBadge,

            // Collections
            make("airlines", "Globetrotter", .collections, "globe.americas.fill", tiers: [15, 30, 60],
                 distinct { $0.isAirline ? $0.operatorName : nil },
                 detail: { "Spot \($0) different airlines" },
                 about: "Each airline counts once, however many of its flights you see. Listed here: the first flight you logged from each."),
            make("types", "Type Collector", .collections, "square.stack.3d.up.fill", tiers: [25, 50, 100], distinct(\.typeCode),
                 detail: { "Spot \($0) different aircraft types" },
                 about: "Counted by ICAO type code, so an A320 and an A321 are different types. Listed here: the first of each you logged."),
            make("rotor", "Rotorhead", .collections, "fan.fill", tiers: [10, 50], matching { $0.kind == .helicopter },
                 detail: { "Spot \($0) helicopters" },
                 about: "News, police, medical and tour helicopters mostly fly low and slow, so they're often the closest traffic you'll log."),
            make("countries", "Around the World", .collections, "flag.fill", tiers: [10, 25], distinct(\.registrationCountry),
                 detail: { "Spot aircraft registered in \($0) countries" },
                 about: "Told by the tail number's prefix: N for the United States, G for the UK, D for Germany, A6 for the UAE. Listed here: the first from each country."),
            make("silhouettes", "Silhouette Set", .collections, "square.grid.2x2.fill", tiers: [silhouettes],
                 distinct { $0.typeCode == nil ? nil : $0.silhouette.rawValue },
                 detail: { _ in "Spot every radar silhouette: airliners, wide-bodies, jumbos, regionals, bizjets, props, light aircraft, fighters, military transports and helicopters" },
                 about: "Every aircraft on the radar is drawn as one of \(silhouettes) shapes. Listed here: the first of each you logged."),
            make("longhaul", "Long Haul", .collections, "globe.europe.africa.fill", matching { ($0.routeMiles ?? 0) >= 5_000 },
                 detail: { _ in "Spot a flight whose route is 5,000 miles or longer" },
                 about: "Measured airport to airport along the great circle. Atlanta to Seoul or Johannesburg, Dallas to Sydney: the longest flights in the world."),
        ]
    }
}
