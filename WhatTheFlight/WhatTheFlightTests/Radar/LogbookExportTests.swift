//
//  LogbookExportTests.swift
//  WhatTheFlightTests
//
//  CSV export, backups and restoring them (Enhancements Spec C4).
//

import XCTest
import CoreLocation
@testable import WhatTheFlight

@MainActor
final class LogbookExportTests: XCTestCase {
    private func contact(_ id: String, miles: Double, type: String = "B738") -> RadarContact {
        RadarContact(flight: TestTraffic.flight(id, miles: miles, type: type), observer: TestTraffic.observer, at: Date())
    }

    func testCSVHasHeadersAndOneRowPerSighting() {
        let book = Logbook(fileURL: nil, device: .iPhone)
        book.record([contact("a", miles: 4), contact("b", miles: 6, type: "A320")], placeName: "Atlanta, GA")
        let csv = LogbookExport.csv(book.sightings, units: .imperial)
        let lines = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].hasPrefix("First seen,Last seen,Flight,Callsign,Registration"))
        XCTAssertTrue(lines[0].contains("Closest (mi)"))
        // "Atlanta, GA" has a comma, so it's quoted.
        XCTAssertTrue(lines[1].contains("\"Atlanta, GA\""), lines[1])
        XCTAssertTrue(lines[1].contains(",4.00,"), lines[1])
    }

    func testMetricCSVConverts() {
        let book = Logbook(fileURL: nil)
        book.record([contact("a", miles: 10)])
        let csv = LogbookExport.csv(book.sightings, units: .metric)
        XCTAssertTrue(csv.contains("Closest (km)"))
        XCTAssertTrue(csv.contains(",16.09,"), csv)
    }

    func testFieldsAreEscaped() {
        XCTAssertEqual(LogbookExport.field("plain"), "plain")
        XCTAssertEqual(LogbookExport.field("a,b"), "\"a,b\"")
        XCTAssertEqual(LogbookExport.field("say \"hi\""), "\"say \"\"hi\"\"\"")
    }

    func testABackupRestoresIntoAnEmptyLogbook() throws {
        let book = Logbook(fileURL: nil)
        book.record([contact("a", miles: 4), contact("b", miles: 6)])
        let data = try LogbookExport.backupData(book.sightings)
        let fresh = Logbook(fileURL: nil)
        var uploaded = Set<String>()
        fresh.onLocalChange = { saved, _ in uploaded.formUnion(saved) }
        let result = fresh.restore(try LogbookExport.readBackup(data))
        XCTAssertEqual(result.added, 2)
        XCTAssertEqual(fresh.sightings.map(\.id).sorted(), ["a", "b"])
        XCTAssertEqual(uploaded, ["a", "b"], "restored sightings go up to iCloud")
    }

    func testRestoringTwiceAddsNothing() throws {
        let book = Logbook(fileURL: nil)
        book.record([contact("a", miles: 4)])
        let backup = try LogbookExport.readBackup(LogbookExport.backupData(book.sightings))
        let again = book.restore(backup)
        XCTAssertEqual(again, Logbook.RestoreResult(added: 0, updated: 0, photos: 0))
        XCTAssertEqual(book.sightings.count, 1)
    }

    func testABareLogbookFileRestoresToo() throws {
        let book = Logbook(fileURL: nil)
        book.record([contact("a", miles: 4)])
        let bare = try JSONEncoder().encode(book.sightings)
        XCTAssertEqual(try LogbookExport.readBackup(bare).map(\.id), ["a"])
        XCTAssertThrowsError(try LogbookExport.readBackup(Data("{\"nope\":1}".utf8)))
    }
}

@MainActor
final class DailyDigestTests: XCTestCase {
    func testADayWithSightingsHasADigest() {
        Units.current = .imperial
        let now = Date()
        let book = Logbook(fileURL: nil)
        book.record([RadarContact(flight: TestTraffic.flight("a", miles: 0.3, type: "R44"), observer: TestTraffic.observer, at: now),
                     RadarContact(flight: TestTraffic.flight("b", miles: 5), observer: TestTraffic.observer, at: now)], at: now)
        let message = DailyDigest.message(for: DailyRecap(book.sightings, day: now))
        XCTAssertEqual(message?.body.hasPrefix("2 aircraft"), true, message?.body ?? "")
        XCTAssertTrue(message?.body.contains("closest A at 0.3 mi") == true, message?.body ?? "")
    }

    func testAnEmptyDayHasNone() {
        XCTAssertNil(DailyDigest.message(for: DailyRecap([], day: Date())))
    }

    func testTheDigestIsOnlyScheduledAhead() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let morning = calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 9))!
        let night = calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 21))!
        XCTAssertEqual(DailyDigest.fireDate(minutes: 20 * 60, on: morning, calendar: calendar),
                       calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 20)))
        XCTAssertNil(DailyDigest.fireDate(minutes: 20 * 60, on: night, calendar: calendar))
    }
}
