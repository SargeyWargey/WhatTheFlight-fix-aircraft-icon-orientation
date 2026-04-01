//
//  FlightDataTests.swift
//  WhatTheFlightTests
//
//  Created by Kiro on 8/1/25.
//

import XCTest
@testable import WhatTheFlight

final class FlightDataTests: XCTestCase {
    
    func testFlightDataInitialization() {
        let flightData = FlightData(id: "test123")
        
        XCTAssertEqual(flightData.id, "test123")
        XCTAssertNil(flightData.flightNumber)
        XCTAssertNil(flightData.callsign)
        XCTAssertNil(flightData.airline)
        XCTAssertNil(flightData.aircraft)
        XCTAssertNil(flightData.route)
        XCTAssertNil(flightData.position)
    }
    
    func testDisplayIdentifierWithFlightNumber() {
        let flightData = FlightData(id: "test123", flightNumber: "AA123")
        XCTAssertEqual(flightData.displayIdentifier, "AA123")
    }
    
    func testDisplayIdentifierWithCallsignOnly() {
        let flightData = FlightData(id: "test123", callsign: "AMERICAN123")
        XCTAssertEqual(flightData.displayIdentifier, "AMERICAN123")
    }
    
    func testDisplayIdentifierFallbackToId() {
        let flightData = FlightData(id: "test123")
        XCTAssertEqual(flightData.displayIdentifier, "test123")
    }
    
    func testRouteDescription() {
        let origin = AirportInfo(name: "Los Angeles International", iataCode: "LAX")
        let destination = AirportInfo(name: "John F. Kennedy International", iataCode: "JFK")
        let route = RouteInfo(origin: origin, destination: destination)
        let flightData = FlightData(id: "test123", route: route)
        
        XCTAssertEqual(flightData.routeDescription, "LAX → JFK")
    }
    
    func testRouteDescriptionWithoutRoute() {
        let flightData = FlightData(id: "test123")
        XCTAssertEqual(flightData.routeDescription, "Unknown Route")
    }
    
    func testAircraftDescription() {
        let airline = AirlineInfo(name: "American Airlines", code: "AA")
        let aircraft = AircraftInfo(model: "Boeing 737-800", code: "B738")
        let flightData = FlightData(id: "test123", airline: airline, aircraft: aircraft)
        
        XCTAssertEqual(flightData.aircraftDescription, "American Airlines • Boeing 737-800")
    }
    
    func testAircraftDescriptionWithMissingInfo() {
        let flightData = FlightData(id: "test123")
        XCTAssertEqual(flightData.aircraftDescription, "Unknown Airline • Unknown Aircraft")
    }
    
    func testFlightDataEquality() {
        let flightData1 = FlightData(id: "test123", flightNumber: "AA123")
        let flightData2 = FlightData(id: "test123", flightNumber: "AA123")
        let flightData3 = FlightData(id: "test456", flightNumber: "AA123")
        
        XCTAssertEqual(flightData1, flightData2)
        XCTAssertNotEqual(flightData1, flightData3)
    }
    
    func testFlightDataCodable() throws {
        let airline = AirlineInfo(name: "American Airlines", code: "AA")
        let aircraft = AircraftInfo(model: "Boeing 737-800", code: "B738")
        let origin = AirportInfo(name: "Los Angeles International", iataCode: "LAX")
        let destination = AirportInfo(name: "John F. Kennedy International", iataCode: "JFK")
        let route = RouteInfo(origin: origin, destination: destination)
        let position = FlightPosition(latitude: 34.0522, longitude: -118.2437, altitude: 35000, speed: 450)
        
        let originalFlight = FlightData(
            id: "test123",
            flightNumber: "AA123",
            callsign: "AMERICAN123",
            airline: airline,
            aircraft: aircraft,
            route: route,
            position: position
        )
        
        let encoded = try JSONEncoder().encode(originalFlight)
        let decoded = try JSONDecoder().decode(FlightData.self, from: encoded)
        
        XCTAssertEqual(originalFlight, decoded)
    }
}

final class AirportInfoTests: XCTestCase {
    
    func testAirportDisplayName() {
        let airport1 = AirportInfo(name: "Los Angeles International Airport", iataCode: "LAX")
        XCTAssertEqual(airport1.displayName, "Los Angeles International")
        
        let airport2 = AirportInfo(name: "Heathrow", iataCode: "LHR")
        XCTAssertEqual(airport2.displayName, "Heathrow")
    }
}

final class FlightPositionTests: XCTestCase {
    
    func testValidPosition() {
        let position = FlightPosition(latitude: 34.0522, longitude: -118.2437)
        XCTAssertTrue(position.isValid)
    }
    
    func testInvalidLatitude() {
        let position = FlightPosition(latitude: 91.0, longitude: -118.2437)
        XCTAssertFalse(position.isValid)
    }
    
    func testInvalidLongitude() {
        let position = FlightPosition(latitude: 34.0522, longitude: 181.0)
        XCTAssertFalse(position.isValid)
    }
    
    func testAltitudeDescription() {
        let position1 = FlightPosition(latitude: 34.0522, longitude: -118.2437, altitude: 35000)
        XCTAssertEqual(position1.altitudeDescription, "35000 ft")
        
        let position2 = FlightPosition(latitude: 34.0522, longitude: -118.2437)
        XCTAssertEqual(position2.altitudeDescription, "Unknown")
    }
    
    func testSpeedDescription() {
        let position1 = FlightPosition(latitude: 34.0522, longitude: -118.2437, speed: 450)
        XCTAssertEqual(position1.speedDescription, "450 kts")
        
        let position2 = FlightPosition(latitude: 34.0522, longitude: -118.2437)
        XCTAssertEqual(position2.speedDescription, "Unknown")
    }
}