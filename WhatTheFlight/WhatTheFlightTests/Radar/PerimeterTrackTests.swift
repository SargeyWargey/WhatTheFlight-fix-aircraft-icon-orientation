//
//  PerimeterTrackTests.swift
//  WhatTheFlightTests
//

import XCTest
import CoreGraphics
@testable import WhatTheFlight

final class PerimeterTrackTests: XCTestCase {
    /// iPhone-ish safe area, inset like the real icon track.
    let track = PerimeterTrack(rect: CGRect(x: 27, y: 27, width: 339, height: 705), cornerRadius: 34)

    func testCardinalAnglesHitTheMiddleOfEachEdge() {
        let up = track.point(forScreenAngle: 0)
        XCTAssertEqual(up.x, track.rect.midX, accuracy: 0.5)
        XCTAssertEqual(up.y, track.rect.minY, accuracy: 0.5)

        let right = track.point(forScreenAngle: 90)
        XCTAssertEqual(right.x, track.rect.maxX, accuracy: 0.5)
        XCTAssertEqual(right.y, track.rect.midY, accuracy: 0.5)

        let down = track.point(forScreenAngle: 180)
        XCTAssertEqual(down.x, track.rect.midX, accuracy: 0.5)
        XCTAssertEqual(down.y, track.rect.maxY, accuracy: 0.5)

        let left = track.point(forScreenAngle: 270)
        XCTAssertEqual(left.x, track.rect.minX, accuracy: 0.5)
        XCTAssertEqual(left.y, track.rect.midY, accuracy: 0.5)
    }

    func testEveryAngleLandsOnTheTrackAndPointsTheRightWay() {
        for angle in stride(from: 0.0, to: 360, by: 7.5) {
            let p = track.point(forScreenAngle: angle)
            // Inside (or on) the rect.
            XCTAssertGreaterThanOrEqual(p.x, track.rect.minX - 0.5)
            XCTAssertLessThanOrEqual(p.x, track.rect.maxX + 0.5)
            XCTAssertGreaterThanOrEqual(p.y, track.rect.minY - 0.5)
            XCTAssertLessThanOrEqual(p.y, track.rect.maxY + 0.5)
            // The ray from the centre really goes that way.
            let measured = GeoMath.normalize(atan2(Double(p.x - track.center.x), Double(track.center.y - p.y)).degrees)
            XCTAssertEqual(GeoMath.shortestDelta(from: angle, to: measured), 0, accuracy: 0.6, "angle \(angle)")
        }
    }

    func testArcLengthIsMonotonicClockwise() {
        var previous: CGFloat = -1
        for angle in stride(from: 0.0, to: 360, by: 1) {
            let s = track.arcLength(forScreenAngle: angle)
            XCTAssertGreaterThan(s, previous)
            previous = s
        }
        XCTAssertLessThanOrEqual(previous, track.length)
    }

    func testCornerMidpointsSitOnTheRoundedCorners() {
        let br = track.point(at: track.arcLength(of: .bottomRight))
        XCTAssertGreaterThan(br.x, track.rect.maxX - track.cornerRadius)
        XCTAssertGreaterThan(br.y, track.rect.maxY - track.cornerRadius)
        let bl = track.point(at: track.arcLength(of: .bottomLeft))
        XCTAssertLessThan(bl.x, track.rect.minX + track.cornerRadius)
        XCTAssertGreaterThan(bl.y, track.rect.maxY - track.cornerRadius)
    }

    func testSpreadSeparatesStackedIcons() {
        let s = track.arcLength(forScreenAngle: 45)
        let spread = track.spread([s, s, s], minGap: 40)
        let sorted = spread.sorted()
        XCTAssertGreaterThanOrEqual(sorted[1] - sorted[0], 39.5)
        XCTAssertGreaterThanOrEqual(sorted[2] - sorted[1], 39.5)
        // Still centred around where they wanted to be.
        XCTAssertEqual(sorted[1], s, accuracy: 3)
    }

    func testSpreadLeavesWellSeparatedIconsAlone() {
        let a = track.arcLength(forScreenAngle: 10)
        let b = track.arcLength(forScreenAngle: 120)
        let spread = track.spread([a, b], minGap: 40)
        XCTAssertEqual(spread[0], a, accuracy: 0.01)
        XCTAssertEqual(spread[1], b, accuracy: 0.01)
    }

    func testSpreadKeepsIconsOffObstacles() {
        let gear = PerimeterTrack.Obstacle(s: track.arcLength(of: .bottomRight), halfWidth: 26)
        let spread = track.spread([gear.s, gear.s + 5], minGap: 40, obstacles: [gear])
        for s in spread {
            XCTAssertGreaterThanOrEqual(abs(track.delta(from: gear.s, to: s)), 26 + 20 - 0.5)
        }
    }

    func testSpreadHandlesWrapAroundTopCentre() {
        // Two icons either side of s = 0 must be pushed apart across the seam, not around the whole loop.
        let spread = track.spread([track.length - 2, 2], minGap: 40)
        XCTAssertGreaterThanOrEqual(abs(track.delta(from: spread[0], to: spread[1])), 39.5)
        XCTAssertLessThan(abs(track.delta(from: spread[0], to: spread[1])), 60)
    }

    func testClusterTowardAnAirportFansOutAroundItsTrueBearing() {
        // A dozen arrivals all lined up toward the same airport.
        let base = track.arcLength(forScreenAngle: 200)
        let desired = (0..<12).map { base + CGFloat($0) * 1.5 }
        let spread = track.spread(desired, minGap: 40)
        let sorted = spread.sorted()
        for i in 1..<sorted.count {
            XCTAssertGreaterThanOrEqual(sorted[i] - sorted[i - 1], 39.9)
        }
        // Order is preserved and the fan stays centred on the cluster.
        XCTAssertEqual(spread, spread.sorted())
        let meanDesired = desired.reduce(0, +) / CGFloat(desired.count)
        let meanSpread = spread.reduce(0, +) / CGFloat(spread.count)
        XCTAssertEqual(meanSpread, meanDesired, accuracy: 0.5)
    }

    func testSpreadSqueezesWhenTheSkyIsFull() {
        let desired = Array(repeating: CGFloat(100), count: 80)
        let spread = track.spread(desired, minGap: 40)
        XCTAssertEqual(spread.count, 80)
        let sorted = spread.sorted()
        let expectedGap = track.length / 80
        for i in 1..<sorted.count {
            XCTAssertGreaterThan(sorted[i] - sorted[i - 1], expectedGap * 0.6)
        }
    }
}
