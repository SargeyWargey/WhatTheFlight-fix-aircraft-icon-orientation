//
//  WatchSupportTests.swift
//  WhatTheFlightTests
//
//  Apple Watch: Point & Find maths, the iPhone → Watch sync payload, complication timeline
//  projection and the perimeter cap for small screens.
//

import XCTest
import CoreLocation
import simd
@testable import WhatTheFlight

final class WristPointingTests: XCTestCase {
    func testCrownTowardHandPointsAlongPositiveX() {
        XCTAssertEqual(WristPointing.axisSign(leftWrist: true, crownOnRight: true), 1)
        XCTAssertEqual(WristPointing.axisSign(leftWrist: false, crownOnRight: false), 1)
        XCTAssertEqual(WristPointing.axisSign(leftWrist: true, crownOnRight: false), -1)
        XCTAssertEqual(WristPointing.axisSign(leftWrist: false, crownOnRight: true), -1)
        XCTAssertEqual(WristPointing.axisSign(leftWrist: true, crownOnRight: true, flipped: true), -1)
    }

    /// Rows of the attitude matrix: each device axis in the north-west-up reference frame.
    private func rows(x: SIMD3<Double>, y: SIMD3<Double>, z: SIMD3<Double>) -> [SIMD3<Double>] { [x, y, z] }

    func testArmPointingEastAtTheHorizon() {
        // Watch face up, x axis (crown side) toward east = -west.
        let r = rows(x: SIMD3(0, -1, 0), y: SIMD3(1, 0, 0), z: SIMD3(0, 0, 1))
        let dir = WristPointing.direction(of: WristPointing.pointing(rows: r, axesAreRows: true, axisSign: 1))
        XCTAssertEqual(dir.azimuth, 90, accuracy: 0.001)
        XCTAssertEqual(dir.elevation, 0, accuracy: 0.001)

        let back = WristPointing.direction(of: WristPointing.pointing(rows: r, axesAreRows: true, axisSign: -1))
        XCTAssertEqual(back.azimuth, 270, accuracy: 0.001)
    }

    func testArmRaisedTowardTheNorthSky() {
        // x axis points north and 45° up.
        let s = sqrt(0.5)
        let r = rows(x: SIMD3(s, 0, s), y: SIMD3(0, 1, 0), z: SIMD3(-s, 0, s))
        let dir = WristPointing.direction(of: WristPointing.pointing(rows: r, axesAreRows: true, axisSign: 1))
        XCTAssertEqual(dir.azimuth, 0, accuracy: 0.001)
        XCTAssertEqual(dir.elevation, 45, accuracy: 0.001)
    }

    func testColumnConventionTransposes() {
        let r = rows(x: SIMD3(0, -1, 0), y: SIMD3(1, 0, 0), z: SIMD3(0, 0, 1))
        let transposed = [SIMD3(r[0].x, r[1].x, r[2].x), SIMD3(r[0].y, r[1].y, r[2].y), SIMD3(r[0].z, r[1].z, r[2].z)]
        XCTAssertEqual(WristPointing.pointing(rows: r, axesAreRows: true, axisSign: 1),
                       WristPointing.pointing(rows: transposed, axesAreRows: false, axisSign: 1))
    }

    func testConventionDetectedFromGravity() {
        // x axis 45° up toward north: gravity in the device frame has a negative x part.
        let s = sqrt(0.5)
        let r = rows(x: SIMD3(s, 0, s), y: SIMD3(0, 1, 0), z: SIMD3(-s, 0, s))
        XCTAssertEqual(WristPointing.axesAreRows(rows: r, gravity: SIMD3(-s, 0, -s)), true)
        // Lying flat: can't tell.
        XCTAssertNil(WristPointing.axesAreRows(rows: r, gravity: SIMD3(0, 0, -1)))
    }

    func testGravityFallbackUsesHeadingAndTilt() {
        // Crown toward the hand, arm tilted 30° up: gravity has x = -sin 30°.
        let g = SIMD3(-0.5, 0, -sqrt(0.75))
        let dir = WristPointing.direction(of: WristPointing.pointing(gravity: g, headingOfTop: 10, axisSign: 1))
        XCTAssertEqual(dir.azimuth, 100, accuracy: 0.001)
        XCTAssertEqual(dir.elevation, 30, accuracy: 0.001)
    }

    func testDeclinationTurnsMagneticIntoTrue() {
        let magnetic = SkyProjector.direction(azimuth: 80, elevation: 25)
        let dir = WristPointing.direction(of: WristPointing.rotateAzimuth(magnetic, by: -6))
        XCTAssertEqual(dir.azimuth, 74, accuracy: 0.001)
        XCTAssertEqual(dir.elevation, 25, accuracy: 0.001)
    }

    func testGuidanceTellsYouWhichWayToMove() {
        let pointing = SkyProjector.direction(azimuth: 350, elevation: 20)
        let target = SkyProjector.direction(azimuth: 30, elevation: 20)
        let g = WristPointing.guidance(pointing: pointing, target: target)
        XCTAssertEqual(g.turn, 40, accuracy: 0.001)
        XCTAssertEqual(g.raise, 0, accuracy: 0.001)
        XCTAssertEqual(g.arrowAngle, 90, accuracy: 0.5)
        XCTAssertFalse(g.isOnTarget)

        let up = WristPointing.guidance(pointing: SkyProjector.direction(azimuth: 30, elevation: 10),
                                        target: SkyProjector.direction(azimuth: 30, elevation: 15))
        XCTAssertEqual(up.arrowAngle, 0, accuracy: 0.5)
        XCTAssertTrue(up.isOnTarget)
    }

    func testFacingAndLevelAreJudgedSeparately() {
        // Right direction, arm too low.
        let low = WristPointing.guidance(pointing: SkyProjector.direction(azimuth: 120, elevation: 10),
                                         target: SkyProjector.direction(azimuth: 123, elevation: 40))
        XCTAssertTrue(low.isFacing)
        XCTAssertFalse(low.isLevel)
        XCTAssertFalse(low.isOnTarget)
        guard case .raise = WristPointing.cue(for: low) else { return XCTFail("expected raise") }

        // Right height, wrong direction.
        let wide = WristPointing.guidance(pointing: SkyProjector.direction(azimuth: 60, elevation: 40),
                                          target: SkyProjector.direction(azimuth: 120, elevation: 40))
        XCTAssertFalse(wide.isFacing)
        XCTAssertTrue(wide.isLevel)
        guard case .warmer = WristPointing.cue(for: wide) else { return XCTFail("expected warmer") }

        // Too high.
        let high = WristPointing.guidance(pointing: SkyProjector.direction(azimuth: 120, elevation: 70),
                                          target: SkyProjector.direction(azimuth: 120, elevation: 40))
        guard case .lower = WristPointing.cue(for: high) else { return XCTFail("expected lower") }

        let on = WristPointing.guidance(pointing: SkyProjector.direction(azimuth: 121, elevation: 41),
                                        target: SkyProjector.direction(azimuth: 120, elevation: 40))
        XCTAssertEqual(WristPointing.cue(for: on), .onTarget)
    }

    func testSidewaysMissShrinksNearTheZenith() {
        // 30° of azimuth at 80° up is only ~5° of arm swing.
        let g = WristPointing.guidance(pointing: SkyProjector.direction(azimuth: 0, elevation: 80),
                                       target: SkyProjector.direction(azimuth: 30, elevation: 80))
        XCTAssertEqual(g.turn, 30, accuracy: 0.001)
        XCTAssertLessThan(abs(g.sideways), 6)
        XCTAssertTrue(g.isFacing)
    }

    func testClicksSpeedUpAsYouGetCloser() throws {
        let far = try XCTUnwrap(WristPointing.clickInterval(forError: 100))
        let near = try XCTUnwrap(WristPointing.clickInterval(forError: 15))
        XCTAssertLessThan(near, far)
        XCTAssertNil(WristPointing.clickInterval(forError: 5))
    }

    func testTargetSitsAboveTheHorizonAtTheAircraftsBearing() {
        let contact = RadarContact(flight: TestTraffic.flight("a", miles: 2, bearing: 135), observer: TestTraffic.observer, at: Date())
        let dir = WristPointing.direction(of: WristPointing.target(for: contact))
        XCTAssertEqual(dir.azimuth, 135, accuracy: 1)
        XCTAssertGreaterThan(dir.elevation, 30) // 10,000 ft at 2 mi is high in the sky
    }
}

final class WatchSyncTests: XCTestCase {
    private let context = WatchSync.Context(latitude: 33.749, longitude: -84.388, placeName: "Atlanta, GA",
                                            showHelicopters: false, overheadAlerts: true, overheadAlertMiles: 2,
                                            notableAlerts: false, sentAt: Date(timeIntervalSince1970: 1_800_000_000))

    func testContextRoundTrips() throws {
        let decoded = try XCTUnwrap(WatchSync.decodeContext(WatchSync.encode(context)))
        XCTAssertEqual(decoded, context)
        XCTAssertEqual(decoded.observer?.latitude, 33.749)
    }

    func testNewerVersionIsIgnored() throws {
        var future = context
        future.v = WatchSync.Context.currentVersion + 1
        XCTAssertNil(WatchSync.decodeContext(WatchSync.encode(future)))
        XCTAssertNil(WatchSync.decodeContext(["something": "else"]))
    }

    func testMatchIgnoresSendTime() {
        var later = context
        later.sentAt = later.sentAt.addingTimeInterval(60)
        XCTAssertTrue(later.matches(context))
        later.showHelicopters = true
        XCTAssertFalse(later.matches(context))
        XCTAssertFalse(context.matches(nil))
    }

    func testReplyRoundTrips() {
        let reply = WatchSync.Reply(ok: true, message: "Sky Watch is on")
        XCTAssertEqual(WatchSync.decodeReply(WatchSync.encode(reply)), reply)
    }
}

final class TrafficNotificationTests: XCTestCase {
    func testFlightTravelsAsJSONString() throws {
        let contact = RadarContact(flight: TestTraffic.flight("a", miles: 2, bearing: 45, track: 225, speed: 300),
                                   observer: TestTraffic.observer, at: Date())
        let json = String(decoding: try JSONEncoder().encode(SnapshotFlight(contact)), as: UTF8.self)
        let decoded = try XCTUnwrap(TrafficNotification.flight(from: [TrafficNotification.flightKey: json]))
        XCTAssertEqual(decoded.id, "a")
        XCTAssertNotNil(decoded.closestPassSeconds)
        XCTAssertNil(TrafficNotification.flight(from: [:]))
    }
}

final class ComplicationTimelineTests: XCTestCase {
    func testProjectionMovesAircraftAlongTheirTrack() throws {
        let start = Date()
        // 3 mi north, flying south at 360 kt (≈6.9 mi/min): overhead in about half a minute.
        let flight = TestTraffic.flight("a", miles: 3, bearing: 0, track: 180, speed: 360, at: start)
        let snapshots = NearbyTraffic.projectedSnapshots([flight], observer: TestTraffic.observer, radiusMiles: 10,
                                                         placeName: "Here", start: start, count: 4, step: 60)
        XCTAssertEqual(snapshots.count, 4)
        XCTAssertEqual(snapshots.map(\.date), (0..<4).map { start.addingTimeInterval(Double($0) * 60) })
        let first = try XCTUnwrap(snapshots[0].flights.first)
        let second = try XCTUnwrap(snapshots[1].flights.first)
        XCTAssertEqual(first.bearing, 0, accuracy: 1)
        XCTAssertEqual(second.bearing, 180, accuracy: 1) // passed overhead, now to the south
        XCTAssertGreaterThan(second.distanceMiles, 3)
    }

    func testAircraftLeavingTheRadiusDropOut() {
        let start = Date()
        let flight = TestTraffic.flight("a", miles: 8, bearing: 90, track: 90, speed: 480, at: start)
        let snapshots = NearbyTraffic.projectedSnapshots([flight], observer: TestTraffic.observer, radiusMiles: 10,
                                                         placeName: nil, start: start, count: 3, step: 60)
        XCTAssertEqual(snapshots[0].inRangeCount, 1)
        XCTAssertEqual(snapshots[2].inRangeCount, 0)
    }
}

final class SmallScreenPerimeterTests: XCTestCase {
    func testWatchCapKeepsTheNearestAndSpacesThem() {
        let flights = (0..<20).map { TestTraffic.flight("f\($0)", miles: 1 + Double($0) * 0.4, bearing: Double($0) * 7) }
        let contacts = TestTraffic.contacts(flights)
        let track = PerimeterTrack(rect: CGRect(x: 13, y: 13, width: 136, height: 171), cornerRadius: 26)
        let obstacles = [PerimeterTrack.Corner.topLeft, .topRight, .bottomLeft, .bottomRight]
            .map { PerimeterTrack.Obstacle(s: track.arcLength(of: $0), halfWidth: 14) }
        let scale: CGFloat = 0.62
        let placements = PerimeterPlanner.plan(contacts: contacts, heading: 0, track: track, obstacles: obstacles,
                                               scale: scale, maxIcons: 8)
        XCTAssertEqual(placements.map(\.id), contacts.prefix(8).map(\.id))
        let s = placements.map { track.arcLength(forScreenAngle: GeoMath.normalize(atan2(Double($0.point.x - track.center.x), Double(track.center.y - $0.point.y)).degrees)) }
        for i in 0..<s.count {
            for j in (i + 1)..<s.count {
                XCTAssertGreaterThanOrEqual(abs(track.delta(from: s[i], to: s[j])), PerimeterPlanner.iconSpacing * scale - 1)
            }
        }
    }
}

final class IdentifyTests: XCTestCase {
    private func contact(_ id: String, miles: Double, bearing: Double, altitude: Int = 30_000) -> RadarContact {
        var f = TestTraffic.flight(id, miles: miles, bearing: bearing)
        f.altitudeFeet = altitude
        return RadarContact(flight: f, observer: TestTraffic.observer, at: Date())
    }

    private func arm(at c: RadarContact, offsetAzimuth: Double = 0, offsetElevation: Double = 0) -> SIMD3<Double> {
        let dir = WristPointing.direction(of: WristPointing.target(for: c))
        return SkyProjector.direction(azimuth: dir.azimuth + offsetAzimuth, elevation: dir.elevation + offsetElevation)
    }

    func testPicksWhatTheArmPointsAtBestFirst() {
        let a = contact("a", miles: 8, bearing: 90)
        let b = contact("b", miles: 9, bearing: 96)
        let far = contact("far", miles: 14, bearing: 270)
        let found = WristPointing.candidates(pointing: arm(at: a, offsetAzimuth: 1), contacts: [far, b, a])
        XCTAssertEqual(found.map(\.id), ["a", "b"])
        XCTAssertLessThan(found[0].error, 2)
    }

    func testIgnoresBeyondRangeAndBelowTheHorizonCutoff() {
        let tooFar = contact("tooFar", miles: 16, bearing: 0)
        let tooLow = contact("tooLow", miles: 14, bearing: 180, altitude: 1_500)
        XCTAssertTrue(WristPointing.candidates(pointing: arm(at: tooFar), contacts: [tooFar]).isEmpty)
        XCTAssertTrue(WristPointing.candidates(pointing: arm(at: tooLow), contacts: [tooLow]).isEmpty)
        XCTAssertTrue(WristPointing.candidates(pointing: arm(at: contact("x", miles: 5, bearing: 0), offsetAzimuth: 40),
                                               contacts: [contact("x", miles: 5, bearing: 0)]).isEmpty)
    }

    func testNamesOnlyAfterAHoldThenKeepsTheName() {
        var tracker = IdentifyTracker()
        let t0 = Date()
        let a = WristPointing.Candidate(id: "a", error: 4)
        let b = WristPointing.Candidate(id: "b", error: 2)
        XCTAssertEqual(tracker.update([a], now: t0), .acquiring("a"))
        XCTAssertNil(tracker.update([a], now: t0.addingTimeInterval(0.3)))
        XCTAssertEqual(tracker.update([a], now: t0.addingTimeInterval(0.6)), .named("a"))
        // A slightly better neighbour doesn't steal it while "a" stays in the keep cone.
        XCTAssertNil(tracker.update([b, WristPointing.Candidate(id: "a", error: 12)], now: t0.addingTimeInterval(0.7)))
        XCTAssertEqual(tracker.currentID, "a")
        // "a" leaves: "b" has to earn its own hold.
        XCTAssertEqual(tracker.update([b], now: t0.addingTimeInterval(0.8)), .acquiring("b"))
        XCTAssertEqual(tracker.update([], now: t0.addingTimeInterval(0.9)), .lost)
        XCTAssertNil(tracker.update([], now: t0.addingTimeInterval(1.0)))
    }

    func testCrownPreferenceSwitchesStraightAway() {
        var tracker = IdentifyTracker()
        let t0 = Date()
        let a = WristPointing.Candidate(id: "a", error: 2), b = WristPointing.Candidate(id: "b", error: 6)
        _ = tracker.update([a, b], now: t0)
        _ = tracker.update([a, b], now: t0.addingTimeInterval(0.6))
        tracker.preferredID = "b"
        XCTAssertEqual(tracker.update([a, b], now: t0.addingTimeInterval(0.7)), .named("b"))
        XCTAssertTrue(tracker.isLocked)
    }

    func testSpokenIdentificationReadsNaturally() {
        var f = TestTraffic.flight("x", miles: 8, bearing: 225)
        f.flightNumber = "DL570"; f.callsign = "DAL570"; f.airlineICAO = "DAL"
        f.originIATA = "SFO"; f.destinationIATA = "ATL"; f.typeCode = "B752"; f.altitudeFeet = 30_040
        let sentence = SpokenTraffic.identification(for: RadarContact(flight: f, observer: TestTraffic.observer, at: Date()))
        XCTAssertTrue(sentence.hasPrefix("Delta Air Lines flight 570, San Francisco to Atlanta."), sentence)
        XCTAssertTrue(sentence.contains("30,000 feet, 8 miles southwest"), sentence)
    }
}

final class ScreenTurnTests: XCTestCase {
    func testArmRaisedPalmDownPutsTheTopTowardTheHand() {
        // Left wrist, crown toward the hand: the hand is +x. Arm raised 30°.
        let g = SIMD3(-0.5, 0, -0.866)
        XCTAssertEqual(WristPointing.screenTurn(gravity: g, displaySign: 1, current: .upright), .clockwise)
        // Same pose, screen shown turned round (crown on the other side): the hand is now -x on screen.
        XCTAssertEqual(WristPointing.screenTurn(gravity: SIMD3(0.5, 0, -0.866), displaySign: -1, current: .upright), .clockwise)
    }

    func testThumbUpReadsUprightAlongTheArm() {
        let g = SIMD3(-0.2, -0.95, -0.1) // 12 o'clock edge up
        XCTAssertEqual(WristPointing.screenTurn(gravity: g, displaySign: 1, current: .clockwise), .upright)
        XCTAssertEqual(WristPointing.screenTurn(gravity: -g, displaySign: 1, current: .clockwise), .upsideDown)
    }

    func testFlatScreenKeepsWhatItHas() {
        XCTAssertEqual(WristPointing.screenTurn(gravity: SIMD3(0.05, 0.1, -0.99), displaySign: 1, current: .anticlockwise), .anticlockwise)
    }

    func testNoFlickerBetweenNearlyEqualEdges() {
        // Right edge slightly higher than the top: not enough to leave "upright".
        let g = SIMD3(-0.6, -0.5, -0.62)
        XCTAssertEqual(WristPointing.screenTurn(gravity: g, displaySign: 1, current: .upright), .upright)
    }

    func testDefaultsAndDisplaySign() {
        XCTAssertEqual(WristPointing.handTurn(leftWrist: true), .clockwise)
        XCTAssertEqual(WristPointing.handTurn(leftWrist: false), .anticlockwise)
        // Left wrist, crown toward the elbow ("upside down"): arm is -x, and so is the hand on screen.
        let sign = WristPointing.axisSign(leftWrist: true, crownOnRight: false)
        XCTAssertEqual(WristPointing.displaySign(leftWrist: true, axisSign: sign), -1)
        XCTAssertEqual(WristPointing.ScreenTurn.clockwise.reversed, .anticlockwise)
    }
}

final class AimStyleTests: XCTestCase {
    func testTopEdgeIsTheSightLine() {
        // Held like you're reading it, facing north: the top edge points north and 45° up,
        // the screen faces back toward you, x (the crown) points east.
        let s = sqrt(0.5)
        let rows = [SIMD3(0, -1, 0), SIMD3(s, 0, s), SIMD3(-s, 0, s)] // x, y, z in north-west-up
        let dir = WristPointing.direction(of: WristPointing.sightLine(rows: rows, axesAreRows: true, displaySign: 1))
        XCTAssertEqual(dir.azimuth, 0, accuracy: 0.001)
        XCTAssertEqual(dir.elevation, 45, accuracy: 0.001)
        // Screen shown turned round (crown on the other side): the screen's top is Core Motion's -y.
        let flipped = [SIMD3(0, 1, 0), SIMD3(-s, 0, -s), SIMD3(-s, 0, s)]
        let dir2 = WristPointing.direction(of: WristPointing.sightLine(rows: flipped, axesAreRows: true, displaySign: -1))
        XCTAssertEqual(dir2.azimuth, 0, accuracy: 0.001)
        XCTAssertEqual(dir2.elevation, 45, accuracy: 0.001)
    }

    func testCompassFallbackUsesTiltOfTheTopEdge() {
        // Top edge tilted 30° up: gravity has y = -sin 30°.
        let g = SIMD3(0, -0.5, -sqrt(0.75))
        let dir = WristPointing.direction(of: WristPointing.sightLine(gravity: g, headingOfTop: 250, displaySign: 1))
        XCTAssertEqual(dir.azimuth, 250, accuracy: 0.001)
        XCTAssertEqual(dir.elevation, 30, accuracy: 0.001)
    }
}
