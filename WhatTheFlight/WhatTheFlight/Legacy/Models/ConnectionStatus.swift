//
//  ConnectionStatus.swift
//  WhatTheFlight
//
//  Created by Kiro on 8/1/25.
//

import Foundation

enum ConnectionStatus: Equatable, CaseIterable {
    case disconnected
    case connecting
    case connected
    case error(String)
    case rateLimited
    
    static var allCases: [ConnectionStatus] {
        return [.disconnected, .connecting, .connected, .rateLimited]
    }
    
    /// Human-readable description of the connection status
    var description: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting..."
        case .connected:
            return "Connected"
        case .error(let message):
            return "Error: \(message)"
        case .rateLimited:
            return "Rate Limited"
        }
    }
    
    /// Returns true if the status indicates a successful connection
    var isConnected: Bool {
        switch self {
        case .connected:
            return true
        default:
            return false
        }
    }
    
    /// Returns true if the status indicates an error state
    var isError: Bool {
        switch self {
        case .error, .rateLimited:
            return true
        default:
            return false
        }
    }
    
    /// Returns true if the status indicates the system is attempting to connect
    var isConnecting: Bool {
        switch self {
        case .connecting:
            return true
        default:
            return false
        }
    }
    
    /// Color representation for UI display
    var statusColor: String {
        switch self {
        case .disconnected:
            return "gray"
        case .connecting:
            return "yellow"
        case .connected:
            return "green"
        case .error, .rateLimited:
            return "red"
        }
    }
}

// MARK: - Equatable Implementation
extension ConnectionStatus {
    static func == (lhs: ConnectionStatus, rhs: ConnectionStatus) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
             (.connecting, .connecting),
             (.connected, .connected),
             (.rateLimited, .rateLimited):
            return true
        case (.error(let lhsMessage), .error(let rhsMessage)):
            return lhsMessage == rhsMessage
        default:
            return false
        }
    }
}