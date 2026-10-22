//
//  RadarSettings.swift
//  WhatTheFlight
//
//  User preferences, persisted to UserDefaults. Any key can be overridden at launch,
//  e.g. `-wtf.demoTraffic YES` (used by UI tests and screenshots).
//

import Foundation
import Observation
import SwiftUI
import CoreLocation

@MainActor
@Observable
final class RadarSettings {
    enum LocationMode: String, CaseIterable, Identifiable {
        case device, custom
        var id: String { rawValue }
        var title: String { self == .device ? "My Location" : "Custom Spot" }
    }

    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
    }

    static let radiusRange: ClosedRange<Double> = 2...100
    /// The Watch watches a tighter circle: roughly what you can see from where you stand.
    #if os(watchOS)
    static let defaultRadius: Double = 10
    #else
    static let defaultRadius: Double = 20
    #endif
    static let refreshRange: ClosedRange<Double> = 5...60

    var radiusMiles: Double { didSet { save(radiusMiles, .radius) } }
    var refreshSeconds: Double { didSet { save(refreshSeconds, .refresh) } }
    var locationMode: LocationMode { didSet { save(locationMode.rawValue, .locationMode) } }
    var customLatitude: Double? { didSet { save(customLatitude, .customLatitude) } }
    var customLongitude: Double? { didSet { save(customLongitude, .customLongitude) } }
    var appearance: Appearance { didSet { save(appearance.rawValue, .appearance) } }
    var showHelicopters: Bool { didSet { save(showHelicopters, .showHelicopters) } }
    var showTopography: Bool { didSet { save(showTopography, .showTopography) } }
    var showCompassBezel: Bool { didSet { save(showCompassBezel, .showCompassBezel) } }
    var radarSweep: Bool { didSet { save(radarSweep, .radarSweep) } }
    var showPhotos: Bool { didSet { save(showPhotos, .showPhotos) } }
    var hapticsEnabled: Bool { didSet { save(hapticsEnabled, .haptics) } }
    var keepScreenAwake: Bool { didSet { save(keepScreenAwake, .keepAwake) } }
    var demoTraffic: Bool { didSet { save(demoTraffic, .demoTraffic) } }
    var hasSeenWelcome: Bool { didSet { save(hasSeenWelcome, .hasSeenWelcome) } }
    /// Human-readable name for the custom spot ("Atlanta, GA"), when known.
    var customPlaceName: String? { didSet { save(customPlaceName, .customPlaceName) } }
    /// Apple TV only: the compass direction you face when watching the TV, i.e. "up" on screen.
    var tvFacingDegrees: Double { didSet { save(tvFacingDegrees, .tvFacing) } }
    /// Heads-up when an aircraft is about to pass overhead.
    var overheadAlerts: Bool { didSet { save(overheadAlerts, .overheadAlerts) } }
    /// How close counts as "overhead", in miles.
    var overheadAlertMiles: Double { didSet { save(overheadAlertMiles, .overheadAlertMiles) } }
    /// Heads-up for emergencies, military, air ambulances and rare types.
    var notableAlerts: Bool { didSet { save(notableAlerts, .notableAlerts) } }
    /// Apple TV: read alerts aloud as well as showing the banner.
    var spokenAlerts: Bool { didSet { save(spokenAlerts, .spokenAlerts) } }
    /// Record every aircraft that comes inside the radius.
    var keepLogbook: Bool { didSet { save(keepLogbook, .keepLogbook) } }
    /// Merge the logbook with your other devices through iCloud.
    var syncLogbook: Bool { didSet { save(syncLogbook, .syncLogbook) } }
    /// iPhone: lifting the phone to the sky opens Sky View.
    var raiseToSkyView: Bool { didSet { save(raiseToSkyView, .raiseToSkyView) } }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Typed accessors so launch-argument strings ("YES", "25") are understood too.
        func value(_ key: Key, _ fallback: Bool) -> Bool {
            defaults.object(forKey: key.name) == nil ? fallback : defaults.bool(forKey: key.name)
        }
        func value(_ key: Key, _ fallback: Double) -> Double {
            defaults.object(forKey: key.name) == nil ? fallback : defaults.double(forKey: key.name)
        }
        func value(_ key: Key, _ fallback: String) -> String {
            defaults.string(forKey: key.name) ?? fallback
        }
        radiusMiles = value(.radius, Self.defaultRadius).clamped(to: Self.radiusRange)
        refreshSeconds = value(.refresh, 10.0).clamped(to: Self.refreshRange)
        locationMode = LocationMode(rawValue: value(.locationMode, "device")) ?? .device
        func optionalDouble(_ key: Key) -> Double? {
            defaults.object(forKey: key.name) == nil ? nil : defaults.double(forKey: key.name)
        }
        customLatitude = optionalDouble(.customLatitude)
        customLongitude = optionalDouble(.customLongitude)
        appearance = Appearance(rawValue: value(.appearance, "system")) ?? .system
        showHelicopters = value(.showHelicopters, true)
        showTopography = value(.showTopography, true)
        showCompassBezel = value(.showCompassBezel, true)
        radarSweep = value(.radarSweep, true)
        showPhotos = value(.showPhotos, true)
        hapticsEnabled = value(.haptics, true)
        keepScreenAwake = value(.keepAwake, false)
        demoTraffic = value(.demoTraffic, false)
        hasSeenWelcome = value(.hasSeenWelcome, false)
        customPlaceName = defaults.string(forKey: Key.customPlaceName.name)
        tvFacingDegrees = GeoMath.normalize(value(.tvFacing, 0.0))
        overheadAlerts = value(.overheadAlerts, true)
        overheadAlertMiles = value(.overheadAlertMiles, 1.5).clamped(to: Self.overheadAlertRange)
        notableAlerts = value(.notableAlerts, true)
        spokenAlerts = value(.spokenAlerts, false)
        keepLogbook = value(.keepLogbook, true)
        syncLogbook = value(.syncLogbook, true)
        raiseToSkyView = value(.raiseToSkyView, true)
    }

    static let overheadAlertRange: ClosedRange<Double> = 0.5...5

    var alertRules: TrafficAlertRules {
        TrafficAlertRules(overhead: overheadAlerts, notable: notableAlerts, overheadMiles: overheadAlertMiles)
    }

    var customCoordinate: CLLocationCoordinate2D? {
        get {
            guard let lat = customLatitude, let lon = customLongitude else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        set {
            customLatitude = newValue?.latitude
            customLongitude = newValue?.longitude
            customPlaceName = nil
        }
    }

    func resetToDefaults() {
        radiusMiles = Self.defaultRadius
        refreshSeconds = 10
        appearance = .system
        showHelicopters = true
        showTopography = true
        showCompassBezel = true
        radarSweep = true
        showPhotos = true
        hapticsEnabled = true
        keepScreenAwake = false
        demoTraffic = false
        overheadAlerts = true
        overheadAlertMiles = 1.5
        notableAlerts = true
        spokenAlerts = false
        keepLogbook = true
        syncLogbook = true
        raiseToSkyView = true
    }

    // MARK: - Persistence

    private enum Key: String {
        case radius, refresh, locationMode, customLatitude, customLongitude, appearance
        case showHelicopters, showTopography, showCompassBezel, radarSweep, showPhotos
        case haptics, keepAwake, demoTraffic, hasSeenWelcome, customPlaceName, tvFacing
        case overheadAlerts, overheadAlertMiles, notableAlerts, spokenAlerts, keepLogbook, raiseToSkyView
        case syncLogbook = "iCloudLogbook"

        var name: String { "wtf.\(rawValue)" }
    }

    private func save(_ value: Any?, _ key: Key) {
        if let value { defaults.set(value, forKey: key.name) } else { defaults.removeObject(forKey: key.name) }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
