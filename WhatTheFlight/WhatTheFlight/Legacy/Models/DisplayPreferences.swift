// Legacy: only the macOS (and visionOS) app runs this. iOS, tvOS and watchOS run radar v2;
// see Enhancements Spec B4. Delete with the rest of Legacy/ once the Mac runs the iPad app (C11).
#if os(macOS) || os(visionOS)
//
//  DisplayPreferences.swift
//  WhatTheFlight
//
//  Created by Kiro on 8/1/25.
//

import Foundation
import SwiftUI

struct DisplayPreferences: Codable, Equatable {
    var textSize: TextSize
    var colorTheme: ColorTheme
    var informationDensity: InformationDensity
    var animationsEnabled: Bool
    var showAltitude: Bool
    var showSpeed: Bool
    var showHeading: Bool
    var tvOSOrientation: TVOSOrientation
    var tvOSOrientationDegrees: Double
    var proximityDistanceThreshold: Double
    var tvOSSafeAreaMultiplier: Double
    
    init(textSize: TextSize = .medium,
         colorTheme: ColorTheme = .system,
         informationDensity: InformationDensity = .normal,
         animationsEnabled: Bool = true,
         showAltitude: Bool = true,
         showSpeed: Bool = true,
         showHeading: Bool = false,
         tvOSOrientation: TVOSOrientation = .north,
         tvOSOrientationDegrees: Double = 0.0,
         proximityDistanceThreshold: Double = 3.0,
         tvOSSafeAreaMultiplier: Double = 1.0) {
        self.textSize = textSize
        self.colorTheme = colorTheme
        self.informationDensity = informationDensity
        self.animationsEnabled = animationsEnabled
        self.showAltitude = showAltitude
        self.showSpeed = showSpeed
        self.showHeading = showHeading
        self.tvOSOrientation = tvOSOrientation
        self.tvOSOrientationDegrees = tvOSOrientationDegrees
        self.proximityDistanceThreshold = proximityDistanceThreshold
        self.tvOSSafeAreaMultiplier = tvOSSafeAreaMultiplier
    }
    
    static let `default` = DisplayPreferences()
}

enum TextSize: String, Codable, CaseIterable {
    case small = "small"
    case medium = "medium"
    case large = "large"
    case extraLarge = "extraLarge"
    
    var displayName: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .extraLarge: return "Extra Large"
        }
    }
    
    var scaleFactor: CGFloat {
        switch self {
        case .small: return 0.8
        case .medium: return 1.0
        case .large: return 1.2
        case .extraLarge: return 1.4
        }
    }
}

enum ColorTheme: String, Codable, CaseIterable {
    case system = "system"
    case light = "light"
    case dark = "dark"
    case highContrast = "highContrast"
    
    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        case .highContrast: return "High Contrast"
        }
    }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        case .highContrast: return .dark
        }
    }
}

enum InformationDensity: String, Codable, CaseIterable {
    case compact = "compact"
    case normal = "normal"
    case comfortable = "comfortable"
    
    var displayName: String {
        switch self {
        case .compact: return "Compact"
        case .normal: return "Normal"
        case .comfortable: return "Comfortable"
        }
    }
    
    var spacing: CGFloat {
        switch self {
        case .compact: return 8
        case .normal: return 12
        case .comfortable: return 16
        }
    }
    
    var padding: CGFloat {
        switch self {
        case .compact: return 8
        case .normal: return 12
        case .comfortable: return 20
        }
    }
}

enum TVOSOrientation: String, Codable, CaseIterable {
    case north = "north"
    case northeast = "northeast"
    case east = "east"
    case southeast = "southeast"
    case south = "south"
    case southwest = "southwest"
    case west = "west"
    case northwest = "northwest"
    case northnortheast = "northnortheast"
    case eastnortheast = "eastnortheast"
    case eastsoutheast = "eastsoutheast"
    case southsoutheast = "southsoutheast"
    case southsouthwest = "southsouthwest"
    case westsouthwest = "westsouthwest"
    case westnorthwest = "westnorthwest"
    case northnorthwest = "northnorthwest"
    
    var displayName: String {
        switch self {
        case .north: return "N"
        case .northeast: return "NE"
        case .east: return "E"
        case .southeast: return "SE"
        case .south: return "S"
        case .southwest: return "SW"
        case .west: return "W"
        case .northwest: return "NW"
        case .northnortheast: return "NNE"
        case .eastnortheast: return "ENE"
        case .eastsoutheast: return "ESE"
        case .southsoutheast: return "SSE"
        case .southsouthwest: return "SSW"
        case .westsouthwest: return "WSW"
        case .westnorthwest: return "WNW"
        case .northnorthwest: return "NNW"
        }
    }
    
    var degrees: Double {
        switch self {
        case .north: return 0
        case .northnortheast: return 22.5
        case .northeast: return 45
        case .eastnortheast: return 67.5
        case .east: return 90
        case .eastsoutheast: return 112.5
        case .southeast: return 135
        case .southsoutheast: return 157.5
        case .south: return 180
        case .southsouthwest: return 202.5
        case .southwest: return 225
        case .westsouthwest: return 247.5
        case .west: return 270
        case .westnorthwest: return 292.5
        case .northwest: return 315
        case .northnorthwest: return 337.5
        }
    }
}
#endif
