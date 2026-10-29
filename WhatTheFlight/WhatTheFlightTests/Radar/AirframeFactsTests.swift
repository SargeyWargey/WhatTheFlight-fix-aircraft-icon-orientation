//
//  AirframeFactsTests.swift
//  WhatTheFlightTests
//
//  Airframe facts from adsbdb, and keeping private owners private (Enhancements Spec C5).
//

import XCTest
@testable import WhatTheFlight

final class AirframeFactsTests: XCTestCase {
    func testParsesAnAdsbdbAnswer() throws {
        let json = """
        {"response":{"aircraft":{"type":"717 231","icao_type":"B712","manufacturer":"Boeing","mode_s":"A7E509","registration":"N608AT",
         "registered_owner_country_iso_name":"US","registered_owner_country_name":"United States","registered_owner_operator_flag_code":"DAL",
         "registered_owner":"Delta Air Lines"}}}
        """
        let facts = try XCTUnwrap(AirframeFacts.parseAdsbdb(Data(json.utf8)))
        XCTAssertEqual(facts.title, "Boeing 717-231")
        XCTAssertEqual(facts.owner, "Delta Air Lines")
        XCTAssertEqual(facts.ownerCountryISO, "US")
        XCTAssertNil(facts.yearBuilt)
    }

    func testUnknownAircraftIsNil() {
        XCTAssertNil(AirframeFacts.parseAdsbdb(Data(#"{"response":"unknown aircraft"}"#.utf8)))
    }

    func testPrivateOwnersAreNeverShown() {
        let json = #"{"response":{"aircraft":{"type":"172S","manufacturer":"CESSNA","registered_owner":"SMITH JOHN A"}}}"#
        let facts = AirframeFacts.parseAdsbdb(Data(json.utf8))
        XCTAssertNil(facts?.owner)
        XCTAssertEqual(facts?.title, "Cessna 172S")
    }

    func testOrganisations() {
        XCTAssertTrue(AirframeFacts.isOrganisation("WELLS FARGO TRUST CO NA TRUSTEE"))
        XCTAssertTrue(AirframeFacts.isOrganisation("NetJets Sales Inc"))
        XCTAssertTrue(AirframeFacts.isOrganisation("United States Air Force"))
        XCTAssertFalse(AirframeFacts.isOrganisation("DOE JANE"))
        XCTAssertFalse(AirframeFacts.isOrganisation("MARY ANN SMITH"))
        XCTAssertEqual(AirframeFacts.tidyName("SOUTHWEST AIRLINES CO"), "Southwest Airlines Co")
        XCTAssertEqual(AirframeFacts.tidyName("ACME LEASING LLC"), "Acme Leasing LLC")
    }
}
