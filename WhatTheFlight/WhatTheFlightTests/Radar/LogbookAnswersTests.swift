//
//  LogbookAnswersTests.swift
//  WhatTheFlightTests
//
//  What Siri says about the logbook.
//

import XCTest
import CoreLocation
@testable import WhatTheFlight

@MainActor
final class LogbookAnswersTests: XCTestCase {
    private func log(_ book: Logbook, _ id: String, reg: String, callsign: String, at date: Date) {
        var f = TestTraffic.flight(id, miles: 3, at: date)
        f.registration = reg
        f.callsign = callsign
        f.flightNumber = nil
        book.record([RadarContact(flight: f, observer: TestTraffic.observer, at: date)], at: date)
    }

    func testSeenBeforeCountsVisitsByTailOrCallsign() {
        let book = Logbook(fileURL: nil)
        let now = Date()
        log(book, "a", reg: "G-XLEI", callsign: "BAW29G", at: now.addingTimeInterval(-10 * 86_400))
        log(book, "b", reg: "G-XLEI", callsign: "BAW11", at: now.addingTimeInterval(-3 * 86_400))
        log(book, "c", reg: "G-XLEI", callsign: "BAW29G", at: now)
        XCTAssertEqual(LogbookAnswers.matches("gxlei", in: book.sightings).count, 3)
        XCTAssertEqual(LogbookAnswers.matches("BAW29G", in: book.sightings).count, 2)
        let answer = LogbookAnswers.seenBefore("GXLEI", label: "G-XLEI", in: book.sightings, excluding: "c")
        XCTAssertTrue(answer.hasPrefix("Yes. You've seen G-XLEI 2 times"), answer)
    }

    func testNeverSeen() {
        XCTAssertEqual(LogbookAnswers.seenBefore("N1", in: []), "No, N1 isn't in your logbook yet.")
    }

    func testOnceBefore() {
        let book = Logbook(fileURL: nil)
        log(book, "a", reg: "N608AT", callsign: "DAL1751", at: Date().addingTimeInterval(-86_400))
        XCTAssertEqual(LogbookAnswers.seenBefore("N608AT", in: book.sightings), "Yes, once before: yesterday.")
    }

    func testToday() {
        Units.current = .imperial
        XCTAssertEqual(LogbookAnswers.today(DailyRecap([], day: Date())), "Nothing logged yet today.")
        let book = Logbook(fileURL: nil)
        log(book, "a", reg: "N1", callsign: "N1", at: Date())
        let answer = LogbookAnswers.today(DailyRecap(book.sightings, day: Date()))
        XCTAssertTrue(answer.hasPrefix("You've logged 1 aircraft today."), answer)
        XCTAssertEqual(LogbookAnswers.list(["a", "b", "c"]), "a, b and c")
    }
}
