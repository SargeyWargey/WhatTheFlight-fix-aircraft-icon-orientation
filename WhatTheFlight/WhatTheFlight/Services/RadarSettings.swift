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

    /// Apple TV: the radar face, the radar with the live map beside it, or the map alone. The
    /// dock's view button steps through them in this order.
    enum TVView: String, CaseIterable, Identifiable {
        case radar, split, map
        var id: String { rawValue }

        var title: String {
            switch self {
            case .radar: return "Radar"
            case .split: return "Split"
            case .map: return "Map"
            }
        }

        var symbol: String {
            switch self {
            case .radar: return "scope"
            case .split: return "rectangle.split.2x1.fill"
            case .map: return "map.fill"
            }
        }

        var next: TVView {
            let all = Self.allCases
            return all[(all.firstIndex(of: self)! + 1) % all.count]
        }
    }

    /// Apple TV: what the live map is drawn on. MapKit has no topographic style.
    enum MapType: String, CaseIterable, Identifiable {
        case standard, satellite, hybrid
        var id: String { rawValue }

        var title: String {
            switch self {
            case .standard: return "Standard"
            case .satellite: return "Satellite"
            case .hybrid: return "Hybrid"
            }
        }
    }

    /// The contour map behind the radar, drawn by `TopographyRenderer`: one generated terrain,
    /// read four ways. Survey is the default.
    enum TopographyStyle: String, CaseIterable, Identifiable {
        case off, remaster, survey, highlands, relief
        var id: String { rawValue }

        var title: String {
            switch self {
            case .off: return "Off"
            case .remaster: return "Remaster"
            case .survey: return "Survey"
            case .highlands: return "Highlands"
            case .relief: return "Relief"
            }
        }

        var subtitle: String {
            switch self {
            case .off: return "Plain paper"
            case .remaster: return "Big gentle hills, one line weight"
            case .survey: return "A survey map, every fifth line heavier"
            case .highlands: return "Ridges and winding valleys, the most detail"
            case .relief: return "Survey lines over faint hill shading"
            }
        }
    }

    /// Tide: the ground stays put while the contour heights creep, so lines slowly flow out
    /// of the hilltops. 1× moves one line spacing every 20 seconds.
    enum TopographyMotion: String, CaseIterable, Identifiable {
        case off, half, normal, double
        var id: String { rawValue }

        var title: String {
            switch self {
            case .off: return "Off"
            case .half: return "0.5×"
            case .normal: return "1×"
            case .double: return "2×"
            }
        }

        var speed: Double {
            switch self {
            case .off: return 0
            case .half: return 0.5
            case .normal: return 1
            case .double: return 2
            }
        }
    }

    /// Apple TV: the map's own ranges; nil (first) follows the radar's.
    static let mapRadiusChoices: [Double?] = [nil, 2, 5, 10, 15, 20, 30, 50]

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
    /// The contours behind the radar; Off is plain paper.
    var topography: TopographyStyle { didSet { save(topography.rawValue, .topography) } }
    /// How fast the main radar's contours creep (Tide). Every other screen keeps them still.
    var topographyMotion: TopographyMotion { didSet { save(topographyMotion.rawValue, .topographyMotion) } }
    /// Whether any contours show (what the TV's secondary screens pass along).
    var showTopography: Bool { topography != .off }
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
    /// How long before the aircraft passes closest the overhead alert goes off, in seconds.
    var overheadAlertLeadSeconds: Double { didSet { save(overheadAlertLeadSeconds, .overheadAlertLead) } }
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
    /// iPhone: Sky View photos also go to the camera roll at full resolution.
    var skySaveToPhotos: Bool { didSet { save(skySaveToPhotos, .skySaveToPhotos) } }
    /// The ambient map: the Split and Map views on the TV, a map pane beside the radar on iPad
    /// in landscape and the iPhone Duo half open, and the bar's Map button everywhere else on
    /// iPhone and iPad. Off, nothing else changes.
    var mapView: Bool { didSet { save(mapView, .mapView) } }
    /// iPhone / iPad: the live map in place of the radar (the bar's Map / Radar button), when
    /// there's no map pane beside it. Remembered, like the TV's view.
    var mapScreen: Bool { didSet { save(mapScreen, .mapScreen) } }
    /// Apple TV: which view is showing. Read it through `effectiveTVView`.
    var tvView: TVView { didSet { save(tvView.rawValue, .tvView) } }
    /// The map turns so "up" is the TV's facing direction, like the radar. On = north up.
    var mapNorthUp: Bool { didSet { save(mapNorthUp, .mapNorthUp) } }
    /// Apple TV: how far the map reaches, independent of the radar. nil = the radar's radius.
    /// Read it as `effectiveMapRadius`.
    var mapRadiusMiles: Double? { didSet { save(mapRadiusMiles, .mapRadius) } }
    /// Apple TV: standard, satellite or hybrid.
    var mapType: MapType { didSet { save(mapType.rawValue, .mapType) } }
    /// Aircraft followed wherever they are, oldest first. Edit through `RadarModel.pin` / `unpin`.
    var pinnedAircraft: [PinnedAircraft] {
        didSet {
            save(try? JSONEncoder().encode(pinnedAircraft), .pinnedAircraft)
            onPinnedAircraftChange?(oldValue)
        }
    }
    /// `PinSync` listens here to send local pin changes to iCloud; gets the old list.
    @ObservationIgnored var onPinnedAircraftChange: ((_ old: [PinnedAircraft]) -> Void)?

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
        #if os(tvOS)
        // Apple TV has no switch for it: helicopters always show.
        showHelicopters = true
        #else
        showHelicopters = value(.showHelicopters, true)
        #endif
        // Before styles this was one switch; anyone who turned it off stays off.
        let hadTopographyOff = defaults.object(forKey: Key.showTopography.name) != nil && !defaults.bool(forKey: Key.showTopography.name)
        topography = TopographyStyle(rawValue: value(.topography, hadTopographyOff ? "off" : "survey")) ?? .survey
        topographyMotion = TopographyMotion(rawValue: value(.topographyMotion, "normal")) ?? .normal
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
        overheadAlertLeadSeconds = value(.overheadAlertLead, 150.0).clamped(to: Self.overheadAlertLeadRange)
        notableAlerts = value(.notableAlerts, true)
        spokenAlerts = value(.spokenAlerts, false)
        keepLogbook = value(.keepLogbook, true)
        syncLogbook = value(.syncLogbook, true)
        raiseToSkyView = value(.raiseToSkyView, true)
        skySaveToPhotos = value(.skySaveToPhotos, true)
        mapView = value(.mapView, true)
        mapScreen = value(.mapScreen, false)
        tvView = TVView(rawValue: value(.tvView, "radar")) ?? .radar
        mapNorthUp = value(.mapNorthUp, false)
        mapRadiusMiles = optionalDouble(.mapRadius)?.clamped(to: Self.radiusRange)
        mapType = MapType(rawValue: value(.mapType, "standard")) ?? .standard
        pinnedAircraft = defaults.data(forKey: Key.pinnedAircraft.name)
            .flatMap { try? JSONDecoder().decode([PinnedAircraft].self, from: $0) } ?? []
    }

    /// The TV's view, treated as the radar whenever the map is switched off.
    var effectiveTVView: TVView { mapView ? tvView : .radar }

    /// The map's radius: its own, or the radar's.
    var effectiveMapRadius: Double { mapRadiusMiles ?? radiusMiles }

    static let overheadAlertRange: ClosedRange<Double> = 0.5...5
    static let overheadAlertLeadRange: ClosedRange<Double> = 30...600

    var alertRules: TrafficAlertRules {
        TrafficAlertRules(overhead: overheadAlerts, notable: notableAlerts, overheadMiles: overheadAlertMiles,
                          leadSeconds: overheadAlertLeadSeconds)
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
        topography = .survey
        topographyMotion = .normal
        showCompassBezel = true
        radarSweep = true
        showPhotos = true
        hapticsEnabled = true
        keepScreenAwake = false
        demoTraffic = false
        overheadAlerts = true
        overheadAlertMiles = 1.5
        overheadAlertLeadSeconds = 150
        notableAlerts = true
        spokenAlerts = false
        keepLogbook = true
        syncLogbook = true
        raiseToSkyView = true
        skySaveToPhotos = true
        mapView = true
        mapScreen = false
        tvView = .radar
        mapNorthUp = false
        mapRadiusMiles = nil
        mapType = .standard
    }

    // MARK: - Persistence

    private enum Key: String {
        case radius, refresh, locationMode, customLatitude, customLongitude, appearance
        // `showTopography` is only read, to carry an old "off" over to `topography`.
        case showHelicopters, showTopography, topography, topographyMotion, showCompassBezel, radarSweep, showPhotos
        case haptics, keepAwake, demoTraffic, hasSeenWelcome, customPlaceName, tvFacing
        case overheadAlerts, overheadAlertMiles, overheadAlertLead, notableAlerts, spokenAlerts, keepLogbook, raiseToSkyView
        case mapView, mapScreen, tvView, mapNorthUp, mapRadius, mapType, skySaveToPhotos, pinnedAircraft
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
