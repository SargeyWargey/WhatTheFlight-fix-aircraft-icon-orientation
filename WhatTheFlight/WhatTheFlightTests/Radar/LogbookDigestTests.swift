//
//  LogbookDigestTests.swift
//  WhatTheFlightTests
//
//  The logbook digest (days, months, rankings, records, chart data, streaks) and the
//  grouped, levelled badges.
//

import XCTest
import CoreLocation
@testable import WhatTheFlight

final class LogbookDigestTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    /// Friday 23 October 2026, 2:41 PM in Atlanta.
    private lazy var now: Date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 14, minute: 41))!

    private func at(daysAgo: Int, hour: Int, minute: Int = 0) -> Date {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private func sighting(_ id: String, _ date: Date, registration: String? = nil, type: String? = "B738",
                          airline: String = "Delta Air Lines", isAirline: Bool = true, from: String? = nil, to: String? = nil,
                          miles: Double = 3, altitude: Int = 8_000, speed: Int = 250, track: Double? = nil,
                          tags: [NotableTag] = [], kind: AircraftKind = .airplane, place: String? = "Atlanta, GA",
                          devices: [LogDevice]? = [.iPhone]) -> Sighting {
        var s = Sighting(id: id, firstSeen: date, lastSeen: date.addingTimeInterval(300), displayIdentifier: id,
                         callsign: id, registration: registration, hex: nil, typeCode: type, kind: kind,
                         operatorName: airline, isAirline: isAirline, originIATA: from, destinationIATA: to,
                         closestMiles: miles, altitudeAtClosestFeet: altitude, speedKnots: speed, tags: tags, placeName: place)
        s.trackAtClosest = track
        s.devices = devices
        return s
    }

    // MARK: Days and months

    func testDaysAreNewestFirstAndNewTypesSkipTheFirstDay() {
        let book = [
            sighting("a", at(daysAgo: 20, hour: 9), type: "B738"),
            sighting("b", at(daysAgo: 20, hour: 10), type: "A321"),
            sighting("c", at(daysAgo: 1, hour: 8), type: "A359"),
            sighting("d", at(daysAgo: 0, hour: 7), type: "B738"),
            sighting("e", at(daysAgo: 0, hour: 9), type: "A388", tags: [.rare]),
        ]
        let digest = LogbookDigest(book, now: now, calendar: calendar)
        XCTAssertEqual(digest.days.map(\.count), [2, 1, 2])
        XCTAssertEqual(digest.days.first?.sightings.map(\.id), ["e", "d"], "newest first within a day")
        XCTAssertEqual(digest.firstOfType, ["c", "e"], "the first day's types aren't 'new'")
        XCTAssertEqual(digest.days.first?.newTypes, 1)
        XCTAssertEqual(digest.days.first?.notable, 1)

        XCTAssertEqual(digest.thisWeek(now: now, calendar: calendar).count, 2)
        let months = digest.earlierMonths(now: now, calendar: calendar)
        XCTAssertEqual(months.count, 1)
        XCTAssertEqual(months.first?.count, 2)
        XCTAssertEqual(digest.busiestDay?.day, calendar.startOfDay(for: now), "ties go to the latest day")

        let recent = digest.recentDays(3, now: now, calendar: calendar)
        XCTAssertEqual(recent.map(\.count), [0, 1, 2], "oldest first, empty days included")
    }

    func testStreaks() {
        let book = [0, 1, 2, 5, 6, 7, 8].map { sighting("s\($0)", at(daysAgo: $0, hour: 12)) }
        let streak = LogbookDigest(book, now: now, calendar: calendar).streak
        XCTAssertEqual(streak.current, 3)
        XCTAssertEqual(streak.best, 4)

        // Nothing yet today: yesterday's run still counts.
        let yesterday = LogbookMath.streak([sighting("y", at(daysAgo: 1, hour: 9))], now: now, calendar: calendar)
        XCTAssertEqual(yesterday.current, 1)
        let stale = LogbookMath.streak([sighting("z", at(daysAgo: 3, hour: 9))], now: now, calendar: calendar)
        XCTAssertEqual(stale.current, 0)
        XCTAssertEqual(stale.best, 1)
    }

    // MARK: Rankings and records

    func testRankingsCountAndOrder() {
        let book = [
            sighting("a1", at(daysAgo: 3, hour: 7), registration: "N685DA", from: "ATL", to: "LGA"),
            sighting("a2", at(daysAgo: 2, hour: 7), registration: "N685DA", from: "ATL", to: "LGA"),
            sighting("a3", at(daysAgo: 1, hour: 7), registration: "N685DA", from: "ATL", to: "BOS"),
            sighting("b1", at(daysAgo: 1, hour: 9), registration: "G-XLEI", airline: "British Airways", from: "LHR", to: "ATL"),
            sighting("c1", at(daysAgo: 0, hour: 9), registration: "N8655D", airline: "Southwest Airlines", from: "ATL", to: "LGA"),
            sighting("c2", at(daysAgo: 0, hour: 10), registration: "N8655D", airline: "Southwest Airlines"),
            sighting("p1", at(daysAgo: 0, hour: 11), registration: "N44RH", isAirline: false),
        ]
        let digest = LogbookDigest(book, now: now, calendar: calendar)
        XCTAssertEqual(digest.rankings[.aircraft]?.map(\.id), ["N685DA", "N8655D"], "only airframes seen more than once")
        XCTAssertEqual(digest.rankings[.aircraft]?.first?.count, 3)
        XCTAssertEqual(digest.regularRank(airframe: "N8655D"), 2)
        XCTAssertNil(digest.regularRank(airframe: "N44RH"))
        XCTAssertEqual(digest.rankings[.airlines]?.map(\.id), ["Delta Air Lines", "Southwest Airlines", "British Airways"])
        XCTAssertEqual(digest.rankings[.routes]?.first?.id, "ATL-LGA")
        XCTAssertEqual(digest.rankings[.routes]?.first?.count, 3)
        XCTAssertEqual(digest.rankings[.airports]?.first?.id, "ATL")
        XCTAssertEqual(digest.rankings[.airports]?.first?.count, 5)
        XCTAssertEqual(Set(digest.rankings[.countries]?.map(\.id) ?? []), ["US", "GB"])
        XCTAssertEqual(digest.countryCount, 2)

        let delta = digest.sightings(matching: LogbookRanking.airlines.filter(for: "Delta Air Lines"), in: book)
        XCTAssertEqual(delta.map(\.id), ["a1", "a2", "a3"])
        XCTAssertEqual(digest.sightings(matching: .airport("LHR"), in: book).map(\.id), ["b1"])
    }

    func testRecords() {
        let book = [
            sighting("near", at(daysAgo: 1, hour: 9), miles: 0.18, altitude: 900, speed: 110, kind: .helicopter),
            sighting("high", at(daysAgo: 1, hour: 10), altitude: 45_000, speed: 480),
            sighting("fast", at(daysAgo: 0, hour: 9), altitude: 36_000, speed: 641),
            sighting("long", at(daysAgo: 0, hour: 12), from: "ATL", to: "ICN"),
        ]
        let records = Dictionary(uniqueKeysWithValues: LogbookDigest(book, now: now, calendar: calendar).records.map { ($0.id, $0) })
        XCTAssertEqual(records["closest"]?.sighting.id, "near")
        XCTAssertEqual(records["closest"]?.value, "0.2 mi")
        XCTAssertEqual(records["highest"]?.sighting.id, "high")
        XCTAssertEqual(records["fastest"]?.value, "641 kts")
        XCTAssertEqual(records["lowest"]?.sighting.id, "near")
        XCTAssertEqual(records["route"]?.sighting.id, "long")
        XCTAssertGreaterThan(book[3].routeMiles ?? 0, 7_000, "Atlanta to Seoul")
    }

    // MARK: Chart data

    func testHourlyWeekdayHeadingAndAltitudeBins() {
        let book = [
            sighting("a", at(daysAgo: 0, hour: 8), altitude: 3_000, track: 2),
            sighting("b", at(daysAgo: 0, hour: 8, minute: 30), altitude: 37_000, track: 268),
            sighting("c", at(daysAgo: 1, hour: 17), altitude: 52_000, track: 359),
        ]
        let digest = LogbookDigest(book, now: now, calendar: calendar)
        XCTAssertEqual(digest.hourly[8], 2)
        XCTAssertEqual(digest.hourly[17], 1)
        XCTAssertEqual(digest.busiestHourOfDay, 8)
        XCTAssertEqual(digest.weekdays[5], 2, "Friday")
        XCTAssertEqual(digest.weekdays[4], 1, "Thursday")
        XCTAssertEqual(digest.headings[0], 2, "2° and 359° both point north")
        XCTAssertEqual(digest.headings[12], 1, "268° is west")
        XCTAssertEqual(digest.altitudes[0], 1)
        XCTAssertEqual(digest.altitudes[7], 1)
        XCTAssertEqual(digest.altitudes[8], 1, "the top band is open-ended")
        XCTAssertEqual(digest.mainHeading?.degrees, 0)
        XCTAssertEqual(digest.topHeadings().map(\.sector), [0, 12], "north, then west")
        XCTAssertEqual(digest.topHeadings().first?.share ?? 0, 2.0 / 3, accuracy: 0.001)
        XCTAssertEqual(digest.busiestHour?.count, 2)
    }

    func testFormatting() {
        XCTAssertEqual(LogbookFormat.hourRange(7), "7–8 AM")
        XCTAssertEqual(LogbookFormat.hourRange(11), "11 AM–12 PM")
        XCTAssertEqual(LogbookFormat.hourRange(12), "12–1 PM")
        XCTAssertEqual(LogbookFormat.hourRange(23), "11 PM–12 AM")
        XCTAssertEqual(LogbookFormat.duration(20), "Under a min")
        XCTAssertEqual(LogbookFormat.duration(65 * 60), "1 h 05 min")
        XCTAssertEqual(LogbookFormat.preciseMiles(0.18), "0.2 mi")
        XCTAssertEqual(LogbookFormat.direction(268), "west")
    }

    // MARK: Badges

    func testLevelledBadges() {
        let book = (0..<120).map { sighting("s\($0)", at(daysAgo: 0, hour: 0).addingTimeInterval(Double($0) * 600)) }
        let spotter = try! XCTUnwrap(Achievement.all(for: book, calendar: calendar).first { $0.id == "spotter" })
        XCTAssertEqual(spotter.level, 1)
        XCTAssertTrue(spotter.isUnlocked)
        XCTAssertFalse(spotter.isMaxed)
        XCTAssertEqual(spotter.target, 500)
        XCTAssertEqual(spotter.detail, "Log 500 aircraft")
        XCTAssertEqual(spotter.unlockedBy?.id, "s99", "the 100th sighting reached level 1")
        XCTAssertEqual(spotter.fraction, 120.0 / 500, accuracy: 0.0001)
        XCTAssertEqual(spotter.levelText, "Level 1 of 4")
    }

    func testEveryBadgeHasAGroupAndAUniqueID() {
        let all = Achievement.all(for: [], calendar: calendar)
        XCTAssertEqual(Set(all.map(\.id)).count, all.count)
        XCTAssertEqual(all.count, 25)
        for group in Achievement.Group.allCases {
            XCTAssertFalse(all.filter { $0.group == group }.isEmpty, group.title)
        }
        XCTAssertTrue(all.allSatisfy { !$0.isUnlocked && $0.unlockedBy == nil })
    }

    func testBusyStreakRegularAndFullHouse() {
        // 25 aircraft in 50 minutes on one day…
        var book = (0..<25).map { sighting("h\($0)", at(daysAgo: 20, hour: 8).addingTimeInterval(Double($0) * 120), registration: "N\($0)") }
        // …the same airframe ten mornings running…
        book += (0..<10).reversed().map { sighting("r\($0)", at(daysAgo: $0, hour: 7), registration: "N685DA", devices: [$0 == 0 ? .appleTV : .iPhone]) }
        // …and one logged on an iPad.
        book.append(sighting("i", at(daysAgo: 0, hour: 12), devices: [.iPad]))
        book.sort { $0.firstSeen < $1.firstSeen }
        let all = Dictionary(uniqueKeysWithValues: Achievement.all(for: book, calendar: calendar).map { ($0.id, $0) })

        XCTAssertEqual(all["busy"]?.progress, 25)
        XCTAssertEqual(all["busy"]?.unlockedBy?.id, "h24")
        XCTAssertEqual(all["regular"]?.progress, 10)
        XCTAssertEqual(all["regular"]?.unlockedBy?.id, "r0")
        XCTAssertEqual(all["streak"]?.progress, 10)
        XCTAssertEqual(all["streak"]?.level, 1)
        XCTAssertEqual(all["streak"]?.unlockedBy?.id, "r3", "the seventh day in a row")
        XCTAssertEqual(all["fullhouse"]?.progress, 3)
        XCTAssertEqual(all["fullhouse"]?.unlockedBy?.id, "i")

        let digest = LogbookDigest(book, now: now, calendar: calendar)
        XCTAssertFalse(digest.nextUp().contains { $0.isMaxed })
        XCTAssertEqual(digest.recentlyUnlocked(1).first?.unlockedAt, book.last?.firstSeen)
    }

    @MainActor
    func testDigestIsCachedUntilTheLogbookChanges() {
        let book = Logbook(fileURL: nil, device: .iPhone)
        book.record([RadarContact(flight: TestTraffic.flight("a", miles: 3), observer: TestTraffic.observer, at: Date())])
        let first = book.digest
        XCTAssertEqual(first.stats.total, 1)
        XCTAssertEqual(book.digest.builtAt, first.builtAt, "same revision: cached")
        book.record([RadarContact(flight: TestTraffic.flight("b", miles: 3), observer: TestTraffic.observer, at: Date())])
        XCTAssertEqual(book.digest.stats.total, 2)
    }

    @MainActor
    func testBigLogbooksRebuildTheirDigestInTheBackground() async throws {
        let book = Logbook(fileURL: nil, device: .iPhone)
        let count = Logbook.backgroundDigestThreshold + 100
        book.merge(remote: (0..<count).map { sighting("s\($0)", at(daysAgo: 3, hour: 0).addingTimeInterval(Double($0) * 60)) })
        XCTAssertEqual(book.digest.stats.total, count, "the first build is immediate")
        book.record([RadarContact(flight: TestTraffic.flight("new", miles: 3), observer: TestTraffic.observer, at: Date())])
        XCTAssertEqual(book.digest.stats.total, count, "the previous digest while the new one builds")
        for _ in 0..<200 where book.digest.stats.total != count + 1 {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(book.digest.stats.total, count + 1)
    }

    @MainActor
    func testNewBadgesAreAnnouncedOnce() {
        UserDefaults.standard.removeObject(forKey: "wtf.announcedBadgeLevels")
        defer { UserDefaults.standard.removeObject(forKey: "wtf.announcedBadgeLevels") }
        let book = Logbook(fileURL: nil, device: .iPhone)
        var announced: [String] = []
        book.onBadgeUnlocked = { announced.append($0.id) }
        book.record([RadarContact(flight: TestTraffic.flight("a", miles: 0.3), observer: TestTraffic.observer, at: Date())])
        XCTAssertEqual(Set(announced), ["first", "overhead"], "a brand-new logbook announces its first badges")
        book.record([RadarContact(flight: TestTraffic.flight("b", miles: 0.2), observer: TestTraffic.observer, at: Date().addingTimeInterval(30))],
                    at: Date().addingTimeInterval(30))
        XCTAssertEqual(announced.count, 2, "nothing new")
    }
}

final class LogbookDigestPerformanceTests: XCTestCase {
    /// A full logbook (10,000 sightings, the cap) should build its digest in well under a
    /// second, since the screens rebuild it after every change.
    func testDigestOfAFullLogbook() {
        let types = ["B738", "A321", "A320", "B739", "CRJ9", "E75L", "B77W", "A359", "R44", "C172", "GLF6", "B744"]
        let airports = ["ATL", "LGA", "BOS", "MCO", "LHR", "ICN", "DFW", "SEA"]
        let start = Date().addingTimeInterval(-60 * 86_400)
        let book: [Sighting] = (0..<10_000).map { i in
            var s = Sighting(id: "s\(i)", firstSeen: start.addingTimeInterval(Double(i) * 518), lastSeen: start.addingTimeInterval(Double(i) * 518 + 300),
                             displayIdentifier: "F\(i % 900)", callsign: "F\(i % 900)", registration: "N\(i % 700)", hex: nil,
                             typeCode: types[i % types.count], kind: .airplane, operatorName: "Airline \(i % 40)", isAirline: true,
                             originIATA: airports[i % airports.count], destinationIATA: airports[(i * 3 + 1) % airports.count],
                             closestMiles: Double(i % 90) / 10 + 0.1, altitudeAtClosestFeet: (i * 37) % 45_000, speedKnots: 120 + i % 500,
                             tags: i % 97 == 0 ? [.military] : [], placeName: i % 3 == 0 ? "Atlanta, GA" : "Decatur, GA")
            s.trackAtClosest = Double((i * 29) % 360)
            s.devices = [.iPhone]
            return s
        }
        let began = Date()
        let digest = LogbookDigest(book)
        let seconds = Date().timeIntervalSince(began)
        print("LogbookDigest of 10,000 sightings: \(Int(seconds * 1000)) ms")
        XCTAssertEqual(digest.stats.total, 10_000)
        XCTAssertLessThan(seconds, 2, "debug build, so generous")
    }
}
