//
//  GeographicBounds.swift
//  WhatTheFlight
//
//  Created by Kiro on 8/1/25.
//

import Foundation
import CoreLocation

struct GeographicBounds: Codable, Equatable {
    let northLatitude: Double
    let southLatitude: Double
    let eastLongitude: Double
    let westLongitude: Double
    
    init(northLatitude: Double, southLatitude: Double, 
         eastLongitude: Double, westLongitude: Double) {
        self.northLatitude = northLatitude
        self.southLatitude = southLatitude
        self.eastLongitude = eastLongitude
        self.westLongitude = westLongitude
    }
    
    /// Validates that the bounds form a valid geographic rectangle
    var isValid: Bool {
        return northLatitude > southLatitude && 
               eastLongitude > westLongitude &&
               abs(northLatitude) <= 90 && abs(southLatitude) <= 90 &&
               abs(eastLongitude) <= 180 && abs(westLongitude) <= 180
    }
    
    /// Returns the center point of the bounds
    var center: CLLocationCoordinate2D {
        let centerLat = (northLatitude + southLatitude) / 2
        let centerLon = (eastLongitude + westLongitude) / 2
        return CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
    }
    
    /// Returns the bounds formatted as a string for API requests
    var boundsString: String {
        return "\(northLatitude),\(southLatitude),\(westLongitude),\(eastLongitude)"
    }
    
    /// Creates bounds around a center point with a given radius in kilometers
    static func around(center: CLLocationCoordinate2D, radiusKm: Double) -> GeographicBounds {
        let latDelta = radiusKm / 111.0 // Approximate km per degree latitude
        let lonDelta = radiusKm / (111.0 * cos(center.latitude * .pi / 180.0))
        
        return GeographicBounds(
            northLatitude: center.latitude + latDelta,
            southLatitude: center.latitude - latDelta,
            eastLongitude: center.longitude + lonDelta,
            westLongitude: center.longitude - lonDelta
        )
    }
    
    /// Creates bounds from a CLLocationCoordinate2D center and radius
    static func fromCenter(_ center: CLLocationCoordinate2D, radiusKm: Double = 10.0) -> GeographicBounds {
        return around(center: center, radiusKm: radiusKm)
    }
    
    /// Checks if a coordinate is within these bounds
    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        return coordinate.latitude >= southLatitude &&
               coordinate.latitude <= northLatitude &&
               coordinate.longitude >= westLongitude &&
               coordinate.longitude <= eastLongitude
    }
    
    /// Returns a human-readable description of the bounds
    var description: String {
        return "N: \(String(format: "%.4f", northLatitude)), S: \(String(format: "%.4f", southLatitude)), E: \(String(format: "%.4f", eastLongitude)), W: \(String(format: "%.4f", westLongitude))"
    }
}

// MARK: - Validation Extensions
extension GeographicBounds {
    enum ValidationError: LocalizedError {
        case invalidLatitudeRange
        case invalidLongitudeRange
        case invalidBoundsOrder
        case boundsOutOfRange
        
        var errorDescription: String? {
            switch self {
            case .invalidLatitudeRange:
                return "Latitude values must be between -90 and 90 degrees"
            case .invalidLongitudeRange:
                return "Longitude values must be between -180 and 180 degrees"
            case .invalidBoundsOrder:
                return "North latitude must be greater than south latitude, and east longitude must be greater than west longitude"
            case .boundsOutOfRange:
                return "Geographic bounds are outside valid coordinate ranges"
            }
        }
    }
    
    /// Validates the bounds and throws specific errors
    func validate() throws {
        guard abs(northLatitude) <= 90 && abs(southLatitude) <= 90 else {
            throw ValidationError.invalidLatitudeRange
        }
        
        guard abs(eastLongitude) <= 180 && abs(westLongitude) <= 180 else {
            throw ValidationError.invalidLongitudeRange
        }
        
        guard northLatitude > southLatitude && eastLongitude > westLongitude else {
            throw ValidationError.invalidBoundsOrder
        }
    }
}