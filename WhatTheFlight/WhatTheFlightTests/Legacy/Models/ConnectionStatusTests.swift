// Legacy: only the macOS (and visionOS) app runs this. iOS, tvOS and watchOS run radar v2;
// see Enhancements Spec B4. Delete with the rest of Legacy/ once the Mac runs the iPad app (C11).
#if os(macOS) || os(visionOS)
//
//  ConnectionStatusTests.swift
//  WhatTheFlightTests
//
//  Created by Kiro on 8/1/25.
//

import XCTest
@testable import WhatTheFlight

final class ConnectionStatusTests: XCTestCase {
    
    func testConnectionStatusDescriptions() {
        XCTAssertEqual(ConnectionStatus.disconnected.description, "Disconnected")
        XCTAssertEqual(ConnectionStatus.connecting.description, "Connecting...")
        XCTAssertEqual(ConnectionStatus.connected.description, "Connected")
        XCTAssertEqual(ConnectionStatus.rateLimited.description, "Rate Limited")
        XCTAssertEqual(ConnectionStatus.error("Network timeout").description, "Error: Network timeout")
    }
    
    func testIsConnected() {
        XCTAssertTrue(ConnectionStatus.connected.isConnected)
        XCTAssertFalse(ConnectionStatus.disconnected.isConnected)
        XCTAssertFalse(ConnectionStatus.connecting.isConnected)
        XCTAssertFalse(ConnectionStatus.rateLimited.isConnected)
        XCTAssertFalse(ConnectionStatus.error("Test error").isConnected)
    }
    
    func testIsError() {
        XCTAssertTrue(ConnectionStatus.error("Test error").isError)
        XCTAssertTrue(ConnectionStatus.rateLimited.isError)
        XCTAssertFalse(ConnectionStatus.connected.isError)
        XCTAssertFalse(ConnectionStatus.disconnected.isError)
        XCTAssertFalse(ConnectionStatus.connecting.isError)
    }
    
    func testIsConnecting() {
        XCTAssertTrue(ConnectionStatus.connecting.isConnecting)
        XCTAssertFalse(ConnectionStatus.connected.isConnecting)
        XCTAssertFalse(ConnectionStatus.disconnected.isConnecting)
        XCTAssertFalse(ConnectionStatus.rateLimited.isConnecting)
        XCTAssertFalse(ConnectionStatus.error("Test error").isConnecting)
    }
    
    func testStatusColor() {
        XCTAssertEqual(ConnectionStatus.disconnected.statusColor, "gray")
        XCTAssertEqual(ConnectionStatus.connecting.statusColor, "yellow")
        XCTAssertEqual(ConnectionStatus.connected.statusColor, "green")
        XCTAssertEqual(ConnectionStatus.rateLimited.statusColor, "red")
        XCTAssertEqual(ConnectionStatus.error("Test error").statusColor, "red")
    }
    
    func testEquality() {
        XCTAssertEqual(ConnectionStatus.disconnected, ConnectionStatus.disconnected)
        XCTAssertEqual(ConnectionStatus.connecting, ConnectionStatus.connecting)
        XCTAssertEqual(ConnectionStatus.connected, ConnectionStatus.connected)
        XCTAssertEqual(ConnectionStatus.rateLimited, ConnectionStatus.rateLimited)
        XCTAssertEqual(ConnectionStatus.error("Same message"), ConnectionStatus.error("Same message"))
        
        XCTAssertNotEqual(ConnectionStatus.connected, ConnectionStatus.disconnected)
        XCTAssertNotEqual(ConnectionStatus.error("Message 1"), ConnectionStatus.error("Message 2"))
        XCTAssertNotEqual(ConnectionStatus.error("Test"), ConnectionStatus.rateLimited)
    }
    
    func testAllCases() {
        let allCases = ConnectionStatus.allCases
        XCTAssertEqual(allCases.count, 4)
        XCTAssertTrue(allCases.contains(.disconnected))
        XCTAssertTrue(allCases.contains(.connecting))
        XCTAssertTrue(allCases.contains(.connected))
        XCTAssertTrue(allCases.contains(.rateLimited))
    }
}
#endif
