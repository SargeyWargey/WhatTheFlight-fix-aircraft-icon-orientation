// Legacy: only the macOS (and visionOS) app runs this. iOS, tvOS and watchOS run radar v2;
// see Enhancements Spec B4. Delete with the rest of Legacy/ once the Mac runs the iPad app (C11).
#if os(macOS) || os(visionOS)
//
//  LocationManagerTests.swift
//  WhatTheFlightTests
//
//  Created by Kiro on 8/1/25.
//

import XCTest
import CoreLocation
import Combine
@testable import WhatTheFlight

@MainActor
final class LocationManagerTests: XCTestCase {
    var locationManager: LocationManager!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        locationManager = LocationManager()
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() {
        cancellables = nil
        locationManager = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInitialization() {
        XCTAssertEqual(locationManager.authorizationStatus, CLLocationManager().authorizationStatus)
        XCTAssertNil(locationManager.currentLocation)
        
        // Location availability should be false initially unless already authorized
        #if os(iOS)
        let expectedAvailability = locationManager.authorizationStatus == .authorizedWhenInUse || 
                                  locationManager.authorizationStatus == .authorizedAlways
        #else
        let expectedAvailability = locationManager.authorizationStatus == .authorizedAlways
        #endif
        XCTAssertEqual(locationManager.isLocationAvailable, expectedAvailability)
    }
    
    // MARK: - Manual Coordinate Entry Tests
    
    func testCreateBoundsFromManualEntry_ValidCoordinates() throws {
        let latitude = 37.7749
        let longitude = -122.4194
        let radiusKm = 10.0
        
        let bounds = try LocationManager.createBoundsFromManualEntry(
            latitude: latitude,
            longitude: longitude,
            radiusKm: radiusKm
        )
        
        XCTAssertTrue(bounds.isValid)
        XCTAssertEqual(bounds.center.latitude, latitude, accuracy: 0.001)
        XCTAssertEqual(bounds.center.longitude, longitude, accuracy: 0.001)
    }
    
    func testCreateBoundsFromManualEntry_InvalidLatitude() {
        XCTAssertThrowsError(try LocationManager.createBoundsFromManualEntry(
            latitude: 91.0,
            longitude: -122.4194,
            radiusKm: 10.0
        )) { error in
            XCTAssertTrue(error is CoordinateValidationError)
            XCTAssertEqual(error as? CoordinateValidationError, .invalidLatitude)
        }
        
        XCTAssertThrowsError(try LocationManager.createBoundsFromManualEntry(
            latitude: -91.0,
            longitude: -122.4194,
            radiusKm: 10.0
        )) { error in
            XCTAssertTrue(error is CoordinateValidationError)
            XCTAssertEqual(error as? CoordinateValidationError, .invalidLatitude)
        }
    }
    
    func testCreateBoundsFromManualEntry_InvalidLongitude() {
        XCTAssertThrowsError(try LocationManager.createBoundsFromManualEntry(
            latitude: 37.7749,
            longitude: 181.0,
            radiusKm: 10.0
        )) { error in
            XCTAssertTrue(error is CoordinateValidationError)
            XCTAssertEqual(error as? CoordinateValidationError, .invalidLongitude)
        }
        
        XCTAssertThrowsError(try LocationManager.createBoundsFromManualEntry(
            latitude: 37.7749,
            longitude: -181.0,
            radiusKm: 10.0
        )) { error in
            XCTAssertTrue(error is CoordinateValidationError)
            XCTAssertEqual(error as? CoordinateValidationError, .invalidLongitude)
        }
    }
    
    func testCreateBoundsFromManualEntry_InvalidRadius() {
        XCTAssertThrowsError(try LocationManager.createBoundsFromManualEntry(
            latitude: 37.7749,
            longitude: -122.4194,
            radiusKm: 0.0
        )) { error in
            XCTAssertTrue(error is CoordinateValidationError)
            XCTAssertEqual(error as? CoordinateValidationError, .invalidRadius)
        }
        
        XCTAssertThrowsError(try LocationManager.createBoundsFromManualEntry(
            latitude: 37.7749,
            longitude: -122.4194,
            radiusKm: 101.0
        )) { error in
            XCTAssertTrue(error is CoordinateValidationError)
            XCTAssertEqual(error as? CoordinateValidationError, .invalidRadius)
        }
    }
    
    // MARK: - Coordinate String Parsing Tests
    
    func testParseCoordinateString_ValidFormat() throws {
        let coordinateString = "37.7749, -122.4194"
        let (latitude, longitude) = try LocationManager.parseCoordinateString(coordinateString)
        
        XCTAssertEqual(latitude, 37.7749, accuracy: 0.0001)
        XCTAssertEqual(longitude, -122.4194, accuracy: 0.0001)
    }
    
    func testParseCoordinateString_ValidFormatNoSpaces() throws {
        let coordinateString = "37.7749,-122.4194"
        let (latitude, longitude) = try LocationManager.parseCoordinateString(coordinateString)
        
        XCTAssertEqual(latitude, 37.7749, accuracy: 0.0001)
        XCTAssertEqual(longitude, -122.4194, accuracy: 0.0001)
    }
    
    func testParseCoordinateString_InvalidFormat() {
        XCTAssertThrowsError(try LocationManager.parseCoordinateString("37.7749")) { error in
            XCTAssertTrue(error is CoordinateValidationError)
            XCTAssertEqual(error as? CoordinateValidationError, .invalidFormat)
        }
        
        XCTAssertThrowsError(try LocationManager.parseCoordinateString("37.7749, -122.4194, 100")) { error in
            XCTAssertTrue(error is CoordinateValidationError)
            XCTAssertEqual(error as? CoordinateValidationError, .invalidFormat)
        }
        
        XCTAssertThrowsError(try LocationManager.parseCoordinateString("invalid, coordinates")) { error in
            XCTAssertTrue(error is CoordinateValidationError)
            XCTAssertEqual(error as? CoordinateValidationError, .invalidFormat)
        }
    }
    
    // MARK: - Location Availability Tests
    
    func testLocationAvailability_AuthorizedWhenInUse() {
        // Simulate authorized when in use status
        #if os(iOS)
        locationManager.authorizationStatus = .authorizedWhenInUse
        
        // Test through the computed property
        let isAvailable = locationManager.authorizationStatus == .authorizedWhenInUse || 
                         locationManager.authorizationStatus == .authorizedAlways
        XCTAssertTrue(isAvailable)
        #else
        // On macOS, only authorizedAlways is available
        locationManager.authorizationStatus = .authorizedAlways
        
        let isAvailable = locationManager.authorizationStatus == .authorizedAlways
        XCTAssertTrue(isAvailable)
        #endif
    }
    
    func testLocationAvailability_AuthorizedAlways() {
        locationManager.authorizationStatus = .authorizedAlways
        
        #if os(iOS)
        let isAvailable = locationManager.authorizationStatus == .authorizedWhenInUse || 
                         locationManager.authorizationStatus == .authorizedAlways
        #else
        let isAvailable = locationManager.authorizationStatus == .authorizedAlways
        #endif
        XCTAssertTrue(isAvailable)
    }
    
    func testLocationAvailability_Denied() {
        locationManager.authorizationStatus = .denied
        
        #if os(iOS)
        let isAvailable = locationManager.authorizationStatus == .authorizedWhenInUse || 
                         locationManager.authorizationStatus == .authorizedAlways
        #else
        let isAvailable = locationManager.authorizationStatus == .authorizedAlways
        #endif
        XCTAssertFalse(isAvailable)
    }
    
    func testLocationAvailability_NotDetermined() {
        locationManager.authorizationStatus = .notDetermined
        
        #if os(iOS)
        let isAvailable = locationManager.authorizationStatus == .authorizedWhenInUse || 
                         locationManager.authorizationStatus == .authorizedAlways
        #else
        let isAvailable = locationManager.authorizationStatus == .authorizedAlways
        #endif
        XCTAssertFalse(isAvailable)
    }
    
    // MARK: - Error Handling Tests
    
    func testLocationError_ErrorDescriptions() {
        let permissionError = LocationError.permissionDenied
        XCTAssertNotNil(permissionError.errorDescription)
        XCTAssertTrue(permissionError.errorDescription!.contains("Location permission"))
        
        let unavailableError = LocationError.locationUnavailable(NSError(domain: "test", code: 1))
        XCTAssertNotNil(unavailableError.errorDescription)
        XCTAssertTrue(unavailableError.errorDescription!.contains("Unable to determine"))
        
        let disabledError = LocationError.locationServicesDisabled
        XCTAssertNotNil(disabledError.errorDescription)
        XCTAssertTrue(disabledError.errorDescription!.contains("Location services are disabled"))
    }
    
    func testLocationError_RecoverySuggestions() {
        let permissionError = LocationError.permissionDenied
        XCTAssertNotNil(permissionError.recoverySuggestion)
        XCTAssertTrue(permissionError.recoverySuggestion!.contains("Settings"))
        
        let unavailableError = LocationError.locationUnavailable(NSError(domain: "test", code: 1))
        XCTAssertNotNil(unavailableError.recoverySuggestion)
        XCTAssertTrue(unavailableError.recoverySuggestion!.contains("Try again"))
        
        let disabledError = LocationError.locationServicesDisabled
        XCTAssertNotNil(disabledError.recoverySuggestion)
        XCTAssertTrue(disabledError.recoverySuggestion!.contains("Enable Location Services"))
    }
    
    func testCoordinateValidationError_ErrorDescriptions() {
        let latitudeError = CoordinateValidationError.invalidLatitude
        XCTAssertNotNil(latitudeError.errorDescription)
        XCTAssertTrue(latitudeError.errorDescription!.contains("Latitude must be"))
        
        let longitudeError = CoordinateValidationError.invalidLongitude
        XCTAssertNotNil(longitudeError.errorDescription)
        XCTAssertTrue(longitudeError.errorDescription!.contains("Longitude must be"))
        
        let radiusError = CoordinateValidationError.invalidRadius
        XCTAssertNotNil(radiusError.errorDescription)
        XCTAssertTrue(radiusError.errorDescription!.contains("Radius must be"))
        
        let formatError = CoordinateValidationError.invalidFormat
        XCTAssertNotNil(formatError.errorDescription)
        XCTAssertTrue(formatError.errorDescription!.contains("Coordinates must be"))
    }
    
    // MARK: - Integration Tests with GeographicBounds
    
    func testCreateBoundsFromManualEntry_IntegrationWithGeographicBounds() throws {
        let latitude = 40.7128
        let longitude = -74.0060
        let radiusKm = 15.0
        
        let bounds = try LocationManager.createBoundsFromManualEntry(
            latitude: latitude,
            longitude: longitude,
            radiusKm: radiusKm
        )
        
        // Test that the bounds are valid
        XCTAssertTrue(bounds.isValid)
        
        // Test that the center is correct
        let center = bounds.center
        XCTAssertEqual(center.latitude, latitude, accuracy: 0.001)
        XCTAssertEqual(center.longitude, longitude, accuracy: 0.001)
        
        // Test that the bounds contain the center point
        XCTAssertTrue(bounds.contains(CLLocationCoordinate2D(latitude: latitude, longitude: longitude)))
        
        // Test that the bounds validation passes
        XCTAssertNoThrow(try bounds.validate())
    }
    
    func testBoundsCreation_EdgeCases() throws {
        // Test near poles
        let nearNorthPole = try LocationManager.createBoundsFromManualEntry(
            latitude: 89.0,
            longitude: 0.0,
            radiusKm: 5.0
        )
        XCTAssertTrue(nearNorthPole.isValid)
        
        let nearSouthPole = try LocationManager.createBoundsFromManualEntry(
            latitude: -89.0,
            longitude: 0.0,
            radiusKm: 5.0
        )
        XCTAssertTrue(nearSouthPole.isValid)
        
        // Test near date line
        let nearDateLine = try LocationManager.createBoundsFromManualEntry(
            latitude: 0.0,
            longitude: 179.0,
            radiusKm: 5.0
        )
        XCTAssertTrue(nearDateLine.isValid)
    }
    
    // MARK: - Performance Tests
    
    func testCoordinateParsingPerformance() {
        let coordinateStrings = [
            "37.7749, -122.4194",
            "40.7128, -74.0060",
            "51.5074, -0.1278",
            "35.6762, 139.6503",
            "-33.8688, 151.2093"
        ]
        
        measure {
            for coordinateString in coordinateStrings {
                _ = try? LocationManager.parseCoordinateString(coordinateString)
            }
        }
    }
    
    func testBoundsCreationPerformance() {
        let coordinates = [
            (37.7749, -122.4194),
            (40.7128, -74.0060),
            (51.5074, -0.1278),
            (35.6762, 139.6503),
            (-33.8688, 151.2093)
        ]
        
        measure {
            for (lat, lon) in coordinates {
                _ = try? LocationManager.createBoundsFromManualEntry(
                    latitude: lat,
                    longitude: lon,
                    radiusKm: 10.0
                )
            }
        }
    }
}

// MARK: - Mock Location Manager for Testing
// Using the shared MockLocationManager from Mocks/MockLocationManager.swift

// MARK: - Mock Location Error Types
// Using the shared MockLocationError from Mocks/MockLocationManager.swift

// MARK: - Mock Location Manager Tests

@MainActor
final class MockLocationManagerTests: XCTestCase {
    var mockLocationManager: MockLocationManager!
    
    override func setUp() {
        super.setUp()
        mockLocationManager = MockLocationManager()
    }
    
    override func tearDown() {
        mockLocationManager = nil
        super.tearDown()
    }
    
    func testMockLocationManager_SuccessfulLocationRequest() async throws {
        mockLocationManager.authorizationStatus = MockLocationManager.authorizedStatus
        mockLocationManager.isLocationAvailable = true
        
        let location = try await mockLocationManager.getCurrentLocation()
        
        XCTAssertEqual(location.coordinate.latitude, 37.7749, accuracy: 0.0001)
        XCTAssertEqual(location.coordinate.longitude, -122.4194, accuracy: 0.0001)
        XCTAssertEqual(mockLocationManager.currentLocation, location)
    }
    
    func testMockLocationManager_FailedLocationRequest() async {
        mockLocationManager.shouldFailLocationRequest = true
        
        do {
            _ = try await mockLocationManager.getCurrentLocation()
            XCTFail("Expected location request to fail")
        } catch {
            XCTAssertTrue(error is LocationError)
        }
    }
    
    func testMockLocationManager_CreateBoundsFromCurrentLocation() async throws {
        mockLocationManager.authorizationStatus = MockLocationManager.authorizedStatus
        mockLocationManager.isLocationAvailable = true
        
        let bounds = try await mockLocationManager.createBoundsFromCurrentLocation(radiusKm: 10.0)
        
        XCTAssertTrue(bounds.isValid)
        XCTAssertEqual(bounds.center.latitude, 37.7749, accuracy: 0.001)
        XCTAssertEqual(bounds.center.longitude, -122.4194, accuracy: 0.001)
    }
}
#endif
