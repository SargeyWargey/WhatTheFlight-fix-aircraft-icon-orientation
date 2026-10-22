//
//  SilhouetteTests.swift
//  WhatTheFlightTests
//
//  ICAO type code → radar silhouette.
//

import XCTest
@testable import WhatTheFlight

final class SilhouetteTests: XCTestCase {
    func testCommonTypesGetTheirShape() {
        let expected: [String: AircraftSilhouette] = [
            "B738": .airliner, "A21N": .airliner, "B752": .airliner, "P8": .airliner,
            "B77W": .widebody, "B789": .widebody, "A359": .widebody, "KC46": .widebody,
            "B748": .fourEngine, "A388": .fourEngine, "K35R": .fourEngine, "B52": .fourEngine,
            "CRJ9": .regional, "E75L": .regional, "MD88": .regional, "B712": .regional,
            "GLF6": .bizjet, "C68A": .bizjet, "PC24": .bizjet,
            "AT76": .twinProp, "DH8D": .twinProp, "BE20": .twinProp, "PA34": .twinProp,
            "C172": .light, "SR22": .light, "C208": .light, "PC12": .light,
            "F16": .fighter, "F35": .fighter, "T38": .fighter,
            "C17": .militaryTransport, "C130": .militaryTransport, "A400": .militaryTransport,
            "EC35": .helicopter, "H60": .helicopter, "R44": .helicopter,
        ]
        for (code, silhouette) in expected {
            XCTAssertEqual(AircraftTypeCatalog.silhouette(forTypeCode: code), silhouette, code)
        }
    }

    func testLookupIgnoresCase() {
        XCTAssertEqual(AircraftTypeCatalog.silhouette(forTypeCode: "c172"), .light)
    }

    func testUnknownOrMissingCodesFallBackToAirliner() {
        XCTAssertEqual(AircraftTypeCatalog.silhouette(forTypeCode: nil), .airliner)
        XCTAssertEqual(AircraftTypeCatalog.silhouette(forTypeCode: ""), .airliner)
        XCTAssertEqual(AircraftTypeCatalog.silhouette(forTypeCode: "ZZZZ"), .airliner)
    }

    func testEveryCodeHasExactlyOneShape() {
        var seen: [String: AircraftSilhouette] = [:]
        for (silhouette, codes) in AircraftTypeCatalog.silhouetteCodes {
            for code in codes {
                if let other = seen[code] {
                    XCTFail("\(code) is listed as both \(other) and \(silhouette)")
                }
                seen[code] = silhouette
                XCTAssertFalse(AircraftTypeCatalog.helicopterCodes.contains(code), "\(code) is also a helicopter")
            }
        }
        XCTAssertNil(AircraftTypeCatalog.silhouetteCodes[.helicopter], "Helicopters come from helicopterCodes")
    }

    func testHelicopterSilhouetteMatchesKind() {
        for code in AircraftTypeCatalog.helicopterCodes {
            XCTAssertEqual(AircraftTypeCatalog.kind(forTypeCode: code), .helicopter)
            XCTAssertEqual(AircraftTypeCatalog.silhouette(forTypeCode: code), .helicopter)
        }
    }

    func testFlightExposesItsSilhouette() {
        var f = TestTraffic.flight("x", miles: 3, type: "A388")
        f.typeCode = "A388"
        XCTAssertEqual(f.silhouette, .fourEngine)
    }
}
