//
//  LogbookSnapshotTests.swift
//  WhatTheFlightTests
//
//  The logbook widgets' snapshot: built from the digest, then read as of a later moment
//  (after midnight, days later) without the app, and round-tripped through the App Group.
//

import XCTest
import CoreLocation
@testable import WhatTheFlight

final class LogbookSnapshotTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    /// Friday 23 October 2026, 2:41 PM in Atlanta.
    private lazy var now: Date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 14, minute: 41))!

    private func at(daysAgo: Int, hour: Int) -> Date {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
    }

    private func sighting(_ id: String, _ date: Date, type: String = "B738", tags: [NotableTag] = []) -> Sighting {
        var s = Sighting(id: id, firstSeen: date, lastSeen: date.addingTimeInterval(300), displayIdentifier: id,
                         callsign: id, registration: "N\(id)", hex: nil, typeCode: type, kind: .airplane,
                         operatorName: "Delta Air Lines", isAirline: true, originIATA: "ATL", destinationIATA: "LGA",
                         closestMiles: 2, altitudeAtClosestFeet: 9_000, speedKnots: 280, tags: tags, placeName: "Atlanta, GA")
        s.trackAtClosest = 270
        s.timeZone = "America/New_York"
        return s
    }

    private func snapshot(_ book: [Sighting]) -> LogbookSnapshot {
        LogbookSnapshot(digest: LogbookDigest(book, now: now, calendar: calendar), observer: nil, calendar: calendar)
    }

    func testCountsDaysAndTheLatestRun() {
        // Two today, one on each of the two days before, then a gap and an older run of four.
        let book = [40, 9, 8, 7, 6, 2, 1, 0, 0].enumerated().map { i, back in sighting("s\(i)", at(daysAgo: back, hour: 9 + i % 5)) }
        let s = snapshot(book)
        XCTAssertEqual(s.total, 9)
        XCTAssertEqual(s.count(on: now, calendar: calendar), 2)
        XCTAssertEqual(s.lastRun, 3)
        XCTAssertEqual(s.bestStreak, 4)
        XCTAssertEqual(s.streak(at: now, calendar: calendar), 3)
        XCTAssertFalse(s.streakNeedsToday(at: now, calendar: calendar))
        XCTAssertFalse(s.recentDays.contains { $0.day < at(daysAgo: LogbookSnapshot.recentSpan, hour: 0) },
                       "only the last five weeks travel")
        XCTAssertEqual(s.recentDays.map(\.day), s.recentDays.map(\.day).sorted(), "oldest first")

        let week = s.days(7, endingOn: now, calendar: calendar)
        XCTAssertEqual(week.map(\.count), [1, 0, 0, 0, 1, 1, 2], "oldest first, empty days included")
        XCTAssertEqual(week.first?.day, at(daysAgo: 6, hour: 0))
    }

    func testTheStreakAndTodayMoveOnAtMidnightWithoutTheApp() {
        let book = [2, 1, 0].map { sighting("d\($0)", at(daysAgo: $0, hour: 12)) }
        let s = snapshot(book)
        let tomorrow = calendar.date(byAdding: .hour, value: 12, to: now)!
        XCTAssertEqual(s.count(on: tomorrow, calendar: calendar), 0)
        XCTAssertEqual(s.streak(at: tomorrow, calendar: calendar), 3, "still alive until the day ends")
        XCTAssertTrue(s.streakNeedsToday(at: tomorrow, calendar: calendar))
        XCTAssertNil(s.highlights(at: tomorrow, calendar: calendar), "today's highlights are yesterday's now")
        XCTAssertNotNil(s.highlights(at: now, calendar: calendar))

        let dayAfter = calendar.date(byAdding: .day, value: 2, to: now)!
        XCTAssertEqual(s.streak(at: dayAfter, calendar: calendar), 0, "a missed day ends it")
    }

    func testBadgesNextUpAndTheSky() {
        let book = (0..<60).map { i in sighting("b\(i)", at(daysAgo: i % 3, hour: 6 + i % 12), type: i % 2 == 0 ? "B738" : "A321") }
        let digest = LogbookDigest(book, now: now, calendar: calendar)
        let s = LogbookSnapshot(digest: digest, observer: CLLocationCoordinate2D(latitude: 33.75, longitude: -84.39), calendar: calendar)

        XCTAssertEqual(s.badges.count, digest.achievements.count)
        XCTAssertEqual(s.unlockedCount, digest.unlockedCount)
        XCTAssertEqual(s.levelsTotal - s.levelsEarned, digest.levelsToGo)
        XCTAssertEqual(s.nextUp, digest.nextUp(6).map(\.id))
        XCTAssertFalse(s.nextUpBadges.contains { $0.isRecord })
        let spotter = try! XCTUnwrap(s.badge(id: "spotter"))
        XCTAssertEqual(spotter.progressText, "60 of 100")
        XCTAssertEqual(spotter.levels, 5)
        XCTAssertFalse(spotter.isUnlocked)
        XCTAssertEqual(s.groups.map(\.badges.count).reduce(0, +), s.badges.count)

        XCTAssertEqual(s.featuredBadge("spotter")?.id, "spotter", "a chosen badge wins")
        XCTAssertEqual(s.featuredBadge("gone")?.id, s.nextUp.first, "a badge that's gone falls back to next up")

        let sky = try! XCTUnwrap(s.sky)
        XCTAssertEqual(sky.count, 60)
        XCTAssertTrue(sky.showsTimes)
        XCTAssertTrue(sky.showsHeadings)
        XCTAssertEqual(sky.mainSector, 12, "all westbound")
        XCTAssertEqual(sky.mainShare, 1)
        XCTAssertEqual(sky.hourly.reduce(0, +), 60)
    }

    func testRoundTripsThroughTheAppGroupAndIgnoresTheBuildTime() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "LogbookSnapshotTests"))
        defer { defaults.removePersistentDomain(forName: "LogbookSnapshotTests") }
        let store = SharedRadarStore(defaults: defaults)
        XCTAssertNil(store.logbook)

        let book = [sighting("r", at(daysAgo: 0, hour: 8), tags: [.military])]
        let s = snapshot(book)
        store.logbook = s
        XCTAssertEqual(store.logbook, s)
        // The publisher's check: a later build of the same logbook only differs in when.
        let later = LogbookSnapshot(digest: LogbookDigest(book, now: now.addingTimeInterval(600), calendar: calendar),
                                    observer: nil, calendar: calendar)
        XCTAssertNotEqual(later, s)
        XCTAssertEqual(later.built(at: s.builtAt), s, "nothing to reload")
        XCTAssertEqual(s.today?.notable, 1)
    }

    func testAnEmptyLogbook() {
        let s = snapshot([])
        XCTAssertEqual(s.total, 0)
        XCTAssertNil(s.lastDay)
        XCTAssertEqual(s.streak(at: now, calendar: calendar), 0)
        XCTAssertNil(s.today)
        XCTAssertNil(s.sky)
        XCTAssertTrue(s.recentDays.isEmpty)
        XCTAssertFalse(s.badges.isEmpty, "every badge is there, locked")
    }
}
