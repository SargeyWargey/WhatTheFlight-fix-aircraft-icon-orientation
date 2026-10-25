//
//  LogbookMergeTests.swift
//  WhatTheFlightTests
//
//  Devices on sightings, merging logbooks from several devices, and the daily recap.
//

import XCTest
import CoreLocation
@testable import WhatTheFlight

@MainActor
final class LogbookMergeTests: XCTestCase {
    private func contact(_ id: String, miles: Double, type: String = "B738", at date: Date = Date()) -> RadarContact {
        RadarContact(flight: TestTraffic.flight(id, miles: miles, type: type, at: date), observer: TestTraffic.observer, at: date)
    }

    func testRecordingStampsTheDeviceAndPlace() {
        let book = Logbook(fileURL: nil, device: .iPhone)
        book.record([contact("a", miles: 4)], placeName: "Atlanta, GA")
        XCTAssertEqual(book.sightings.first?.loggedOn, [.iPhone])
        XCTAssertEqual(book.sightings.first?.placeName, "Atlanta, GA")
        XCTAssertEqual(book.sightings.first?.timeZone, TimeZone.current.identifier, "hour charts read local time where it was logged")
    }

    func testLocalChangesAreReported() {
        let book = Logbook(fileURL: nil, device: .iPhone)
        var saved = Set<String>(), deleted = Set<String>()
        book.onLocalChange = { saved.formUnion($0); deleted.formUnion($1) }
        book.record([contact("a", miles: 4), contact("b", miles: 6)])
        XCTAssertEqual(saved, ["a", "b"])
        book.delete(["a"])
        XCTAssertEqual(deleted, ["a"])
    }

    func testUnchangedTicksAreNotReported() {
        let book = Logbook(fileURL: nil, device: .iPhone)
        let now = Date()
        book.record([contact("a", miles: 4, at: now)], at: now)
        var reports = 0
        book.onLocalChange = { _, _ in reports += 1 }
        book.record([contact("a", miles: 4, at: now)], at: now.addingTimeInterval(1))
        XCTAssertEqual(reports, 0)
    }

    func testMergingTheSameFlightKeepsTheClosestPassAndEveryDevice() {
        let phone = Logbook(fileURL: nil, device: .iPhone)
        let tv = Logbook(fileURL: nil, device: .appleTV)
        let start = Date()
        phone.record([contact("a", miles: 3, at: start)], at: start, placeName: "Atlanta, GA")
        tv.record([contact("a", miles: 6, at: start.addingTimeInterval(-60))], at: start.addingTimeInterval(-60), placeName: "Home")

        let differs = phone.merge(remote: tv.sightings)
        let merged = phone.sightings[0]
        XCTAssertEqual(phone.sightings.count, 1)
        XCTAssertEqual(merged.loggedOn, [.iPhone, .appleTV])
        XCTAssertEqual(merged.closestMiles, 3, accuracy: 0.05)
        XCTAssertEqual(merged.placeName, "Atlanta, GA")
        XCTAssertEqual(merged.firstSeen, start.addingTimeInterval(-60))
        XCTAssertEqual(differs, ["a"], "The merged copy has the iPhone too, so it goes back up")
    }

    func testMergingAnIdenticalCopyNeedsNoUpload() {
        let book = Logbook(fileURL: nil, device: .iPhone)
        book.record([contact("a", miles: 3)])
        XCTAssertEqual(book.merge(remote: book.sightings), [])
    }

    func testRemoteSightingsAreAddedInOrder() {
        let book = Logbook(fileURL: nil, device: .iPhone)
        let now = Date()
        book.record([contact("new", miles: 3, at: now)], at: now)
        let other = Logbook(fileURL: nil, device: .iPad)
        other.record([contact("old", miles: 5, at: now.addingTimeInterval(-3600))], at: now.addingTimeInterval(-3600))
        book.merge(remote: other.sightings)
        XCTAssertEqual(book.sightings.map(\.id), ["old", "new"])
        XCTAssertEqual(book.sighting(id: "old")?.loggedOn, [.iPad])
    }

    func testRemoteDeletionsRemoveSightings() {
        let book = Logbook(fileURL: nil, device: .iPhone)
        var reported = false
        book.record([contact("a", miles: 3), contact("b", miles: 4)])
        book.onLocalChange = { _, _ in reported = true }
        book.applyRemoteDeletions(["a"])
        XCTAssertEqual(book.sightings.map(\.id), ["b"])
        XCTAssertFalse(reported, "A deletion from another device isn't sent back")
    }

    func testOldSightingsWithoutDevicesStillDecode() throws {
        let book = Logbook(fileURL: nil)
        book.record([contact("a", miles: 3)])
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(book.sightings[0])) as! [String: Any]
        json.removeValue(forKey: "devices")
        let decoded = try JSONDecoder().decode(Sighting.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.loggedOn, [])
    }

    func testDailyRecapPicksOutNotableAndNewAircraft() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date()).addingTimeInterval(12 * 3600)
        let yesterday = today.addingTimeInterval(-86_400)
        let book = Logbook(fileURL: nil, device: .iPhone)
        book.record([contact("y1", miles: 5, type: "B738", at: yesterday)], at: yesterday)
        book.record([contact("t1", miles: 2, type: "B738", at: today)], at: today)
        book.record([contact("t2", miles: 4, type: "A388", at: today)], at: today)

        let recap = DailyRecap(book.sightings, day: today)
        XCTAssertEqual(recap.total, 2)
        XCTAssertEqual(recap.newTypes.map(\.id), ["t2"])
        XCTAssertEqual(recap.closest?.id, "t1")
        XCTAssertEqual(recap.notable.map(\.id), ["t2"], "An A380 is a rare type")
    }

    func testFirstDayHasNoNewTypesToBoastAbout() {
        let book = Logbook(fileURL: nil)
        book.record([contact("a", miles: 2, type: "B738")])
        XCTAssertEqual(DailyRecap(book.sightings).newTypes, [])
    }
}
