// Legacy: only the macOS (and visionOS) app runs this. iOS, tvOS and watchOS run radar v2;
// see Enhancements Spec B4. Delete with the rest of Legacy/ once the Mac runs the iPad app (C11).
#if os(macOS) || os(visionOS)
//
//  ModelIntegrationTests.swift
//  WhatTheFlightTests
//
//  Created by Kiro on 8/1/25.
//

import XCTest
import CoreLocation
@testable import WhatTheFlight

final class ModelIntegrationTests: XCTestCase {
    
    func testCompleteFlightDataCreation() {
        // Create a complete flight data object with all components
        let airline = AirlineInfo(name: "American Airlines", code: "AA")
        let aircraft = AircraftInfo(model: "Boeing 737-800", code: "B738", registration: "N123AA")
        
        let origin = AirportInfo(name: "Los Angeles International Airport", iataCode: "LAX", city: "Los Angeles")
        let destination = AirportInfo(name: "John F. Kennedy International Airport", iataCode: "JFK", city: "New York")
        let route = RouteInfo(origin: origin, destination: destination)
        
        let position = FlightPosition(
            latitude: 34.0522,
            longitude: -118.2437,
            altitude: 35000,
            speed: 450,
            heading: 90
        )
        
        let flightData = FlightData(
            id: "aa123_20250801",
            flightNumber: "AA123",
            callsign: "AMERICAN123",
            airline: airline,
            aircraft: aircraft,
            route: route,
            position: position
        )
        
        // Verify all components are properly integrated
        XCTAssertEqual(flightData.displayIdentifier, "AA123")
        XCTAssertEqual(flightData.routeDescription, "LAX → JFK")
        XCTAssertEqual(flightData.aircraftDescription, "American Airlines • Boeing 737-800")
        XCTAssertTrue(flightData.position?.isValid ?? false)
        XCTAssertEqual(flightData.position?.altitudeDescription, "35000 ft")
        XCTAssertEqual(flightData.position?.speedDescription, "450 kts")
    }
    
    func testGeographicBoundsWithFlightPosition() {
        // Create bounds around LAX airport
        let laxCoordinate = CLLocationCoordinate2D(latitude: 33.9425, longitude: -118.4081)
        let bounds = GeographicBounds.fromCenter(laxCoordinate, radiusKm: 50.0)
        
        // Create a flight position within the bounds
        let flightPosition = FlightPosition(latitude: 33.95, longitude: -118.40)
        let flightCoordinate = CLLocationCoordinate2D(
            latitude: flightPosition.latitude,
            longitude: flightPosition.longitude
        )
        
        XCTAssertTrue(bounds.isValid)
        XCTAssertTrue(bounds.contains(flightCoordinate))
        XCTAssertTrue(flightPosition.isValid)
    }
    
    func testDisplayPreferencesDefaults() {
        let preferences = DisplayPreferences.default
        
        XCTAssertEqual(preferences.textSize, .medium)
        XCTAssertEqual(preferences.colorTheme, .system)
        XCTAssertEqual(preferences.informationDensity, .normal)
        XCTAssertTrue(preferences.animationsEnabled)
        XCTAssertTrue(preferences.showAltitude)
        XCTAssertTrue(preferences.showSpeed)
        XCTAssertFalse(preferences.showHeading)
    }
    
    func testNotificationSettingsDefaults() {
        let settings = NotificationSettings.default
        
        XCTAssertTrue(settings.flightDetectionEnabled)
        XCTAssertFalse(settings.connectionStatusEnabled)
        XCTAssertTrue(settings.errorAlertsEnabled)
        XCTAssertTrue(settings.soundEnabled)
        XCTAssertFalse(settings.badgeEnabled)
        XCTAssertTrue(settings.hasNotificationsEnabled)
    }
    
    func testAllModelsCodable() throws {
        // Test that all models can be encoded and decoded
        let airline = AirlineInfo(name: "Test Airline", code: "TA")
        let aircraft = AircraftInfo(model: "Test Aircraft", code: "TEST")
        let origin = AirportInfo(name: "Test Origin", iataCode: "TST")
        let destination = AirportInfo(name: "Test Destination", iataCode: "TSD")
        let route = RouteInfo(origin: origin, destination: destination)
        let position = FlightPosition(latitude: 0.0, longitude: 0.0)
        
        let flightData = FlightData(
            id: "test",
            flightNumber: "TEST123",
            airline: airline,
            aircraft: aircraft,
            route: route,
            position: position
        )
        
        let bounds = GeographicBounds(
            northLatitude: 1.0,
            southLatitude: -1.0,
            eastLongitude: 1.0,
            westLongitude: -1.0
        )
        
        let displayPrefs = DisplayPreferences()
        let notificationSettings = NotificationSettings()
        
        // Test encoding/decoding
        let flightEncoded = try JSONEncoder().encode(flightData)
        let flightDecoded = try JSONDecoder().decode(FlightData.self, from: flightEncoded)
        XCTAssertEqual(flightData, flightDecoded)
        
        let boundsEncoded = try JSONEncoder().encode(bounds)
        let boundsDecoded = try JSONDecoder().decode(GeographicBounds.self, from: boundsEncoded)
        XCTAssertEqual(bounds, boundsDecoded)
        
        let prefsEncoded = try JSONEncoder().encode(displayPrefs)
        let prefsDecoded = try JSONDecoder().decode(DisplayPreferences.self, from: prefsEncoded)
        XCTAssertEqual(displayPrefs, prefsDecoded)
        
        let notifEncoded = try JSONEncoder().encode(notificationSettings)
        let notifDecoded = try JSONDecoder().decode(NotificationSettings.self, from: notifEncoded)
        XCTAssertEqual(notificationSettings, notifDecoded)
    }
}
#endif
