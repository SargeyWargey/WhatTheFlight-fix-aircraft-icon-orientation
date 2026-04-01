//
//  NotificationSettings.swift
//  WhatTheFlight
//
//  Created by Kiro on 8/1/25.
//

import Foundation

struct NotificationSettings: Codable, Equatable {
    var flightDetectionEnabled: Bool
    var connectionStatusEnabled: Bool
    var errorAlertsEnabled: Bool
    var soundEnabled: Bool
    var badgeEnabled: Bool
    
    init(flightDetectionEnabled: Bool = true,
         connectionStatusEnabled: Bool = false,
         errorAlertsEnabled: Bool = true,
         soundEnabled: Bool = true,
         badgeEnabled: Bool = false) {
        self.flightDetectionEnabled = flightDetectionEnabled
        self.connectionStatusEnabled = connectionStatusEnabled
        self.errorAlertsEnabled = errorAlertsEnabled
        self.soundEnabled = soundEnabled
        self.badgeEnabled = badgeEnabled
    }
    
    static let `default` = NotificationSettings()
    
    /// Returns true if any notifications are enabled
    var hasNotificationsEnabled: Bool {
        return flightDetectionEnabled || connectionStatusEnabled || errorAlertsEnabled
    }
}

enum NotificationType: String, CaseIterable {
    case flightDetected = "flightDetected"
    case connectionLost = "connectionLost"
    case connectionRestored = "connectionRestored"
    case apiError = "apiError"
    case rateLimitExceeded = "rateLimitExceeded"
    
    var title: String {
        switch self {
        case .flightDetected:
            return "Flight Detected"
        case .connectionLost:
            return "Connection Lost"
        case .connectionRestored:
            return "Connection Restored"
        case .apiError:
            return "API Error"
        case .rateLimitExceeded:
            return "Rate Limit Exceeded"
        }
    }
    
    var identifier: String {
        return "com.whattheflight.\(rawValue)"
    }
}