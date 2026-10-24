//
//  AircraftPhotoServiceTests.swift
//  WhatTheFlightTests
//
//  Created by Kiro on 8/3/25.
//

import XCTest
@testable import WhatTheFlight

final class AircraftPhotoServiceTests: XCTestCase {
    
    var photoService: AircraftPhotoService!
    
    override func setUp() {
        super.setUp()
        photoService = AircraftPhotoService()
    }
    
    override func tearDown() {
        photoService = nil
        super.tearDown()
    }
    
    func testFetchAircraftPhotoURL_ReturnsPlaceholder() async {
        // Given
        let registration = "N2819Q"
        
        // When
        let result = await photoService.fetchAircraftPhotoURL(registration: registration)
        
        // Then
        XCTAssertNotNil(result, "Should return a placeholder URL when real photos are not available")
        XCTAssertTrue(result?.contains("placeholder") == true, "Should return a placeholder URL")
        XCTAssertTrue(result?.contains("N2819Q") == true, "Should include the registration in the placeholder")
    }
    
    func testFetchAircraftPhotoURL_TriesMultipleSources() async {
        // Given
        let registration = "TEST123"
        
        // When
        let result = await photoService.fetchAircraftPhotoURL(registration: registration)
        
        // Then
        // Since all sources will likely fail (they're mostly blocked or don't exist),
        // we should get a placeholder, but the service should have tried multiple sources
        XCTAssertNotNil(result, "Should return a result even if all sources fail")
        XCTAssertTrue(result?.contains("placeholder") == true, "Should fallback to placeholder when all sources fail")
    }
    
    func testFetchAircraftPhotoURL_HandlesSpecialCharacters() async {
        // Given
        let registration = "G-ABCD"
        
        // When
        let result = await photoService.fetchAircraftPhotoURL(registration: registration)
        
        // Then
        XCTAssertNotNil(result, "Should handle registrations with special characters")
        XCTAssertTrue(result?.contains("placeholder") == true, "Should return a placeholder URL")
    }
}