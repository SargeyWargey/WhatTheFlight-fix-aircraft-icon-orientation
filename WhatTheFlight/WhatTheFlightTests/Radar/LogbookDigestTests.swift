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
        let sky = digest.sky
        XCTAssertEqual(sky.hourly[8], 2)
        XCTAssertEqual(sky.hourly[17], 1)
        XCTAssertEqual(sky.busiestHourOfDay, 8)
        XCTAssertEqual(sky.weekdays[5], 2, "Friday")
        XCTAssertEqual(sky.weekdays[4], 1, "Thursday")
        XCTAssertEqual(sky.busiestWeekday, 5)
        XCTAssertEqual(sky.headings[0], 2, "2° and 359° both point north")
        XCTAssertEqual(sky.headings[12], 1, "268° is west")
        XCTAssertEqual(sky.altitudes[0], 1)
        XCTAssertEqual(sky.altitudes[7], 1)
        XCTAssertEqual(sky.altitudes[8], 1, "the top band is open-ended")
        XCTAssertEqual(sky.mainHeading?.degrees, 0)
        XCTAssertEqual(sky.topHeadings().map(\.sector), [0, 12], "north, then west")
        XCTAssertEqual(sky.topHeadings().first?.share ?? 0, 2.0 / 3, accuracy: 0.001)
        XCTAssertEqual(digest.busiestHour?.count, 2)
    }

    // MARK: Spots (the sky where you watch from)

    private let atlanta = CLLocationCoordinate2D(latitude: 33.749, longitude: -84.388)
    private let decatur = CLLocationCoordinate2D(latitude: 33.775, longitude: -84.296)   // ~5.5 mi east
    private let chicago = CLLocationCoordinate2D(latitude: 41.878, longitude: -87.630)

    private func watched(_ id: String, _ date: Date, from c: CLLocationCoordinate2D, place: String?,
                         track: Double? = 90, altitude: Int = 8_000, zone: String? = nil) -> Sighting {
        var s = sighting(id, date, track: track, place: place)
        s.altitudeAtClosestFeet = altitude
        s.observerLatitude = c.latitude
        s.observerLongitude = c.longitude
        s.timeZone = zone
        return s
    }

    func testSightingsGroupIntoSpotsByWhereTheyWereWatchedFrom() {
        var book = (0..<40).map { watched("a\($0)", at(daysAgo: 30, hour: 8).addingTimeInterval(Double($0) * 600), from: atlanta, place: "Atlanta, GA") }
        book += (0..<25).map { watched("d\($0)", at(daysAgo: 20, hour: 8).addingTimeInterval(Double($0) * 600), from: decatur, place: "Decatur, GA") }
        book += (0..<12).map { watched("c\($0)", at(daysAgo: 2, hour: 8).addingTimeInterval(Double($0) * 600), from: chicago, place: "Chicago, IL") }
        // Logged before positions were recorded: joins the spot named after its place.
        book.append(sighting("old", at(daysAgo: 40, hour: 9), place: "Atlanta, GA"))
        // Nowhere at all: only in everywhere.
        book.append(sighting("lost", at(daysAgo: 40, hour: 10), place: nil))
        book.sort { $0.firstSeen < $1.firstSeen }

        let digest = LogbookDigest(book, now: now, calendar: calendar)
        XCTAssertEqual(digest.spots.map(\.name), ["Atlanta, GA", "Chicago, IL"], "the suburb is part of home's sky; most sightings first")
        XCTAssertEqual(digest.spots.map(\.count), [66, 12])
        XCTAssertEqual(digest.sky.count, 79)
        XCTAssertEqual(digest.spot(near: decatur)?.name, "Atlanta, GA")
        XCTAssertEqual(digest.spot(near: chicago)?.name, "Chicago, IL")
        XCTAssertNil(digest.spot(near: CLLocationCoordinate2D(latitude: 40.64, longitude: -73.78)), "never watched from New York")

        // The order sightings arrive in doesn't change the spots.
        let shuffled = LogbookSpot.spots(book.reversed(), calendar: calendar)
        XCTAssertEqual(shuffled.map(\.id), digest.spots.map(\.id))
    }

    func testChartsNeedFiftyAircraft() {
        let base = at(daysAgo: 10, hour: 6)
        let few = (0..<49).map { watched("f\($0)", base.addingTimeInterval(Double($0) * 600), from: atlanta, place: "Atlanta, GA") }
        let sky = LogbookSky(few, calendar: calendar)
        XCTAssertEqual(LogbookSky.minimum, 50)
        XCTAssertTrue(sky.isFillingIn)
        XCTAssertFalse(sky.showsTimes || sky.showsHeadings || sky.showsAltitudes)

        var enough = few + [watched("f49", base.addingTimeInterval(49 * 600), from: atlanta, place: "Atlanta, GA", track: nil)]
        var ready = LogbookSky(enough, calendar: calendar)
        XCTAssertTrue(ready.showsTimes)
        XCTAssertTrue(ready.showsAltitudes)
        XCTAssertFalse(ready.showsHeadings, "only 49 of them have a heading")
        XCTAssertFalse(ready.isFillingIn)

        enough.append(watched("f50", base.addingTimeInterval(50 * 600), from: atlanta, place: "Atlanta, GA"))
        ready = LogbookSky(enough, calendar: calendar)
        XCTAssertTrue(ready.showsHeadings)
    }

    func testHoursAreLocalTimeWhereTheAircraftWasSeen() {
        var london = Calendar(identifier: .gregorian)
        london.timeZone = TimeZone(identifier: "Europe/London")!
        let nineInLondon = london.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 9))!
        let book = [
            watched("lhr", nineInLondon, from: CLLocationCoordinate2D(latitude: 51.47, longitude: -0.45), place: "London", zone: "Europe/London"),
            // Logged before zones were recorded, at the same spot: takes the spot's zone.
            watched("old", nineInLondon.addingTimeInterval(1_800), from: CLLocationCoordinate2D(latitude: 51.47, longitude: -0.45), place: "London"),
        ]
        let digest = LogbookDigest(book, now: now, calendar: calendar)
        XCTAssertEqual(digest.sky.hourly[9], 1, "9 AM in London, though the phone is now in New York")
        XCTAssertEqual(digest.sky.hourly[4], 1, "no zone and no spot to borrow one from: the phone's calendar")
        XCTAssertEqual(digest.spots.first?.sky.hourly[9], 2)
    }

    func testTheSkyShownFirstIsWhereYouAreOnceItsReadyElseHome() {
        var book = (0..<60).map { watched("a\($0)", at(daysAgo: 30, hour: 8).addingTimeInterval(Double($0) * 600), from: atlanta, place: "Atlanta, GA") }
        book += (0..<12).map { watched("c\($0)", at(daysAgo: 2, hour: 8).addingTimeInterval(Double($0) * 600), from: chicago, place: "Chicago, IL") }
        var digest = LogbookDigest(book, now: now, calendar: calendar)
        let home = digest.spots[0].id, away = digest.spots[1].id

        XCTAssertEqual(digest.sky(nil, near: chicago).spot?.id, home, "Chicago's charts aren't ready, so home's show")
        XCTAssertEqual(digest.sky(nil, near: atlanta).spot?.id, home)
        XCTAssertEqual(digest.sky(nil, near: nil).spot?.id, home)
        XCTAssertEqual(digest.sky(.spot(away), near: atlanta).spot?.id, away, "a picked spot sticks")
        XCTAssertEqual(digest.sky(.spot("gone"), near: atlanta).spot?.id, home)
        XCTAssertNil(digest.sky(.everywhere, near: atlanta).spot)
        XCTAssertEqual(digest.sky(.everywhere, near: atlanta).title, "All places")

        book += (12..<60).map { watched("c\($0)", at(daysAgo: 1, hour: 8).addingTimeInterval(Double($0) * 600), from: chicago, place: "Chicago, IL") }
        digest = LogbookDigest(book, now: now, calendar: calendar)
        XCTAssertEqual(digest.sky(nil, near: chicago).spot?.name, "Chicago, IL", "ready now, and you're there")

        XCTAssertEqual(LogbookDigest([sighting("x", at(daysAgo: 0, hour: 9), place: nil)], now: now, calendar: calendar).sky(nil, near: atlanta).scope,
                       .everywhere, "nothing positioned: everywhere")
    }

    // MARK: Slices (drilling into a chart)

    /// Two spots, a sighting from before positions were saved, one from before zones were, and
    /// a spread of tracks, hours and altitudes.
    private func slicedBook() -> [Sighting] {
        let tracks: [Double?] = [2, 45, 92, 181, 225, 230, 268, 359, nil]
        let altitudes = [0, 2_500, 7_000, 12_000, 31_000, 37_000, 44_000]
        var book = (0..<70).map { i in
            watched("a\(i)", at(daysAgo: i % 9, hour: (i * 5) % 24, minute: i % 60), from: i % 3 == 0 ? decatur : atlanta,
                    place: "Atlanta, GA", track: tracks[i % tracks.count], altitude: altitudes[i % altitudes.count],
                    zone: i % 4 == 0 ? nil : "America/New_York")
        }
        book += (0..<20).map { i in
            watched("c\(i)", at(daysAgo: i % 3, hour: 7 + i % 4), from: chicago, place: "Chicago, IL",
                    track: tracks[(i + 3) % tracks.count], altitude: altitudes[(i + 2) % altitudes.count], zone: "America/Chicago")
        }
        book.append(sighting("old", at(daysAgo: 12, hour: 9), track: 225, place: "Atlanta, GA"))
        book.append(sighting("lost", at(daysAgo: 12, hour: 10), track: 225, place: nil))
        return book.sorted { $0.firstSeen < $1.firstSeen }
    }

    func testEverySliceListsExactlyTheAircraftItsBarCounts() {
        let book = slicedBook()
        let digest = LogbookDigest(book, now: now, calendar: calendar)
        let recent = Array(book.reversed())
        XCTAssertEqual(digest.spots.map(\.name), ["Atlanta, GA", "Chicago, IL"])
        let skies: [(String?, LogbookSky)] = [(nil, digest.sky)] + digest.spots.map { ($0.id, $0.sky) }
        for (spot, sky) in skies {
            for chart in [LogbookSkySlice.heading(0), .hour(0), .weekday(0), .altitude(0)] {
                let bins = sky.bins(of: chart)
                for i in bins.indices {
                    let slice = chart.with(index: i)
                    let found = digest.sightings(in: slice, spot: spot, from: recent, calendar: calendar)
                    XCTAssertEqual(found.count, bins[i], "\(slice) in \(spot ?? "everywhere")")
                }
            }
        }
        let home = digest.spots[0].id
        XCTAssertTrue(digest.sightings(in: .heading(10), spot: home, from: recent, calendar: calendar).contains { $0.id == "old" },
                      "a sighting without a position joins the spot named after its place")
        XCTAssertFalse(digest.sightings(in: .heading(10), spot: home, from: recent, calendar: calendar).contains { $0.id == "lost" })
        XCTAssertTrue(digest.sightings(in: .heading(10), spot: nil, from: recent, calendar: calendar).contains { $0.id == "lost" })
        XCTAssertTrue(digest.sightings(in: .heading(10), spot: "gone", from: recent, calendar: calendar).isEmpty)
        XCTAssertEqual(digest.sightings(in: .hour(9), spot: home, from: recent, calendar: calendar).map(\.firstSeen),
                       digest.sightings(in: .hour(9), spot: home, from: recent, calendar: calendar).map(\.firstSeen).sorted(by: >),
                       "newest first, like the list they came from")
    }

    func testASliceSummarySaysItsShareRankAndWhoIsInIt() {
        func flight(_ id: String, _ track: Double, hour: Int, airline: String, type: String, altitude: Int) -> Sighting {
            sighting(id, at(daysAgo: 1, hour: hour), type: type, airline: airline, from: "ATL", to: track > 180 ? "DFW" : "LGA",
                     altitude: altitude, track: track)
        }
        let book = [
            flight("w1", 270, hour: 18, airline: "Delta Air Lines", type: "A321", altitude: 9_000),
            flight("w2", 268, hour: 18, airline: "Delta Air Lines", type: "B738", altitude: 11_000),
            flight("w3", 272, hour: 7, airline: "American Airlines", type: "A321", altitude: 10_000),
            flight("e1", 90, hour: 8, airline: "Delta Air Lines", type: "B739", altitude: 30_000),
            flight("n1", 0, hour: 8, airline: "Southwest Airlines", type: "B737", altitude: 4_000),
        ].sorted { $0.firstSeen < $1.firstSeen }
        let digest = LogbookDigest(book, now: now, calendar: calendar)
        let recent = Array(book.reversed())
        let west = digest.summary(of: .heading(12), spot: nil, from: recent, calendar: calendar)
        XCTAssertEqual(west.count, 3)
        XCTAssertEqual(west.total, 5)
        XCTAssertEqual(west.percent, 60)
        XCTAssertEqual(west.rank, 1)
        XCTAssertEqual(west.rankText, "The busiest direction")
        XCTAssertEqual(west.airlines.map(\.title), ["Delta Air Lines", "American Airlines"])
        XCTAssertEqual(west.types.first?.id, "A321")
        XCTAssertEqual(west.routes.map(\.title), ["ATL → DFW"])
        XCTAssertEqual(west.typicalAltitudeFeet, 10_000)
        XCTAssertEqual(west.busiestHour, 18)
        XCTAssertNil(west.mainSector, "a petal doesn't repeat its own direction")

        let eight = digest.summary(of: .hour(8), spot: nil, from: recent, calendar: calendar)
        XCTAssertEqual(eight.count, 2)
        XCTAssertEqual(eight.rank, 1, "tied with 6 PM")
        XCTAssertNil(eight.busiestHour)
        XCTAssertEqual(eight.mainSector, 0, "north and east tie; north comes first")

        let seven = digest.summary(of: .hour(7), spot: nil, from: recent, calendar: calendar)
        XCTAssertEqual(seven.rankText, "3rd busiest hour", "two hours have more")

        XCTAssertEqual(Set(digest.sightings(matching: .sky(.heading(12), spot: nil), in: recent).map(\.id)), ["w1", "w2", "w3"])
        XCTAssertFalse(LogbookFilter.sky(.heading(12), spot: nil).matches(book[0], firstOfType: []), "needs the digest")
    }

    func testSliceWording() {
        XCTAssertEqual(LogbookSkySlice.heading(10).title, "Heading southwest")
        XCTAssertEqual(LogbookSkySlice.hour(8).title, "8–9 AM")
        XCTAssertEqual(LogbookFilter.sky(.hour(23), spot: nil).title, "11 PM–12 AM")
        XCTAssertEqual(LogbookSkySlice.heading(10).phrase, "heading southwest")
        XCTAssertEqual(LogbookSkySlice.hour(8).phrase, "from 8–9 AM")
        XCTAssertEqual(LogbookSky.altitudeBandTitle(0, units: .imperial), "Below 5,000 ft")
        XCTAssertEqual(LogbookSky.altitudeBandTitle(2, units: .imperial), "10,000–15,000 ft")
        XCTAssertEqual(LogbookSky.altitudeBandTitle(8, units: .imperial), "40,000+ ft")
        XCTAssertEqual(LogbookSky.altitudeBandTitle(2, units: .metric), "3–4.5 km")
        XCTAssertEqual(LogbookSky.altitudeBandTitle(8, units: .metric), "12+ km")
        XCTAssertEqual((1...4).map(LogbookSliceSummary.ordinal), ["1st", "2nd", "3rd", "4th"])
        XCTAssertEqual([11, 12, 13, 21, 22].map(LogbookSliceSummary.ordinal), ["11th", "12th", "13th", "21st", "22nd"])
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
        XCTAssertEqual(spotter.target, 1_000)
        XCTAssertEqual(spotter.detail, "Log \(RadarFormat.wholeNumber(1_000)) aircraft")
        XCTAssertEqual(spotter.unlockedBy?.id, "s99", "the 100th sighting reached level 1")
        XCTAssertEqual(spotter.fraction, 120.0 / 1_000, accuracy: 0.0001)
        XCTAssertEqual(spotter.levelText, "Level 1 of 5")
    }

    func testEveryBadgeHasAGroupAndAUniqueID() {
        let all = Achievement.all(for: [], calendar: calendar)
        XCTAssertEqual(Set(all.map(\.id)).count, all.count)
        XCTAssertEqual(all.count, 46)
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

    private func badges(_ book: [Sighting]) -> [String: Achievement] {
        Dictionary(uniqueKeysWithValues: Achievement.all(for: book.sorted { $0.firstSeen < $1.firstSeen }, calendar: calendar).map { ($0.id, $0) })
    }

    private func watched(_ s: Sighting, from latitude: Double, _ longitude: Double) -> Sighting {
        var s = s
        s.observerLatitude = latitude
        s.observerLongitude = longitude
        return s
    }

    func testCalendarBadgesNeedTime() {
        // The same airframe on the same flight, seven days spread over five months.
        let book = (0..<7).map { i -> Sighting in
            var s = sighting("d\(i)", at(daysAgo: i * 20, hour: 9), registration: "N1DL")
            s.callsign = "DAL1"
            return s
        }
        let all = badges(book)
        XCTAssertEqual(all["logkeeper"]?.progress, 7)
        XCTAssertEqual(all["logkeeper"]?.level, 1)
        XCTAssertEqual(all["seasons"]?.progress, 5, "June to October")
        XCTAssertEqual(all["seasons"]?.target, 6)
        XCTAssertEqual(all["oldfriend"]?.progress, 120, "back 120 days after the first visit")
        XCTAssertEqual(all["oldfriend"]?.level, 1)
        XCTAssertEqual(all["oldfriend"]?.unlockedBy?.id, "d4", "the first visit 30+ days after the first")
        XCTAssertEqual(all["oldfriend"]?.targetLabel, "6 months")
        XCTAssertEqual(all["clockwork"]?.progress, 7)
        XCTAssertEqual(all["clockwork"]?.unlockedBy?.id, "d0", "the seventh day")
        XCTAssertEqual(all["newyear"]?.isUnlocked, false)
    }

    func testRoundTheClockNeedsEveryHourOfOneDayForTheTopLevel() {
        var all = badges((0..<24).map { sighting("h\($0)", at(daysAgo: 3, hour: $0)) })
        XCTAssertEqual(all["roundclock"]?.level, 4)
        XCTAssertEqual(all["roundclock"]?.unlockedBy?.id, "h23")

        // Every hour, but over two days.
        all = badges((0..<24).map { sighting("s\($0)", at(daysAgo: $0 < 12 ? 3 : 2, hour: $0)) })
        XCTAssertEqual(all["roundclock"]?.level, 3)
        XCTAssertEqual(all["roundclock"]?.progressLabel, "Best day 12 of 24 hours")
        XCTAssertEqual(all["roundclock"]?.targetLabel, "24 in a day")
    }

    func testRecordsLevelUpByThresholdAndAreNeverNextUp() {
        let book = [
            sighting("a", at(daysAgo: 2, hour: 9), miles: 0.3, altitude: 46_000, speed: 610),
            sighting("b", at(daysAgo: 1, hour: 9), miles: 0.08, altitude: 49_500),
        ]
        let all = badges(book)
        XCTAssertEqual(all["overhead"]?.level, 3, "0.08 mi beats half, a quarter and a tenth of a mile")
        XCTAssertEqual(all["overhead"]?.unlockedBy?.id, "b")
        XCTAssertEqual(all["overhead"]?.targetLabel, "0.05 mi")
        XCTAssertEqual(all["overhead"]?.progressLabel, "Closest 0.08 mi")
        XCTAssertEqual(all["highflier"]?.progress, 49_500)
        XCTAssertEqual(all["highflier"]?.level, 2)
        XCTAssertEqual(all["highflier"]?.unlockedBy?.id, "b")
        XCTAssertEqual(all["highflier"]?.progressLabel, "Highest \(RadarFormat.wholeNumber(49_500)) ft")
        XCTAssertEqual(all["highflier"]?.fraction ?? 0, 2.0 / 3, accuracy: 0.0001, "levels earned, not distance to the next")
        XCTAssertEqual(all["speed"]?.level, 1)
        XCTAssertFalse(LogbookDigest(book, now: now, calendar: calendar).nextUp(50).contains { $0.isRecord })
    }

    func testBusySkyOnlyCountsAircraftWithinFiveMiles() {
        let book = (0..<30).map { sighting("b\($0)", at(daysAgo: 1, hour: 8, minute: $0 * 2), miles: $0 < 20 ? 3 : 12) }
        XCTAssertEqual(badges(book)["busy"]?.progress, 20)
    }

    func testTravelBadges() {
        let book = [
            // Downtown Atlanta, three times: the usual spot.
            watched(sighting("a", at(daysAgo: 5, hour: 9), registration: "N1", from: "ATL", to: "LHR"), from: 33.749, -84.388),
            watched(sighting("b", at(daysAgo: 5, hour: 18), registration: "N1", from: "LHR", to: "ATL"), from: 33.749, -84.388),
            watched(sighting("c", at(daysAgo: 4, hour: 9), from: "ATL", to: "JNB"), from: 33.750, -84.390),
            // Beside Heathrow, about 4,200 miles away.
            watched(sighting("d", at(daysAgo: 1, hour: 9), from: "LHR", to: "SYD"), from: 51.470, -0.454),
        ]
        let all = badges(book)
        XCTAssertEqual(all["airports"]?.progress, 4, "ATL, LHR, JNB, SYD")
        XCTAssertEqual(all["continents"]?.progress, 4, "North America, Europe, Africa, Oceania")
        XCTAssertEqual(all["continents"]?.level, 1)
        XCTAssertEqual(all["farfromhome"]?.level, 2)
        XCTAssertEqual(all["farfromhome"]?.unlockedBy?.id, "d")
        XCTAssertEqual(Double(all["farfromhome"]?.progress ?? 0), 4_200, accuracy: 100)
        XCTAssertEqual(all["fence"]?.progress, 1, "Heathrow, not downtown Atlanta")
        XCTAssertEqual(all["fence"]?.unlockedBy?.id, "d")
        XCTAssertEqual(all["boomerang"]?.progress, 1)
        XCTAssertEqual(all["boomerang"]?.unlockedBy?.id, "b")
        XCTAssertEqual(all["longhaul"]?.level, 3, "London to Sydney is over 10,000 miles")
    }

    func testPatternAndRareBadges() {
        var book = [
            sighting("DAL1", at(daysAgo: 1, hour: 9)),
            sighting("BAW2", at(daysAgo: 1, hour: 10)),
            sighting("QTR3", at(daysAgo: 1, hour: 11)),
            sighting("N123AB", at(daysAgo: 1, hour: 12), isAirline: false),
            sighting("BOE7", at(daysAgo: 1, hour: 13), type: "B38M", isAirline: false),
            sighting("SAM1", at(daysAgo: 1, hour: 14), type: "C32", isAirline: false, tags: [.government]),
            sighting("REACH1", at(daysAgo: 2, hour: 9), type: "C17", tags: [.military]),
            sighting("BELUGA", at(daysAgo: 2, hour: 10), type: "A337"),
            sighting("DOOM1", at(daysAgo: 2, hour: 11), type: "B52", tags: [.military]),
        ]
        book += [5.0, 15, 25, 355, 45].enumerated().map { i, track in
            sighting("t\(i)", at(daysAgo: 3, hour: 9 + i), miles: track == 45 ? 3 : 0.5, track: track)
        }
        let all = badges(book)
        XCTAssertEqual(all["alphabet"]?.progress, 3, "D, B and Q, but not the private aircraft or the test flight")
        XCTAssertEqual(all["testflight"]?.isUnlocked, true)
        XCTAssertEqual(all["government"]?.isUnlocked, true)
        XCTAssertEqual(all["heavy"]?.progress, 2, "a C-17 and a Beluga")
        XCTAssertEqual(all["bomber"]?.progress, 1)
        XCTAssertEqual(all["compass"]?.progress, 4, "0°, 10°, 20° and 350°; the one 3 miles out doesn't count")
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
        UserDefaults.standard.removeObject(forKey: Logbook.announcedKey)
        defer { UserDefaults.standard.removeObject(forKey: Logbook.announcedKey) }
        let book = Logbook(fileURL: nil, device: .iPhone)
        var announced: [String] = []
        book.onBadgeUnlocked = { announced.append($0.id) }
        book.record([RadarContact(flight: TestTraffic.flight("a", miles: 0.3), observer: TestTraffic.observer, at: Date())])
        XCTAssertEqual(Set(announced), ["first", "overhead"], "a brand-new logbook announces its first badges")
        XCTAssertEqual(Set(UserDefaults.standard.stringArray(forKey: Logbook.announcedKey) ?? []), ["first@1", "overhead@1"],
                       "levels are remembered by what they take, so a changed ladder doesn't skip one")
        book.record([RadarContact(flight: TestTraffic.flight("b", miles: 0.4), observer: TestTraffic.observer, at: Date().addingTimeInterval(30))],
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
        let atlanta = CLLocationCoordinate2D(latitude: 33.749, longitude: -84.388)
        let decatur = CLLocationCoordinate2D(latitude: 33.775, longitude: -84.296)
        let chicago = CLLocationCoordinate2D(latitude: 41.878, longitude: -87.630)
        let book: [Sighting] = (0..<10_000).map { i in
            var s = Sighting(id: "s\(i)", firstSeen: start.addingTimeInterval(Double(i) * 518), lastSeen: start.addingTimeInterval(Double(i) * 518 + 300),
                             displayIdentifier: "F\(i % 900)", callsign: "F\(i % 900)", registration: "N\(i % 700)", hex: nil,
                             typeCode: types[i % types.count], kind: .airplane, operatorName: "Airline \(i % 40)", isAirline: true,
                             originIATA: airports[i % airports.count], destinationIATA: airports[(i * 3 + 1) % airports.count],
                             closestMiles: Double(i % 90) / 10 + 0.1, altitudeAtClosestFeet: (i * 37) % 45_000, speedKnots: 120 + i % 500,
                             tags: i % 97 == 0 ? [.military] : [], placeName: i % 3 == 0 ? "Atlanta, GA" : "Decatur, GA")
            s.trackAtClosest = Double((i * 29) % 360)
            s.devices = [.iPhone]
            // Mostly home and the next suburb, every seventh away in Chicago; some from before
            // time zones were recorded.
            let spot = i % 7 == 0 ? chicago : (i % 2 == 0 ? atlanta : decatur)
            s.observerLatitude = spot.latitude + Double(i % 11) * 0.004
            s.observerLongitude = spot.longitude - Double(i % 13) * 0.004
            s.timeZone = i % 5 == 0 ? nil : (i % 7 == 0 ? "America/Chicago" : "America/New_York")
            return s
        }
        let began = Date()
        let digest = LogbookDigest(book)
        let seconds = Date().timeIntervalSince(began)
        print("LogbookDigest of 10,000 sightings: \(Int(seconds * 1000)) ms")
        XCTAssertEqual(digest.stats.total, 10_000)
        XCTAssertEqual(digest.spots.count, 2, "home and the suburb are one sky; Chicago is another")
        XCTAssertLessThan(seconds, 2, "debug build, so generous")
    }
}
