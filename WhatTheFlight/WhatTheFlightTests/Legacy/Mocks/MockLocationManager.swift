// Legacy: only the macOS (and visionOS) app runs this. iOS, tvOS and watchOS run radar v2;
// see Enhancements Spec B4. Delete with the rest of Legacy/ once the Mac runs the iPad app (C11).
#if os(macOS) || os(visionOS)
//
//  MockLocationManager.swift
//  WhatTheFlightTests
//
//  Created by Kiro on 8/1/25.
//

import Foundation
import Combine
import CoreLocation
@testable import WhatTheFlight

// MARK: - Mock Location Error Types
enum MockLocationError: Error, LocalizedError {
    case locationUnavailable
    case permissionDenied
    case timeout
    case networkError
    
    var errorDescription: String? {
        switch self {
        case .locationUnavailable:
            return "Mock location unavailable"
        case .permissionDenied:
            return "Mock permission denied"
        case .timeout:
            return "Mock location timeout"
        case .networkError:
            return "Mock network error"
        }
    }
}

@MainActor
class MockLocationManager: LocationManagerProtocol, ObservableObject {
    
    // MARK: - Published Properties
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var currentLocation: CLLocation?
    @Published var isLocationAvailable: Bool = false
    
    // MARK: - Mock Properties
    var requestLocationPermissionCalled = false
    var getCurrentLocationCalled = false
    var createBoundsFromCurrentLocationCalled = false
    var shouldThrowError = false
    var mockLocation: CLLocation?
    var mockError: Error = MockLocationError.locationUnavailable
    var lastRadiusKm: Double?
    var shouldFailLocationRequest = false
    var locationRequestDelay: TimeInterval = 0.1
    
    // MARK: - LocationManagerProtocol Implementation
    
    func requestLocationPermission() {
        requestLocationPermissionCalled = true
        
        // Simulate permission being granted after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if self.authorizationStatus == .notDetermined {
                #if os(iOS)
                self.authorizationStatus = .authorizedWhenInUse
                #else
                self.authorizationStatus = .authorizedAlways
                #endif
                self.isLocationAvailable = true
            }
        }
    }
    
    func getCurrentLocation() async throws -> CLLocation {
        getCurrentLocationCalled = true
        
        if shouldThrowError {
            throw mockError
        }
        
        guard let location = mockLocation else {
            throw MockLocationError.locationUnavailable
        }
        
        currentLocation = location
        return location
    }
    
    func createBoundsFromCurrentLocation(radiusKm: Double) async throws -> GeographicBounds {
        createBoundsFromCurrentLocationCalled = true
        lastRadiusKm = radiusKm
        
        if shouldThrowError {
            throw mockError
        }
        
        guard let location = mockLocation else {
            throw MockLocationError.locationUnavailable
        }
        
        let coordinate = location.coordinate
        
        // Calculate approximate degree offset for the given radius
        let latOffset = radiusKm / 111.0 // Rough conversion: 1 degree ≈ 111 km
        let lonOffset = radiusKm / (111.0 * cos(coordinate.latitude * .pi / 180.0))
        
        return GeographicBounds(
            northLatitude: coordinate.latitude + latOffset,
            southLatitude: coordinate.latitude - latOffset,
            eastLongitude: coordinate.longitude + lonOffset,
            westLongitude: coordinate.longitude - lonOffset
        )
    }
    
    // MARK: - Mock Helper Methods
    
    /// Returns the appropriate authorized status for the current platform
    static var authorizedStatus: CLAuthorizationStatus {
        #if os(iOS)
        return .authorizedWhenInUse
        #else
        return .authorizedAlways
        #endif
    }
    
    func reset() {
        requestLocationPermissionCalled = false
        getCurrentLocationCalled = false
        createBoundsFromCurrentLocationCalled = false
        shouldThrowError = false
        mockLocation = nil
        mockError = MockLocationError.locationUnavailable
        authorizationStatus = .notDetermined
        currentLocation = nil
        isLocationAvailable = false
        lastRadiusKm = nil
        shouldFailLocationRequest = false
        locationRequestDelay = 0.1
    }
    
    func setMockLocation(_ location: CLLocation) {
        mockLocation = location
        currentLocation = location
        isLocationAvailable = true
    }
    
    func setAuthorizationStatus(_ status: CLAuthorizationStatus) {
        authorizationStatus = status
        #if os(iOS)
        isLocationAvailable = (status == .authorizedWhenInUse || status == .authorizedAlways)
        #else
        isLocationAvailable = (status == .authorizedAlways)
        #endif
    }
    
    func simulateLocationError(_ error: Error) {
        shouldThrowError = true
        mockError = error
    }
}
#endif
