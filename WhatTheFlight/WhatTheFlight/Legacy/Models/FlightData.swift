//
//  FlightData.swift
//  WhatTheFlight
//
//  Created by Kiro on 8/1/25.
//

import Foundation
import CoreLocation

struct FlightData: Codable, Identifiable, Equatable {
    let id: String
    let flightNumber: String?
    let callsign: String?
    let airline: AirlineInfo?
    let aircraft: AircraftInfo?
    let route: RouteInfo?
    let position: FlightPosition?
    let lastUpdated: Date
    
    init(id: String, flightNumber: String? = nil, callsign: String? = nil, 
         airline: AirlineInfo? = nil, aircraft: AircraftInfo? = nil, 
         route: RouteInfo? = nil, position: FlightPosition? = nil, 
         lastUpdated: Date = Date()) {
        self.id = id
        self.flightNumber = flightNumber
        self.callsign = callsign
        self.airline = airline
        self.aircraft = aircraft
        self.route = route
        self.position = position
        self.lastUpdated = lastUpdated
    }
    
    /// Returns the primary display identifier for the flight with fallback hierarchy
    var displayIdentifier: String {
        // Priority order: flightNumber → callsign → registration → aircraft model → "AIRCRAFT"
        if let flightNumber = flightNumber, !flightNumber.isEmpty {
            return flightNumber
        }
        
        if let callsign = callsign, !callsign.isEmpty {
            return callsign
        }
        
        if let registration = aircraft?.registration, !registration.isEmpty {
            return registration
        }
        
        if let aircraftModel = aircraft?.model, !aircraftModel.isEmpty {
            return aircraftModel
        }
        
        return "AIRCRAFT"
    }
    
    /// Returns a formatted route string for display
    var routeDescription: String {
        guard let route = route else { return "Unknown Route" }
        return "\(route.origin.iataCode) → \(route.destination.iataCode)"
    }
    
    /// Returns a formatted airline and aircraft string for display
    var aircraftDescription: String {
        let airlineName = airline?.name ?? "Unknown Airline"
        let aircraftModel = aircraft?.model ?? "Unknown Aircraft"
        return "\(airlineName) • \(aircraftModel)"
    }
    
    /// Calculates distance in miles from a given location
    func distanceFromLocation(_ location: CLLocation) -> Double? {
        guard let position = position else { return nil }
        let flightLocation = CLLocation(latitude: position.latitude, longitude: position.longitude)
        let distanceInMeters = location.distance(from: flightLocation)
        return distanceInMeters * 0.000621371 // Convert to miles
    }
    
    /// Calculates bearing (cardinal direction) from a given location
    func bearingFromLocation(_ location: CLLocation) -> Double? {
        guard let position = position else { return nil }
        
        let lat1 = location.coordinate.latitude * .pi / 180
        let lat2 = position.latitude * .pi / 180
        let deltaLon = (position.longitude - location.coordinate.longitude) * .pi / 180
        
        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        
        let bearing = atan2(y, x) * 180 / .pi
        return bearing >= 0 ? bearing : bearing + 360
    }
    
    /// Returns whether the aircraft is moving towards or away from a given location
    func isMovingTowardsLocation(_ location: CLLocation) -> Bool? {
        guard let position = position,
              let heading = position.heading else { return nil }
        
        guard let bearing = bearingFromLocation(location) else { return nil }
        
        // Calculate the difference between aircraft heading and bearing to user
        let angleDiff = abs(heading - Int(bearing))
        let normalizedDiff = min(angleDiff, 360 - angleDiff)
        
        // If the angle difference is less than 90 degrees, aircraft is moving towards user
        return normalizedDiff > 90
    }
    
    /// Calculates ETA to nearest point to user location in minutes and seconds
    func etaToNearestPoint(from location: CLLocation) -> String? {
        guard let position = position,
              let speed = position.speed,
              let heading = position.heading,
              speed > 0 else { return nil }
        
        // Current distance to user
        guard let currentDistance = distanceFromLocation(location) else { return nil }
        
        // Convert heading to radians
        let headingRadians = Double(heading) * .pi / 180
        
        // Aircraft current position
        let aircraftLocation = CLLocation(latitude: position.latitude, longitude: position.longitude)
        
        // Calculate the vector from aircraft to user
        let userLat = location.coordinate.latitude * .pi / 180
        let userLon = location.coordinate.longitude * .pi / 180
        let aircraftLat = aircraftLocation.coordinate.latitude * .pi / 180
        let aircraftLon = aircraftLocation.coordinate.longitude * .pi / 180
        
        // Great circle bearing from aircraft to user
        let deltaLon = userLon - aircraftLon
        let y = sin(deltaLon) * cos(userLat)
        let x = cos(aircraftLat) * sin(userLat) - sin(aircraftLat) * cos(userLat) * cos(deltaLon)
        let bearingToUser = atan2(y, x)
        
        // Calculate the angle between aircraft heading and bearing to user
        let angleDiff = abs(headingRadians - bearingToUser)
        let normalizedAngleDiff = min(angleDiff, 2 * .pi - angleDiff)
        
        // Calculate the component of aircraft velocity towards the user
        let approachSpeed = Double(speed) * cos(normalizedAngleDiff)
        
        // If not approaching (negative speed component), return nil
        guard approachSpeed > 0 else { return nil }
        
        // Calculate time to closest approach in hours
        let timeToClosestApproach = currentDistance / approachSpeed
        
        // Convert to minutes and seconds
        let totalMinutes = timeToClosestApproach * 60
        let minutes = Int(totalMinutes)
        let seconds = Int((totalMinutes - Double(minutes)) * 60)
        
        // Format as "m s"
        return "\(minutes)m \(seconds)s"
    }
    
    /// Calculates the minimum distance the aircraft will get to the user based on its flight path
    func nearestApproachDistance(to location: CLLocation) -> Double? {
        guard let position = position,
              let heading = position.heading else { return nil }
        
        // Aircraft current position
        let aircraftLocation = CLLocation(latitude: position.latitude, longitude: position.longitude)
        
        // Convert heading to radians
        let headingRadians = Double(heading) * .pi / 180
        
        // Convert coordinates to radians
        let userLat = location.coordinate.latitude * .pi / 180
        let userLon = location.coordinate.longitude * .pi / 180
        let aircraftLat = aircraftLocation.coordinate.latitude * .pi / 180
        let aircraftLon = aircraftLocation.coordinate.longitude * .pi / 180
        
        // Calculate the great circle bearing from aircraft to user
        let deltaLon = userLon - aircraftLon
        let y = sin(deltaLon) * cos(userLat)
        let x = cos(aircraftLat) * sin(userLat) - sin(aircraftLat) * cos(userLat) * cos(deltaLon)
        let bearingToUser = atan2(y, x)
        
        // Calculate the angle between aircraft heading and bearing to user
        let angleDiff = abs(headingRadians - bearingToUser)
        let normalizedAngleDiff = min(angleDiff, 2 * .pi - angleDiff)
        
        // Current distance to user
        guard let currentDistance = distanceFromLocation(location) else { return nil }
        
        // Calculate the perpendicular distance (closest approach)
        // This is the component of the current distance that's perpendicular to the flight path
        let nearestDistance = currentDistance * abs(sin(normalizedAngleDiff))
        
        return nearestDistance
    }
    
    /// Determines if the aircraft should be displayed with an orange icon based on proximity threshold
    func isNearProximityThreshold(to location: CLLocation, threshold: Double) -> Bool {
        guard let currentDistance = distanceFromLocation(location) else { return false }
        
        // Check if aircraft is approaching (moving towards user)
        let isApproaching = isMovingTowardsLocation(location) ?? false
        
        if isApproaching {
            // For approaching aircraft, use nearest approach distance
            if let nearestDistance = nearestApproachDistance(to: location) {
                return nearestDistance <= threshold
            }
            // Fallback to current distance for approaching aircraft
            return currentDistance <= threshold
        } else {
            // For outbound aircraft, only show orange if currently within threshold
            // This ensures outbound aircraft beyond threshold show normal colors
            return currentDistance <= threshold
        }
    }
    
    /// Determines if the aircraft is a helicopter based on aircraft code and model
    var isHelicopter: Bool {
        guard let aircraft = aircraft else { return false }
        
        // Check aircraft code for helicopter indicators
        let helicopterCodes = ["H25A", "H25B", "H25C", "H47", "H60", "H130", "H135", "H145", "H155", "H175", "H225", "EC20", "EC30", "EC35", "EC45", "AS50", "AS55", "AS65", "BH06", "BH09", "BH12", "R22", "R44", "R66", "S76", "AW09", "AW39", "AW69", "AW89", "AW99", "MI8", "MI17", "MI24", "MI26", "MI28", "KA50", "KA52", "UH1", "AH1", "CH47", "CH53", "SH60", "MH60", "UH60", "V22"]
        
        if helicopterCodes.contains(aircraft.code) {
            return true
        }
        
        // Check model name for helicopter keywords
        let helicopterKeywords = ["helicopter", "heli", "rotor", "chopper", "bell", "sikorsky", "eurocopter", "airbus helicopters", "robinson", "agusta", "westland", "mil", "kamov", "hughes", "mcdonnell douglas"]
        let modelLower = aircraft.model.lowercased()
        
        return helicopterKeywords.contains { modelLower.contains($0) }
    }
}

struct AirlineInfo: Codable, Equatable {
    let name: String
    let code: String?
    
    init(name: String, code: String? = nil) {
        self.name = name
        self.code = code
    }
}

struct AircraftInfo: Codable, Equatable {
    let model: String
    let code: String
    let registration: String?
    let photoURL: String?
    
    init(model: String, code: String, registration: String? = nil, photoURL: String? = nil) {
        self.model = model
        self.code = code
        self.registration = registration
        self.photoURL = photoURL
    }
}

struct RouteInfo: Codable, Equatable {
    let origin: AirportInfo
    let destination: AirportInfo
    
    init(origin: AirportInfo, destination: AirportInfo) {
        self.origin = origin
        self.destination = destination
    }
}

struct AirportInfo: Codable, Equatable {
    let name: String
    let iataCode: String
    let city: String?
    
    init(name: String, iataCode: String, city: String? = nil) {
        self.name = name
        self.iataCode = iataCode
        self.city = city
    }
    
    /// Returns a cleaned airport name without "Airport" suffix
    var displayName: String {
        return name.replacingOccurrences(of: " Airport", with: "")
    }
}

struct FlightPosition: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    let altitude: Int?
    let speed: Int?
    let heading: Int?
    
    init(latitude: Double, longitude: Double, altitude: Int? = nil, 
         speed: Int? = nil, heading: Int? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.speed = speed
        self.heading = heading
    }
    
    /// Validates that the coordinates are within valid ranges
    var isValid: Bool {
        return abs(latitude) <= 90 && abs(longitude) <= 180
    }
    
    /// Returns formatted altitude string
    var altitudeDescription: String {
        guard let altitude = altitude else { return "Unknown" }
        return "\(altitude) ft"
    }
    
    /// Returns formatted speed string
    var speedDescription: String {
        guard let speed = speed else { return "Unknown" }
        return "\(speed) kts"
    }
}

// MARK: - Mock Data for Previews
extension FlightData {
    static let mockFlight1 = FlightData(
        id: "mock1",
        flightNumber: "AA123",
        callsign: "AAL123",
        airline: AirlineInfo(name: "American Airlines", code: "AA"),
        aircraft: AircraftInfo(model: "Boeing 737-800", code: "B738", registration: "N123AA", photoURL: nil),
        route: RouteInfo(
            origin: AirportInfo(name: "John F. Kennedy International Airport", iataCode: "JFK", city: "New York"),
            destination: AirportInfo(name: "Los Angeles International Airport", iataCode: "LAX", city: "Los Angeles")
        ),
        position: FlightPosition(latitude: 40.7128, longitude: -74.0060, altitude: 35000, speed: 450, heading: 270),
        lastUpdated: Date().addingTimeInterval(-30)
    )
    
    static let mockFlight2 = FlightData(
        id: "mock2",
        flightNumber: "DL456",
        callsign: "DAL456",
        airline: AirlineInfo(name: "Delta Air Lines", code: "DL"),
        aircraft: AircraftInfo(model: "Airbus A320", code: "A320", registration: "N456DL", photoURL: nil),
        route: RouteInfo(
            origin: AirportInfo(name: "Chicago O'Hare International Airport", iataCode: "ORD", city: "Chicago"),
            destination: AirportInfo(name: "Miami International Airport", iataCode: "MIA", city: "Miami")
        ),
        position: FlightPosition(latitude: 41.9742, longitude: -87.9073, altitude: 38000, speed: 480, heading: 135),
        lastUpdated: Date().addingTimeInterval(-45)
    )
    
    static let mockFlight3 = FlightData(
        id: "mock3",
        flightNumber: "UA789",
        callsign: "UAL789",
        airline: AirlineInfo(name: "United Airlines", code: "UA"),
        aircraft: AircraftInfo(model: "Boeing 777-300ER", code: "B77W", registration: "N789UA", photoURL: nil),
        route: RouteInfo(
            origin: AirportInfo(name: "San Francisco International Airport", iataCode: "SFO", city: "San Francisco"),
            destination: AirportInfo(name: "London Heathrow Airport", iataCode: "LHR", city: "London")
        ),
        position: FlightPosition(latitude: 37.7749, longitude: -122.4194, altitude: 41000, speed: 520, heading: 45),
        lastUpdated: Date().addingTimeInterval(-60)
    )
    
    static let mockHelicopter = FlightData(
        id: "mockHeli1",
        flightNumber: "HELI1",
        callsign: "MEDIC1",
        airline: AirlineInfo(name: "Emergency Medical Services", code: "EMS"),
        aircraft: AircraftInfo(model: "Bell 412 Helicopter", code: "BH12", registration: "N412EM", photoURL: nil),
        route: RouteInfo(
            origin: AirportInfo(name: "Regional Hospital", iataCode: "RGH", city: "Local"),
            destination: AirportInfo(name: "City Medical Center", iataCode: "CMC", city: "Downtown")
        ),
        position: FlightPosition(latitude: 40.7580, longitude: -73.9855, altitude: 1500, speed: 120, heading: 180),
        lastUpdated: Date().addingTimeInterval(-15)
    )
}