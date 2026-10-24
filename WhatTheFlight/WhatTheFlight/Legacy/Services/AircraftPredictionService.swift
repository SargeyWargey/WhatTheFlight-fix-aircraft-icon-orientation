// Legacy: only the macOS (and visionOS) app runs this. iOS, tvOS and watchOS run radar v2;
// see Enhancements Spec B4. Delete with the rest of Legacy/ once the Mac runs the iPad app (C11).
#if os(macOS) || os(visionOS)
//
//  AircraftPredictionService.swift
//  WhatTheFlight
//
//  Created by Kiro on 8/4/25.
//

import Foundation
import CoreLocation
import Combine

/// Service responsible for predicting aircraft positions between API updates
class AircraftPredictionService: ObservableObject {
    
    // MARK: - Published Properties
    @Published private(set) var predictedPositions: [String: PredictedPosition] = [:]
    
    // MARK: - Private Properties
    private var predictionTimer: Timer?
    private var flightData: [String: FlightData] = [:]
    private var userLocation: CLLocation?
    
    // Adaptive timer intervals based on distance
    private let closeDistanceThreshold: Double = 2.0 // miles
    private let mediumDistanceThreshold: Double = 5.0 // miles
    private let closeUpdateInterval: TimeInterval = 1.0 // 1 second for very close aircraft
    private let mediumUpdateInterval: TimeInterval = 2.0 // 2 seconds for medium distance
    private let distantUpdateInterval: TimeInterval = 5.0 // 5 seconds for distant aircraft
    
    // MARK: - Initialization
    init() {
        startPredictionUpdates()
    }
    
    deinit {
        stopPredictionUpdates()
    }
    
    // MARK: - Public Methods
    
    /// Updates the flight data used for predictions
    func updateFlightData(_ flights: [FlightData]) {
        // Convert to dictionary for efficient lookup
        var newFlightData: [String: FlightData] = [:]
        for flight in flights {
            newFlightData[flight.id] = flight
        }
        
        // Remove predictions for flights that are no longer present
        let currentFlightIds = Set(newFlightData.keys)
        let predictedFlightIds = Set(predictedPositions.keys)
        let removedFlightIds = predictedFlightIds.subtracting(currentFlightIds)
        
        for removedId in removedFlightIds {
            predictedPositions.removeValue(forKey: removedId)
        }
        
        // Update flight data
        flightData = newFlightData
        
        // Initialize predictions for new flights
        updatePredictions()
        
        // Restart timer with adaptive interval based on closest aircraft
        restartAdaptiveTimer()
    }
    
    /// Updates the user location for distance-based calculations
    func updateUserLocation(_ location: CLLocation?) {
        userLocation = location
        // Restart timer with new adaptive interval when user location changes
        restartAdaptiveTimer()
    }
    
    /// Gets the predicted position for a specific flight
    func getPredictedPosition(for flightId: String) -> PredictedPosition? {
        return predictedPositions[flightId]
    }
    
    /// Gets the predicted bearing from a location to an aircraft
    func getPredictedBearing(for flightId: String, from location: CLLocation) -> Double? {
        guard let predicted = predictedPositions[flightId] else { return nil }
        
        let predictedLocation = CLLocation(
            latitude: predicted.latitude,
            longitude: predicted.longitude
        )
        
        return calculateBearing(from: location, to: predictedLocation)
    }
    
    /// Gets the predicted distance from a location to an aircraft
    func getPredictedDistance(for flightId: String, from location: CLLocation) -> Double? {
        guard let predicted = predictedPositions[flightId] else { return nil }
        
        let predictedLocation = CLLocation(
            latitude: predicted.latitude,
            longitude: predicted.longitude
        )
        
        let distanceInMeters = location.distance(from: predictedLocation)
        return distanceInMeters * 0.000621371 // Convert to miles
    }
    
    /// Gets the predicted ETA to nearest point for an aircraft
    func getPredictedETA(for flightId: String, from location: CLLocation) -> String? {
        guard let predicted = predictedPositions[flightId],
              let speed = predicted.speed,
              let heading = predicted.heading,
              speed > 0 else { return nil }
        
        let predictedLocation = CLLocation(
            latitude: predicted.latitude,
            longitude: predicted.longitude
        )
        
        return calculateETAToNearestPoint(
            from: predictedLocation,
            to: location,
            speed: speed,
            heading: heading
        )
    }
    
    /// Gets the predicted nearest approach distance for an aircraft
    func getPredictedNearestApproach(for flightId: String, to location: CLLocation) -> Double? {
        guard let predicted = predictedPositions[flightId],
              let heading = predicted.heading else { return nil }
        
        let predictedLocation = CLLocation(
            latitude: predicted.latitude,
            longitude: predicted.longitude
        )
        
        return calculateNearestApproachDistance(
            from: predictedLocation,
            to: location,
            heading: heading
        )
    }
}

// MARK: - Private Methods
private extension AircraftPredictionService {
    
    /// Starts the prediction update timer with adaptive interval
    func startPredictionUpdates() {
        let interval = calculateOptimalUpdateInterval()
        predictionTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.updatePredictions()
            // Check if we need to adjust the timer interval
            self?.adjustTimerIfNeeded()
        }
    }
    
    /// Stops the prediction update timer
    func stopPredictionUpdates() {
        predictionTimer?.invalidate()
        predictionTimer = nil
    }
    
    /// Updates predictions for all tracked flights
    func updatePredictions() {
        var newPredictions: [String: PredictedPosition] = [:]
        
        for (flightId, flight) in flightData {
            if let predicted = calculatePredictedPosition(for: flight) {
                newPredictions[flightId] = predicted
            }
        }
        
        predictedPositions = newPredictions
    }
    
    /// Restarts the timer with adaptive interval based on current aircraft distances
    func restartAdaptiveTimer() {
        stopPredictionUpdates()
        startPredictionUpdates()
    }
    
    /// Calculates the optimal update interval based on closest aircraft distance
    func calculateOptimalUpdateInterval() -> TimeInterval {
        guard let userLocation = userLocation else {
            // Default to medium interval if no user location
            return mediumUpdateInterval
        }
        
        var closestDistance = Double.greatestFiniteMagnitude
        
        // Find the closest aircraft distance
        for flight in flightData.values {
            if let position = flight.position {
                let flightLocation = CLLocation(latitude: position.latitude, longitude: position.longitude)
                let distance = userLocation.distance(from: flightLocation) * 0.000621371 // Convert to miles
                closestDistance = min(closestDistance, distance)
            }
        }
        
        // Return appropriate interval based on closest aircraft
        if closestDistance < closeDistanceThreshold {
            return closeUpdateInterval
        } else if closestDistance < mediumDistanceThreshold {
            return mediumUpdateInterval
        } else {
            return distantUpdateInterval
        }
    }
    
    /// Checks if the current timer interval needs adjustment and restarts if necessary
    func adjustTimerIfNeeded() {
        let optimalInterval = calculateOptimalUpdateInterval()
        let currentInterval = predictionTimer?.timeInterval ?? mediumUpdateInterval
        
        // Only restart timer if the optimal interval is significantly different
        if abs(optimalInterval - currentInterval) > 0.1 {
            restartAdaptiveTimer()
        }
    }
    
    /// Calculates the predicted position for a flight based on its last known data
    func calculatePredictedPosition(for flight: FlightData) -> PredictedPosition? {
        guard let position = flight.position,
              let speed = position.speed,
              let heading = position.heading,
              speed > 0 else { return nil }
        
        // Calculate time elapsed since last update
        let timeElapsed = Date().timeIntervalSince(flight.lastUpdated)
        
        // Convert speed from knots to miles per second
        let speedMilesPerSecond = Double(speed) * 0.000277778 // knots to miles/sec
        
        // Calculate distance traveled
        let distanceTraveled = speedMilesPerSecond * timeElapsed
        
        // Convert heading to radians (heading is in degrees from north, clockwise)
        let headingRadians = Double(heading) * .pi / 180
        
        // Calculate new position using great circle navigation
        let newPosition = calculateNewPosition(
            from: CLLocationCoordinate2D(latitude: position.latitude, longitude: position.longitude),
            bearing: headingRadians,
            distance: distanceTraveled
        )
        
        return PredictedPosition(
            latitude: newPosition.latitude,
            longitude: newPosition.longitude,
            altitude: position.altitude,
            speed: speed,
            heading: heading,
            lastUpdated: flight.lastUpdated,
            predictionTime: Date()
        )
    }
    
    /// Calculates a new position given a starting coordinate, bearing, and distance
    func calculateNewPosition(from coordinate: CLLocationCoordinate2D, bearing: Double, distance: Double) -> CLLocationCoordinate2D {
        let earthRadius = 3959.0 // Earth radius in miles
        
        let lat1 = coordinate.latitude * .pi / 180
        let lon1 = coordinate.longitude * .pi / 180
        
        let lat2 = asin(sin(lat1) * cos(distance / earthRadius) +
                       cos(lat1) * sin(distance / earthRadius) * cos(bearing))
        
        let lon2 = lon1 + atan2(sin(bearing) * sin(distance / earthRadius) * cos(lat1),
                               cos(distance / earthRadius) - sin(lat1) * sin(lat2))
        
        return CLLocationCoordinate2D(
            latitude: lat2 * 180 / .pi,
            longitude: lon2 * 180 / .pi
        )
    }
    
    /// Calculates bearing from one location to another
    func calculateBearing(from: CLLocation, to: CLLocation) -> Double {
        let lat1 = from.coordinate.latitude * .pi / 180
        let lat2 = to.coordinate.latitude * .pi / 180
        let deltaLon = (to.coordinate.longitude - from.coordinate.longitude) * .pi / 180
        
        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        
        let bearing = atan2(y, x) * 180 / .pi
        return bearing >= 0 ? bearing : bearing + 360
    }
    
    /// Calculates ETA to nearest point using predicted position
    func calculateETAToNearestPoint(from aircraftLocation: CLLocation, to userLocation: CLLocation, speed: Int, heading: Int) -> String? {
        // Convert heading to radians
        let headingRadians = Double(heading) * .pi / 180
        
        // Calculate the vector from aircraft to user
        let userLat = userLocation.coordinate.latitude * .pi / 180
        let userLon = userLocation.coordinate.longitude * .pi / 180
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
        
        // Current distance to user
        let currentDistance = aircraftLocation.distance(from: userLocation) * 0.000621371 // Convert to miles
        
        // Calculate time to closest approach in hours
        let timeToClosestApproach = currentDistance / approachSpeed
        
        // Convert to minutes and seconds
        let totalMinutes = timeToClosestApproach * 60
        let minutes = Int(totalMinutes)
        let seconds = Int((totalMinutes - Double(minutes)) * 60)
        
        // Format as "m s"
        return "\(minutes)m \(seconds)s"
    }
    
    /// Calculates nearest approach distance using predicted position
    func calculateNearestApproachDistance(from aircraftLocation: CLLocation, to userLocation: CLLocation, heading: Int) -> Double? {
        // Convert heading to radians
        let headingRadians = Double(heading) * .pi / 180
        
        // Convert coordinates to radians
        let userLat = userLocation.coordinate.latitude * .pi / 180
        let userLon = userLocation.coordinate.longitude * .pi / 180
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
        let currentDistance = aircraftLocation.distance(from: userLocation) * 0.000621371 // Convert to miles
        
        // Calculate the perpendicular distance (closest approach)
        let nearestDistance = currentDistance * abs(sin(normalizedAngleDiff))
        
        return nearestDistance
    }
}

// MARK: - Supporting Types

/// Represents a predicted aircraft position
struct PredictedPosition {
    let latitude: Double
    let longitude: Double
    let altitude: Int?
    let speed: Int?
    let heading: Int?
    let lastUpdated: Date // When the original data was last updated
    let predictionTime: Date // When this prediction was calculated
    
    /// Time elapsed since the original data was updated
    var timeSinceUpdate: TimeInterval {
        return predictionTime.timeIntervalSince(lastUpdated)
    }
    
    /// Whether this prediction is still considered accurate (within reasonable time bounds)
    var isAccurate: Bool {
        return timeSinceUpdate < 120 // Consider predictions accurate for up to 2 minutes
    }
}
#endif
