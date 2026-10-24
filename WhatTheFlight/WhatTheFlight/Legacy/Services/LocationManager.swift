// Legacy: only the macOS (and visionOS) app runs this. iOS, tvOS and watchOS run radar v2;
// see Enhancements Spec B4. Delete with the rest of Legacy/ once the Mac runs the iPad app (C11).
#if os(macOS) || os(visionOS)
//
//  LocationManager.swift
//  WhatTheFlight
//
//  Created by Kiro on 8/1/25.
//

import Foundation
import CoreLocation
import Combine

/// Protocol defining location management capabilities
@MainActor
protocol LocationManagerProtocol: ObservableObject {
    var authorizationStatus: CLAuthorizationStatus { get }
    var currentLocation: CLLocation? { get }
    var isLocationAvailable: Bool { get }
    
    func requestLocationPermission()
    func getCurrentLocation() async throws -> CLLocation
    func createBoundsFromCurrentLocation(radiusKm: Double) async throws -> GeographicBounds
}

/// Manages user location services and geographic boundary operations
@MainActor
class LocationManager: NSObject, LocationManagerProtocol, ObservableObject {
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var currentLocation: CLLocation?
    @Published var isLocationAvailable: Bool = false
    
    private let locationManager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    
    override init() {
        super.init()
        setupLocationManager()
        updateLocationAvailability()
    }
    
    // MARK: - Setup
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 100 // Update every 100 meters
        authorizationStatus = locationManager.authorizationStatus
    }
    
    private func updateLocationAvailability() {
        #if os(iOS)
        isLocationAvailable = authorizationStatus == .authorizedWhenInUse || 
                             authorizationStatus == .authorizedAlways
        #elseif os(macOS)
        isLocationAvailable = authorizationStatus == .authorizedAlways
        #elseif os(tvOS)
        isLocationAvailable = false // Location services not available on tvOS
        #else
        isLocationAvailable = authorizationStatus == .authorizedAlways
        #endif
    }
    
    // MARK: - Public Methods
    
    func requestLocationPermission() {
        print("LocationManager: Requesting location permission. Current status: \(authorizationStatus)")
        
        guard authorizationStatus == .notDetermined else {
            print("LocationManager: Permission already determined: \(authorizationStatus)")
            return
        }
        
        #if !os(tvOS)
        // Use authorization status instead of locationServicesEnabled to avoid main thread warning
        guard authorizationStatus != .denied && authorizationStatus != .restricted else {
            print("LocationManager: Location services are denied or restricted")
            return
        }
        #endif
        
        #if os(iOS)
        print("LocationManager: Requesting when-in-use authorization for iOS")
        locationManager.requestWhenInUseAuthorization()
        #elseif os(macOS)
        print("LocationManager: Requesting always authorization for macOS")
        locationManager.requestAlwaysAuthorization()
        #elseif os(tvOS)
        print("LocationManager: Location services not available on tvOS")
        authorizationStatus = .denied
        #else
        print("LocationManager: Requesting always authorization")
        locationManager.requestAlwaysAuthorization()
        #endif
    }
    
    func getCurrentLocation() async throws -> CLLocation {
        // Check authorization status first
        guard isLocationAvailable else {
            throw LocationError.permissionDenied
        }
        
        // If we have a recent location, return it
        if let location = currentLocation,
           location.timestamp.timeIntervalSinceNow > -300 { // 5 minutes
            return location
        }
        
        // Request a new location
        return try await withCheckedThrowingContinuation { continuation in
            self.locationContinuation = continuation
            locationManager.requestLocation()
        }
    }
    
    func createBoundsFromCurrentLocation(radiusKm: Double = 10.0) async throws -> GeographicBounds {
        let location = try await getCurrentLocation()
        return GeographicBounds.fromCenter(location.coordinate, radiusKm: radiusKm)
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        Task { @MainActor in
            currentLocation = location
            
            // Complete any pending location request
            if let continuation = locationContinuation {
                locationContinuation = nil
                continuation.resume(returning: location)
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            // Complete any pending location request with error
            if let continuation = locationContinuation {
                locationContinuation = nil
                continuation.resume(throwing: LocationError.locationUnavailable(error))
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor in
            print("LocationManager: Authorization status changed to: \(status)")
            authorizationStatus = status
            updateLocationAvailability()
            
            // Handle permission denied case
            if let continuation = locationContinuation,
               !isLocationAvailable {
                print("LocationManager: Permission denied, cancelling location request")
                locationContinuation = nil
                continuation.resume(throwing: LocationError.permissionDenied)
            }
        }
    }
}

// MARK: - Location Errors

enum LocationError: LocalizedError {
    case permissionDenied
    case locationUnavailable(Error)
    case locationServicesDisabled
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Location permission is required to automatically detect your area. You can manually enter coordinates in settings."
        case .locationUnavailable(let error):
            return "Unable to determine your location: \(error.localizedDescription)"
        case .locationServicesDisabled:
            return "Location services are disabled. Please enable them in Settings to use automatic location detection."
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .permissionDenied:
            return "Go to Settings > Privacy & Security > Location Services to turn on location access for What The Flight?"
        case .locationUnavailable:
            return "Try again or manually enter your coordinates in the app settings."
        case .locationServicesDisabled:
            return "Enable Location Services in your device settings."
        }
    }
}

// MARK: - Manual Coordinate Entry Support

extension LocationManager {
    /// Validates manually entered coordinates and creates bounds
    static func createBoundsFromManualEntry(
        latitude: Double,
        longitude: Double,
        radiusKm: Double = 10.0
    ) throws -> GeographicBounds {
        // Validate coordinate ranges
        guard abs(latitude) <= 90 else {
            throw CoordinateValidationError.invalidLatitude
        }
        
        guard abs(longitude) <= 180 else {
            throw CoordinateValidationError.invalidLongitude
        }
        
        guard radiusKm > 0 && radiusKm <= 100 else {
            throw CoordinateValidationError.invalidRadius
        }
        
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return GeographicBounds.fromCenter(coordinate, radiusKm: radiusKm)
    }
    
    /// Validates a coordinate string and returns parsed values
    static func parseCoordinateString(_ coordinateString: String) throws -> (latitude: Double, longitude: Double) {
        let components = coordinateString.components(separatedBy: ",")
        guard components.count == 2 else {
            throw CoordinateValidationError.invalidFormat
        }
        
        guard let latitude = Double(components[0].trimmingCharacters(in: .whitespaces)),
              let longitude = Double(components[1].trimmingCharacters(in: .whitespaces)) else {
            throw CoordinateValidationError.invalidFormat
        }
        
        return (latitude: latitude, longitude: longitude)
    }
}

// MARK: - Coordinate Validation Errors

enum CoordinateValidationError: LocalizedError {
    case invalidLatitude
    case invalidLongitude
    case invalidRadius
    case invalidFormat
    
    var errorDescription: String? {
        switch self {
        case .invalidLatitude:
            return "Latitude must be between -90 and 90 degrees"
        case .invalidLongitude:
            return "Longitude must be between -180 and 180 degrees"
        case .invalidRadius:
            return "Radius must be between 1 and 100 kilometers"
        case .invalidFormat:
            return "Coordinates must be in the format 'latitude, longitude' (e.g., '37.7749, -122.4194')"
        }
    }
}
#endif
