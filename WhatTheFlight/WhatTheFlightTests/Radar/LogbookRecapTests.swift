//
//  LogbookRecapTests.swift
//  WhatTheFlightTests
//
//  "Your 2026 in the sky": a month or year of the logbook in headlines.
//

import XCTest
import CoreLocation
@testable import WhatTheFlight

@MainActor
final class LogbookRecapTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    private func date(_ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private func log(_ book: Logbook, _ id: String, reg: String, type: String = "B738", miles: Double = 5, on date: Date) {
        var f = TestTraffic.flight(id, miles: miles, type: type, at: date)
        f.registration = reg
        book.record([RadarContact(flight: f, observer: TestTraffic.observer, at: date)], at: date)
    }

    func testAMonthsHeadlines() throws {
        let book = Logbook(fileURL: nil)
        log(book, "s1", reg: "N1", on: date(9, 30))
        log(book, "o1", reg: "N2", on: date(10, 3))
        log(book, "o2", reg: "N2", type: "B744", miles: 0.4, on: date(10, 3, 15))
        log(book, "o3", reg: "N3", on: date(10, 12))
        log(book, "n1", reg: "N4", on: date(11, 1))
        let recap = try XCTUnwrap(LogbookRecap(book.sightings, period: .month(year: 2026, month: 10), calendar: calendar, includeBadges: false))
        XCTAssertEqual(recap.total, 3)
        XCTAssertEqual(recap.daysWatched, 2)
        XCTAssertEqual(recap.airframes, 2)
        XCTAssertEqual(recap.types, 2)
        XCTAssertEqual(recap.busiestDay?.count, 2)
        XCTAssertEqual(recap.topAircraft?.title, "N2")
        XCTAssertEqual(recap.closest?.id, "o2")
        XCTAssertEqual(recap.newTypes.map(\.id), ["o2"], "the 747 is a first; the 737 was seen in September")
    }

    func testTheCardsChartData() throws {
        let book = Logbook(fileURL: nil)
        log(book, "s1", reg: "N1", on: date(9, 30))
        log(book, "o1", reg: "N2", on: date(10, 3, 8))
        log(book, "o2", reg: "N2", type: "B744", on: date(10, 3, 17))
        log(book, "o3", reg: "N3", on: date(10, 12, 17))
        let recap = try XCTUnwrap(LogbookRecap(book.sightings, period: .month(year: 2026, month: 10), calendar: calendar,
                                               now: date(10, 20), includeBadges: false))
        XCTAssertEqual(recap.perDay.count, 31)
        XCTAssertEqual(recap.perDay[2], 2, "two on October 3")
        XCTAssertEqual(recap.perDay[11], 1)
        XCTAssertEqual(recap.perDay.reduce(0, +), 3)
        XCTAssertEqual(recap.daysSoFar, 20, "the 21st onwards are still to come")
        XCTAssertEqual(recap.leadingBlanks, 4, "October 2026 starts on a Thursday; the calendar's week starts on Sunday")
        // Hours go by each sighting's own recorded time zone, so only their shape is fixed.
        XCTAssertEqual(recap.sky.hourly.reduce(0, +), 3)
        XCTAssertEqual(recap.sky.hourly.max(), 2, "both 5 PM sightings share an hour")
        XCTAssertEqual(recap.kinds.reduce(0) { $0 + $1.count }, 3)
        XCTAssertEqual(recap.typeRanking.map(\.count), [2, 1])
        XCTAssertEqual(recap.topType?.subtitle, "B738")
        XCTAssertEqual(LogbookRecap.total(book.sightings, period: .month(year: 2026, month: 10), calendar: calendar), 3)

        let past = try XCTUnwrap(LogbookRecap(book.sightings, period: .month(year: 2026, month: 10), calendar: calendar,
                                              now: date(12, 1), includeBadges: false))
        XCTAssertEqual(past.daysSoFar, 31, "a month that's over has every day behind it")
    }

    func testTheWaffleAddsUpAndKeepsRareKinds() {
        let cells = LogbookRecap.waffle([.init(kind: .airline, count: 995), .init(kind: .cargo, count: 3), .init(kind: .military, count: 2)])
        XCTAssertEqual(cells.count, 100)
        XCTAssertEqual(cells.filter { $0 == .military }.count, 1, "seen at all, so it gets a square")
        XCTAssertEqual(cells.filter { $0 == .cargo }.count, 1)
        XCTAssertEqual(cells.first, .airline)
        XCTAssertEqual(cells.last, .military, "in the kinds' order")

        let even = LogbookRecap.waffle([.init(kind: .airline, count: 1), .init(kind: .cargo, count: 1), .init(kind: .helicopter, count: 1)])
        XCTAssertEqual(even.count, 100)
        for kind in [FlightKind.airline, .cargo, .helicopter] {
            XCTAssertTrue((33...34).contains(even.filter { $0 == kind }.count), "\(kind)")
        }
        XCTAssertTrue(LogbookRecap.waffle([]).isEmpty)
    }

    func testNothingInThePeriodIsNoRecap() {
        let book = Logbook(fileURL: nil)
        log(book, "a", reg: "N1", on: date(3, 1))
        XCTAssertNil(LogbookRecap(book.sightings, period: .month(year: 2026, month: 10), calendar: calendar, includeBadges: false))
    }

    func testAYearCountsTheBadgesEarnedInIt() throws {
        let book = Logbook(fileURL: nil)
        log(book, "a", reg: "N1", on: date(3, 1))
        let recap = try XCTUnwrap(LogbookRecap(book.sightings, period: .year(2026), calendar: calendar))
        XCTAssertTrue(recap.badges.map(\.text).contains("First Contact"), "\(recap.badges.map(\.text))")
    }

    func testWhichRecapsAreOffered() {
        XCTAssertEqual(LogbookRecap.periods(now: date(10, 26), calendar: calendar),
                       [.year(2026), .month(year: 2026, month: 10), .month(year: 2026, month: 9)])
        let january = calendar.date(from: DateComponents(year: 2027, month: 1, day: 10))!
        XCTAssertEqual(LogbookRecap.periods(now: january, calendar: calendar),
                       [.year(2026), .month(year: 2027, month: 1), .month(year: 2026, month: 12)])
    }
}
