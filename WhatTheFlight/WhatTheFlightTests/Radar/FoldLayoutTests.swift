//
//  FoldLayoutTests.swift
//  WhatTheFlightTests
//

import XCTest
import CoreGraphics
@testable import WhatTheFlight

final class FoldLayoutTests: XCTestCase {
    /// The Duo's inner screen held as a book, and the fold strip the simulator reports for it.
    private let bookScreen = CGSize(width: 951, height: 669)
    private let bookStrip = CGRect(x: 455.5, y: 0, width: 40, height: 669)
    /// The same screen turned for tabletop.
    private let tabletopScreen = CGSize(width: 669, height: 951)
    private let tabletopStrip = CGRect(x: 0, y: 455.5, width: 669, height: 40)

    // MARK: Posture

    func testNoFoldOnThisScreenIsNeverSplit() {
        // Folded shut the app is on the cover screen, which has no strip, whatever the hinge says.
        for hinge in [HingeStatus.unknown, .closed, .partiallyOpen, .fullyOpen] {
            XCTAssertEqual(FoldLayout.posture(hinge: hinge, division: nil), .none)
        }
        XCTAssertEqual(FoldLayout.posture(hinge: nil, division: bookStrip), .none)
    }

    func testHalfOpenPostureFollowsTheWayTheFoldRuns() {
        XCTAssertEqual(FoldLayout.posture(hinge: .partiallyOpen, division: bookStrip), .book)
        XCTAssertEqual(FoldLayout.posture(hinge: .partiallyOpen, division: tabletopStrip), .tabletop)
    }

    func testOpenFlatAndShutAreNotHalfOpen() {
        XCTAssertEqual(FoldLayout.posture(hinge: .fullyOpen, division: bookStrip), .flat)
        XCTAssertEqual(FoldLayout.posture(hinge: .closed, division: bookStrip), .none)
        XCTAssertFalse(FoldPosture.flat.isHalfOpen)
        XCTAssertFalse(FoldPosture.none.isHalfOpen)
        XCTAssertTrue(FoldPosture.book.isHalfOpen)
        XCTAssertTrue(FoldPosture.tabletop.isHalfOpen)
    }

    // MARK: Split

    func testBookPutsTheRadarOnTheLeftPageAndTheMapOnTheRight() throws {
        let split = try XCTUnwrap(FoldLayout.split(.book, size: bookScreen, division: bookStrip))
        XCTAssertEqual(split.radar, CGRect(x: 0, y: 0, width: 455.5, height: 669))
        XCTAssertEqual(split.map, CGRect(x: 495.5, y: 0, width: 455.5, height: 669))
        XCTAssertEqual(split.gutter, bookStrip)
        // Half the screen each.
        XCTAssertEqual(split.radar.width, split.map.width)
    }

    func testTabletopPutsTheRadarOnTheStandingHalfAndTheMapOnTheTable() throws {
        let split = try XCTUnwrap(FoldLayout.split(.tabletop, size: tabletopScreen, division: tabletopStrip))
        XCTAssertEqual(split.radar, CGRect(x: 0, y: 0, width: 669, height: 455.5))
        XCTAssertEqual(split.map, CGRect(x: 0, y: 495.5, width: 669, height: 455.5))
        XCTAssertEqual(split.gutter, tabletopStrip)
    }

    func testPanesNeverOverlapTheStripOrEachOther() throws {
        for (posture, size, strip) in [(FoldPosture.book, bookScreen, bookStrip), (.tabletop, tabletopScreen, tabletopStrip)] {
            let split = try XCTUnwrap(FoldLayout.split(posture, size: size, division: strip))
            XCTAssertFalse(split.radar.intersects(split.gutter.insetBy(dx: 0.01, dy: 0.01)))
            XCTAssertFalse(split.map.intersects(split.gutter.insetBy(dx: 0.01, dy: 0.01)))
            XCTAssertFalse(split.radar.intersects(split.map))
            // Together they cover the whole screen.
            XCTAssertEqual(split.radar.union(split.gutter).union(split.map), CGRect(origin: .zero, size: size))
        }
    }

    func testAShortStripStillRunsTheFullLengthOfTheFold() throws {
        let partial = CGRect(x: 455.5, y: 100, width: 40, height: 300)
        let split = try XCTUnwrap(FoldLayout.split(.book, size: bookScreen, division: partial))
        XCTAssertEqual(split.gutter, bookStrip)
        XCTAssertEqual(split.radar.height, 669)
    }

    func testWithoutAStripTheScreenSplitsDownTheMiddle() throws {
        let split = try XCTUnwrap(FoldLayout.split(.book, size: CGSize(width: 1000, height: 600), division: nil))
        XCTAssertEqual(split.gutter, CGRect(x: 480, y: 0, width: 40, height: 600))
        XCTAssertEqual(split.radar.width, 480)
        XCTAssertEqual(split.map.width, 480)
        let across = try XCTUnwrap(FoldLayout.split(.tabletop, size: CGSize(width: 600, height: 1000), division: nil))
        XCTAssertEqual(across.radar, CGRect(x: 0, y: 0, width: 600, height: 480))
        XCTAssertEqual(across.map, CGRect(x: 0, y: 520, width: 600, height: 480))
    }

    func testAStripThatWouldLeaveACrampedHalfIsIgnored() throws {
        let nearEdge = CGRect(x: 60, y: 0, width: 40, height: 669)
        let split = try XCTUnwrap(FoldLayout.split(.book, size: bookScreen, division: nearEdge))
        XCTAssertEqual(split.gutter.midX, bookScreen.width / 2)
        let offScreen = CGRect(x: 2000, y: 0, width: 40, height: 669)
        XCTAssertEqual(try XCTUnwrap(FoldLayout.split(.book, size: bookScreen, division: offScreen)).gutter.midX,
                       bookScreen.width / 2)
    }

    func testOnlyHalfOpenPosturesSplit() {
        XCTAssertNil(FoldLayout.split(.flat, size: bookScreen, division: bookStrip))
        XCTAssertNil(FoldLayout.split(.none, size: bookScreen, division: bookStrip))
        XCTAssertNil(FoldLayout.split(.book, size: .zero, division: bookStrip))
    }

    // MARK: Orientation against the body

    func testInnerScreenHeldAsABookIsPortraitToTheBody() {
        // What the simulator reports for the book pose: device portrait, interface landscapeLeft.
        XCTAssertEqual(FoldLayout.bodyTurn(screenTurn: .landscapeLeft, onInnerScreen: true), .portrait)
    }

    func testInnerScreenTurnsWithTheBody() {
        // Turned a quarter clockwise, the body is landscapeLeft and the panel upside down.
        XCTAssertEqual(FoldLayout.bodyTurn(screenTurn: .portraitUpsideDown, onInnerScreen: true), .landscapeLeft)
        XCTAssertEqual(FoldLayout.bodyTurn(screenTurn: .portrait, onInnerScreen: true), .landscapeRight)
        XCTAssertEqual(FoldLayout.bodyTurn(screenTurn: .landscapeRight, onInnerScreen: true), .portraitUpsideDown)
    }

    func testEveryOtherScreenAlreadyMatchesTheBody() {
        for turn in ScreenTurn.allCases {
            XCTAssertEqual(FoldLayout.bodyTurn(screenTurn: turn, onInnerScreen: false), turn)
        }
    }

    func testScreenTurnsWrapBothWays() {
        XCTAssertEqual(ScreenTurn.landscapeRight.turned(by: 1), .portrait)
        XCTAssertEqual(ScreenTurn.portrait.turned(by: -1), .landscapeRight)
        XCTAssertEqual(ScreenTurn.landscapeLeft.turned(by: 6), .landscapeRight)
    }
}
