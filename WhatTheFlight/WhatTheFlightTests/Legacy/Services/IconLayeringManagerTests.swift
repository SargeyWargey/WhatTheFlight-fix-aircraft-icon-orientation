// Legacy: only the macOS (and visionOS) app runs this. iOS, tvOS and watchOS run radar v2;
// see Enhancements Spec B4. Delete with the rest of Legacy/ once the Mac runs the iPad app (C11).
#if os(macOS) || os(visionOS)
//
//  IconLayeringManagerTests.swift
//  WhatTheFlightTests
//
//  Created by Kiro on 8/3/25.
//

import XCTest
import CoreLocation
@testable import WhatTheFlight

final class IconLayeringManagerTests: XCTestCase {
    
    var layeringManager: IconLayeringManager!
    
    override func setUp() {
        super.setUp()
        layeringManager = IconLayeringManager()
    }
    
    override func tearDown() {
        layeringManager = nil
        super.tearDown()
    }
    
    func testFocusedAircraftHasHighestZIndex() {
        // Create test flights
        let flight1 = createTestFlight(id: "1", distance: 10.0)
        let flight2 = createTestFlight(id: "2", distance: 5.0) // Closer but not focused
        let flights = [flight1, flight2]
        
        // Create overlapping positions
        let positions = [
            "1": CGPoint(x: 100, y: 100),
            "2": CGPoint(x: 105, y: 105) // Overlapping
        ]
        
        let distances = [
            "1": 10.0,
            "2": 5.0
        ]
        
        // Calculate layering with flight1 focused
        let layers = layeringManager.calculateLayering(
            flights: flights,
            positions: positions,
            distances: distances,
            focusedFlightId: "1"
        )
        
        // Find layers for each flight
        let layer1 = layers.first { $0.flight.id == "1" }
        let layer2 = layers.first { $0.flight.id == "2" }
        
        XCTAssertNotNil(layer1)
        XCTAssertNotNil(layer2)
        
        // Focused aircraft should have highest z-index
        XCTAssertEqual(layer1?.zIndex, 1000)
        XCTAssertTrue((layer1?.zIndex ?? 0) > (layer2?.zIndex ?? 0))
        
        // Focused aircraft should have full opacity
        XCTAssertEqual(layer1?.opacity, 1.0)
        
        // Non-focused overlapping aircraft should have reduced opacity
        XCTAssertEqual(layer2?.opacity, 0.7)
    }
    
    func testCloserAircraftHasHigherPriorityWhenNoneFocused() {
        // Create test flights
        let flight1 = createTestFlight(id: "1", distance: 10.0)
        let flight2 = createTestFlight(id: "2", distance: 5.0) // Closer
        let flights = [flight1, flight2]
        
        // Create overlapping positions
        let positions = [
            "1": CGPoint(x: 100, y: 100),
            "2": CGPoint(x: 105, y: 105) // Overlapping
        ]
        
        let distances = [
            "1": 10.0,
            "2": 5.0
        ]
        
        // Calculate layering with no focused flight
        let layers = layeringManager.calculateLayering(
            flights: flights,
            positions: positions,
            distances: distances,
            focusedFlightId: nil
        )
        
        // Find layers for each flight
        let layer1 = layers.first { $0.flight.id == "1" }
        let layer2 = layers.first { $0.flight.id == "2" }
        
        XCTAssertNotNil(layer1)
        XCTAssertNotNil(layer2)
        
        // Closer aircraft should have higher z-index
        XCTAssertTrue((layer2?.zIndex ?? 0) > (layer1?.zIndex ?? 0))
        
        // Closer aircraft should have full opacity
        XCTAssertEqual(layer2?.opacity, 1.0)
        
        // Farther aircraft should have reduced opacity
        XCTAssertEqual(layer1?.opacity, 0.7)
    }
    
    func testNonOverlappingAircraftHaveFullOpacity() {
        // Create test flights
        let flight1 = createTestFlight(id: "1", distance: 10.0)
        let flight2 = createTestFlight(id: "2", distance: 5.0)
        let flights = [flight1, flight2]
        
        // Create non-overlapping positions
        let positions = [
            "1": CGPoint(x: 100, y: 100),
            "2": CGPoint(x: 200, y: 200) // Not overlapping
        ]
        
        let distances = [
            "1": 10.0,
            "2": 5.0
        ]
        
        // Calculate layering
        let layers = layeringManager.calculateLayering(
            flights: flights,
            positions: positions,
            distances: distances,
            focusedFlightId: nil
        )
        
        // Both should have full opacity since they don't overlap
        for layer in layers {
            XCTAssertEqual(layer.opacity, 1.0)
        }
    }
    
    // MARK: - Helper Methods
    
    private func createTestFlight(id: String, distance: Double) -> FlightData {
        return FlightData(
            id: id,
            flightNumber: "TEST\(id)",
            callsign: nil,
            airline: nil,
            aircraft: nil,
            route: nil,
            position: FlightPosition(
                latitude: 37.7749,
                longitude: -122.4194,
                altitude: 35000,
                speed: 500,
                heading: 90
            ),
            lastUpdated: Date()
        )
    }
}
#endif
