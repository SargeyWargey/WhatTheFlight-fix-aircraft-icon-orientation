//
//  GeographicBoundsTests.swift
//  WhatTheFlightTests
//
//  Created by Kiro on 8/1/25.
//

import XCTest
import CoreLocation
@testable import WhatTheFlight

final class GeographicBoundsTests: XCTestCase {
    
    func testValidBounds() {
        let bounds = GeographicBounds(
            northLatitude: 51.6,
            southLatitude: 51.4,
            eastLongitude: -0.1,
            westLongitude: -0.3
        )
        
        XCTAssertTrue(bounds.isValid)
    }
    
    func testInvalidBoundsLatitudeOrder() {
        let bounds = GeographicBounds(
            northLatitude: 51.4,
            southLatitude: 51.6,
            eastLongitude: -0.1,
            westLongitude: -0.3
        )
        
        XCTAssertFalse(bounds.isValid)
    }
    
    func testInvalidBoundsLongitudeOrder() {
        let bounds = GeographicBounds(
            northLatitude: 51.6,
            southLatitude: 51.4,
            eastLongitude: -0.3,
            westLongitude: -0.1
        )
        
        XCTAssertFalse(bounds.isValid)
    }
    
    func testInvalidLatitudeRange() {
        let bounds = GeographicBounds(
            northLatitude: 91.0,
            southLatitude: 51.4,
            eastLongitude: -0.1,
            westLongitude: -0.3
        )
        
        XCTAssertFalse(bounds.isValid)
    }
    
    func testInvalidLongitudeRange() {
        let bounds = GeographicBounds(
            northLatitude: 51.6,
            southLatitude: 51.4,
            eastLongitude: 181.0,
            westLongitude: -0.3
        )
        
        XCTAssertFalse(bounds.isValid)
    }
    
    func testCenter() {
        let bounds = GeographicBounds(
            northLatitude: 52.0,
            southLatitude: 50.0,
            eastLongitude: 0.0,
            westLongitude: -2.0
        )
        
        let center = bounds.center
        XCTAssertEqual(center.latitude, 51.0, accuracy: 0.001)
        XCTAssertEqual(center.longitude, -1.0, accuracy: 0.001)
    }
    
    func testBoundsString() {
        let bounds = GeographicBounds(
            northLatitude: 51.6,
            southLatitude: 51.4,
            eastLongitude: -0.1,
            westLongitude: -0.3
        )
        
        XCTAssertEqual(bounds.boundsString, "51.6,51.4,-0.3,-0.1")
    }
    
    func testAroundCenter() {
        let center = CLLocationCoordinate2D(latitude: 51.5, longitude: -0.2)
        let bounds = GeographicBounds.around(center: center, radiusKm: 10.0)
        
        XCTAssertTrue(bounds.isValid)
        XCTAssertEqual(bounds.center.latitude, center.latitude, accuracy: 0.01)
        XCTAssertEqual(bounds.center.longitude, center.longitude, accuracy: 0.01)
    }
    
    func testFromCenter() {
        let center = CLLocationCoordinate2D(latitude: 51.5, longitude: -0.2)
        let bounds = GeographicBounds.fromCenter(center)
        
        XCTAssertTrue(bounds.isValid)
        XCTAssertEqual(bounds.center.latitude, center.latitude, accuracy: 0.01)
        XCTAssertEqual(bounds.center.longitude, center.longitude, accuracy: 0.01)
    }
    
    func testContains() {
        let bounds = GeographicBounds(
            northLatitude: 52.0,
            southLatitude: 50.0,
            eastLongitude: 0.0,
            westLongitude: -2.0
        )
        
        let insidePoint = CLLocationCoordinate2D(latitude: 51.0, longitude: -1.0)
        let outsidePoint = CLLocationCoordinate2D(latitude: 53.0, longitude: -1.0)
        
        XCTAssertTrue(bounds.contains(insidePoint))
        XCTAssertFalse(bounds.contains(outsidePoint))
    }
    
    func testValidation() throws {
        let validBounds = GeographicBounds(
            northLatitude: 51.6,
            southLatitude: 51.4,
            eastLongitude: -0.1,
            westLongitude: -0.3
        )
        
        XCTAssertNoThrow(try validBounds.validate())
    }
    
    func testValidationInvalidLatitudeRange() {
        let invalidBounds = GeographicBounds(
            northLatitude: 91.0,
            southLatitude: 51.4,
            eastLongitude: -0.1,
            westLongitude: -0.3
        )
        
        XCTAssertThrowsError(try invalidBounds.validate()) { error in
            XCTAssertTrue(error is GeographicBounds.ValidationError)
            if case GeographicBounds.ValidationError.invalidLatitudeRange = error {
                // Expected error
            } else {
                XCTFail("Expected invalidLatitudeRange error")
            }
        }
    }
    
    func testValidationInvalidLongitudeRange() {
        let invalidBounds = GeographicBounds(
            northLatitude: 51.6,
            southLatitude: 51.4,
            eastLongitude: 181.0,
            westLongitude: -0.3
        )
        
        XCTAssertThrowsError(try invalidBounds.validate()) { error in
            XCTAssertTrue(error is GeographicBounds.ValidationError)
            if case GeographicBounds.ValidationError.invalidLongitudeRange = error {
                // Expected error
            } else {
                XCTFail("Expected invalidLongitudeRange error")
            }
        }
    }
    
    func testValidationInvalidBoundsOrder() {
        let invalidBounds = GeographicBounds(
            northLatitude: 51.4,
            southLatitude: 51.6,
            eastLongitude: -0.1,
            westLongitude: -0.3
        )
        
        XCTAssertThrowsError(try invalidBounds.validate()) { error in
            XCTAssertTrue(error is GeographicBounds.ValidationError)
            if case GeographicBounds.ValidationError.invalidBoundsOrder = error {
                // Expected error
            } else {
                XCTFail("Expected invalidBoundsOrder error")
            }
        }
    }
    
    func testEquality() {
        let bounds1 = GeographicBounds(
            northLatitude: 51.6,
            southLatitude: 51.4,
            eastLongitude: -0.1,
            westLongitude: -0.3
        )
        
        let bounds2 = GeographicBounds(
            northLatitude: 51.6,
            southLatitude: 51.4,
            eastLongitude: -0.1,
            westLongitude: -0.3
        )
        
        let bounds3 = GeographicBounds(
            northLatitude: 52.0,
            southLatitude: 51.4,
            eastLongitude: -0.1,
            westLongitude: -0.3
        )
        
        XCTAssertEqual(bounds1, bounds2)
        XCTAssertNotEqual(bounds1, bounds3)
    }
    
    func testCodable() throws {
        let originalBounds = GeographicBounds(
            northLatitude: 51.6,
            southLatitude: 51.4,
            eastLongitude: -0.1,
            westLongitude: -0.3
        )
        
        let encoded = try JSONEncoder().encode(originalBounds)
        let decoded = try JSONDecoder().decode(GeographicBounds.self, from: encoded)
        
        XCTAssertEqual(originalBounds, decoded)
    }
}