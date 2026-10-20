//
//  TVSupportTests.swift
//  WhatTheFlightTests
//

import XCTest
import CoreLocation
@testable import WhatTheFlight

final class TVSupportTests: XCTestCase {
    func testPreviousStepsInwardAndStopsAtNearest() {
        let inRange = TestTraffic.contacts([
            TestTraffic.flight("a", miles: 1),
            TestTraffic.flight("b", miles: 2, bearing: 90),
            TestTraffic.flight("c", miles: 3, bearing: 180),
        ])
        XCTAssertEqual(FocusPolicy.previous(before: RadarFocus(focusedID: "c"), inRange: inRange).focusedID, "b")
        XCTAssertEqual(FocusPolicy.previous(before: RadarFocus(focusedID: "b"), inRange: inRange).focusedID, "a")
        XCTAssertEqual(FocusPolicy.previous(before: RadarFocus(focusedID: "a"), inRange: inRange).focusedID, "a")
        XCTAssertEqual(FocusPolicy.previous(before: RadarFocus(focusedID: "gone"), inRange: inRange).focusedID, "a")
    }

    func testLinkPayloadRoundTrips() throws {
        let payload = TVLink.Payload(latitude: 33.749, longitude: -84.388, facingDegrees: 248.5,
                                     senderName: "iPhone", sentAt: Date(timeIntervalSince1970: 1_800_000_000))
        let data = try XCTUnwrap(TVLink.encode(payload))
        XCTAssertEqual(TVLink.decode(TVLink.Payload.self, from: data), payload)

        let locationOnly = TVLink.Payload(latitude: 1, longitude: 2, facingDegrees: nil, senderName: "x", sentAt: Date(timeIntervalSince1970: 0))
        XCTAssertNil(TVLink.decode(TVLink.Payload.self, from: try XCTUnwrap(TVLink.encode(locationOnly)))?.facingDegrees)
    }

    func testAckIsNotMistakenForPayload() throws {
        let ack = try XCTUnwrap(TVLink.encode(TVLink.Ack(ok: true, message: "ok")))
        XCTAssertNil(TVLink.decode(TVLink.Payload.self, from: ack))
        XCTAssertEqual(TVLink.decode(TVLink.Ack.self, from: ack)?.ok, true)
    }

    @MainActor
    func testTVFacingAndPlaceNamePersist() {
        let defaults = UserDefaults(suiteName: "TVSupportTests-\(UUID().uuidString)")!
        let settings = RadarSettings(defaults: defaults)
        settings.customCoordinate = CLLocationCoordinate2D(latitude: 33.7, longitude: -84.4)
        settings.customPlaceName = "Atlanta, GA"
        settings.tvFacingDegrees = 248
        let reloaded = RadarSettings(defaults: defaults)
        XCTAssertEqual(reloaded.tvFacingDegrees, 248)
        XCTAssertEqual(reloaded.customPlaceName, "Atlanta, GA")

        // Moving the spot forgets the old name.
        reloaded.customCoordinate = CLLocationCoordinate2D(latitude: 40, longitude: -74)
        XCTAssertNil(reloaded.customPlaceName)
    }

    @MainActor
    func testFacingRotatesWherePlanesAppearOnScreen() {
        // An aircraft due west appears at the top of a TV that faces west.
        let track = PerimeterTrack(rect: CGRect(x: 0, y: 0, width: 1700, height: 900), cornerRadius: 60)
        let west = TestTraffic.contacts([TestTraffic.flight("w", miles: 5, bearing: 270)])
        let placements = PerimeterPlanner.plan(contacts: west, heading: 270, track: track, obstacles: [])
        let p = try! XCTUnwrap(placements.first).point
        XCTAssertEqual(p.x, track.rect.midX, accuracy: 1)
        XCTAssertEqual(p.y, track.rect.minY, accuracy: 1)
    }
}
