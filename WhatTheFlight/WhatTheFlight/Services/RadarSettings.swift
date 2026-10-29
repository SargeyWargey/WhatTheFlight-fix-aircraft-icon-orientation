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

/// A named place to watch from: Home, the office, the airport fence (Enhancements Spec C8).
/// Watching one sets the custom spot, so the rest of the app is unchanged.
struct SavedSpot: Codable, Hashable, Identifiable, Sendable {
    var id: String = UUID().uuidString
    var name: String
    var latitude: Double
    var longitude: Double

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }

    init(id: String = UUID().uuidString, name: String, coordinate: CLLocationCoordinate2D) {
        self.id = id
        self.name = name
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }

    /// Within about 100 m: the same place.
    func isAt(_ coordinate: CLLocationCoordinate2D?) -> Bool {
        guard let coordinate else { return false }
        return GeoMath.distanceMiles(from: self.coordinate, to: coordinate) < 0.06
    }
}

@MainActor
@Observable
final class RadarSettings {
    enum LocationMode: String, CaseIterable, Identifiable {
        case device, custom
        var id: String { rawValue }
        var title: String { self == .device ? String(localized: "My Location") : String(localized: "Custom Spot") }
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
            case .radar: return String(localized: "Radar")
            case .split: return String(localized: "Split")
            case .map: return String(localized: "Map")
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
            case .standard: return String(localized: "Standard")
            case .satellite: return String(localized: "Satellite")
            case .hybrid: return String(localized: "Hybrid")
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
            case .off: return String(localized: "Off")
            case .remaster: return String(localized: "Remaster")
            case .survey: return String(localized: "Survey")
            case .highlands: return String(localized: "Highlands")
            case .relief: return String(localized: "Relief")
            }
        }

        var subtitle: String {
            switch self {
            case .off: return String(localized: "Plain paper")
            case .remaster: return String(localized: "Big gentle hills, one line weight")
            case .survey: return String(localized: "A survey map, every fifth line heavier")
            case .highlands: return String(localized: "Ridges and winding valleys, the most detail")
            case .relief: return String(localized: "Survey lines over faint hill shading")
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
            case .off: return String(localized: "Off")
            case .half: return String(localized: "0.5×")
            case .normal: return String(localized: "1×")
            case .double: return String(localized: "2×")
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

    var radiusMiles: Double { didSet { save(radiusMiles, .radius) } }
    /// Where live traffic comes from: Flightradar24 with adsb.lol behind it, or just one.
    var dataSource: DataSourcePreference {
        didSet {
            save(dataSource.rawValue, .dataSource)
            SharedRadarStore().dataSource = dataSource
        }
    }
    /// Miles, feet and knots, or kilometers, meters and km/h. Only what's shown changes.
    var units: UnitSystem {
        didSet {
            save(units.rawValue, .units)
            Units.adopt(units)
        }
    }
    var locationMode: LocationMode { didSet { save(locationMode.rawValue, .locationMode) } }
    var customLatitude: Double? { didSet { save(customLatitude, .customLatitude) } }
    var customLongitude: Double? { didSet { save(customLongitude, .customLongitude) } }
    var appearance: Appearance { didSet { save(appearance.rawValue, .appearance) } }
    var showHelicopters: Bool { didSet { save(showHelicopters, .showHelicopters) } }
    /// The nearest aircraft you can actually see takes the centre, ahead of nearer ones above
    /// the clouds or too far to make out.
    var preferVisible: Bool { didSet { save(preferVisible, .preferVisible) } }
    /// "Above the clouds", "Too far away to make out" under the type on the radar's centre,
    /// and "Can you see it?" on the details.
    var showsVisibility: Bool { didSet { save(showsVisibility, .showsVisibility) } }
    /// Clouds and fog drawn over the radar and the map where the weather reports put them.
    var weatherFog: Bool { didSet { save(weatherFog, .weatherFog) } }
    /// Anything here needs the weather reports.
    var usesWeather: Bool { showsVisibility || preferVisible || weatherFog }
    /// The contours behind the radar; Off is plain paper.
    var topography: TopographyStyle { didSet { save(topography.rawValue, .topography) } }
    /// How fast the main radar's contours creep (Tide). Every other screen keeps them still.
    var topographyMotion: TopographyMotion { didSet { save(topographyMotion.rawValue, .topographyMotion) } }
    /// Whether any contours show (what the TV's secondary screens pass along).
    var showTopography: Bool { topography != .off }
    var showCompassBezel: Bool { didSet { save(showCompassBezel, .showCompassBezel) } }
    var radarSweep: Bool { didSet { save(radarSweep, .radarSweep) } }
    var showPhotos: Bool { didSet { save(showPhotos, .showPhotos) } }
    /// The airframe's maker, variant and registered owner (organisations only) on its details,
    /// from adsbdb. Off, no lookups at all.
    var aircraftFacts: Bool { didSet { save(aircraftFacts, .aircraftFacts) } }
    /// The aircraft's photo on the radar's centre and the map card. Off unless turned on;
    /// Sky View's card shows it whenever Aircraft photos is on.
    var cardPhotos: Bool { didSet { save(cardPhotos, .cardPhotos) } }
    /// Card photos on, and Planespotters photos on at all.
    var showsCardPhotos: Bool { showPhotos && cardPhotos }
    var hapticsEnabled: Bool { didSet { save(hapticsEnabled, .haptics) } }
    var keepScreenAwake: Bool { didSet { save(keepScreenAwake, .keepAwake) } }
    var demoTraffic: Bool { didSet { save(demoTraffic, .demoTraffic) } }
    var hasSeenWelcome: Bool { didSet { save(hasSeenWelcome, .hasSeenWelcome) } }
    /// Human-readable name for the custom spot ("Atlanta, GA"), when known.
    var customPlaceName: String? { didSet { save(customPlaceName, .customPlaceName) } }
    /// Named places to watch from, in the order they were saved.
    var savedSpots: [SavedSpot] { didSet { save(try? JSONEncoder().encode(savedSpots), .savedSpots) } }
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
    /// Read alerts aloud as well as showing the banner (Apple TV), or the notification
    /// (iPhone, also while Sky Watch runs with the phone locked).
    var spokenAlerts: Bool { didSet { save(spokenAlerts, .spokenAlerts) } }
    /// iPhone: only read alerts aloud through headphones, AirPods or the car.
    var spokenAlertsHeadphonesOnly: Bool { didSet { save(spokenAlertsHeadphonesOnly, .spokenAlertsHeadphonesOnly) } }
    /// Tail numbers, types, airlines and callsigns to be told about.
    var watchlist: [WatchlistRule] { didSet { save(try? JSONEncoder().encode(watchlist), .watchlist) } }
    /// A favourite or pinned aircraft coming into range.
    var favoriteAlerts: Bool { didSet { save(favoriteAlerts, .favoriteAlerts) } }
    /// The first of a type or airline in the logbook.
    var firstSeenAlerts: Bool { didSet { save(firstSeenAlerts, .firstSeenAlerts) } }
    /// Record every aircraft that comes inside the radius.
    var keepLogbook: Bool { didSet { save(keepLogbook, .keepLogbook) } }
    /// iPhone: an evening notification about the day's sky, on days something was logged.
    var dailyDigest: Bool { didSet { save(dailyDigest, .dailyDigest) } }
    /// When the digest goes out, minutes after midnight.
    var digestMinutes: Int { didSet { save(digestMinutes, .digestMinutes) } }
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
    /// Aircraft called out in yellow wherever they turn up, oldest first. Edit through
    /// `RadarModel.favorite` / `unfavorite`.
    var favoriteAircraft: [FavoriteAircraft] {
        didSet {
            save(try? JSONEncoder().encode(favoriteAircraft), .favoriteAircraft)
            favoriteSet = FavoriteSet(favoriteAircraft)
            onFavoriteAircraftChange?(oldValue)
        }
    }
    /// The favourites as a lookup, kept with the list; views get it as `\.favoriteAircraft`.
    private(set) var favoriteSet = FavoriteSet()
    /// `FavoriteSync` listens here to send local changes to iCloud; gets the old list.
    @ObservationIgnored var onFavoriteAircraftChange: ((_ old: [FavoriteAircraft]) -> Void)?

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
        units = UnitSystem(rawValue: value(.units, UnitSystem.localeDefault.rawValue)) ?? .localeDefault
        dataSource = DataSourcePreference(rawValue: value(.dataSource, "automatic")) ?? .automatic
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
        preferVisible = value(.preferVisible, false)
        showsVisibility = value(.showsVisibility, true)
        weatherFog = value(.weatherFog, true)
        showCompassBezel = value(.showCompassBezel, true)
        radarSweep = value(.radarSweep, true)
        showPhotos = value(.showPhotos, true)
        aircraftFacts = value(.aircraftFacts, true)
        cardPhotos = value(.cardPhotos, false)
        hapticsEnabled = value(.haptics, true)
        keepScreenAwake = value(.keepAwake, false)
        demoTraffic = value(.demoTraffic, false)
        hasSeenWelcome = value(.hasSeenWelcome, false)
        customPlaceName = defaults.string(forKey: Key.customPlaceName.name)
        savedSpots = defaults.data(forKey: Key.savedSpots.name)
            .flatMap { try? JSONDecoder().decode([SavedSpot].self, from: $0) } ?? []
        tvFacingDegrees = GeoMath.normalize(value(.tvFacing, 0.0))
        overheadAlerts = value(.overheadAlerts, true)
        overheadAlertMiles = value(.overheadAlertMiles, 1.5).clamped(to: Self.overheadAlertRange)
        overheadAlertLeadSeconds = value(.overheadAlertLead, 150.0).clamped(to: Self.overheadAlertLeadRange)
        notableAlerts = value(.notableAlerts, true)
        spokenAlerts = value(.spokenAlerts, false)
        spokenAlertsHeadphonesOnly = value(.spokenAlertsHeadphonesOnly, true)
        watchlist = defaults.data(forKey: Key.watchlist.name)
            .flatMap { try? JSONDecoder().decode([WatchlistRule].self, from: $0) } ?? []
        favoriteAlerts = value(.favoriteAlerts, true)
        firstSeenAlerts = value(.firstSeenAlerts, true)
        keepLogbook = value(.keepLogbook, true)
        dailyDigest = value(.dailyDigest, false)
        // 8 pm (`DailyDigest.defaultMinutes`).
        digestMinutes = Int(value(.digestMinutes, 1200.0)).clamped(to: 0...(24 * 60 - 1))
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
        favoriteAircraft = defaults.data(forKey: Key.favoriteAircraft.name)
            .flatMap { try? JSONDecoder().decode([FavoriteAircraft].self, from: $0) } ?? []
        favoriteSet = FavoriteSet(favoriteAircraft)
        Units.adopt(units)
        SharedRadarStore().dataSource = dataSource
    }

    // MARK: Saved spots

    /// Watches from a saved spot, under its name.
    func watch(_ spot: SavedSpot) {
        customCoordinate = spot.coordinate
        customPlaceName = spot.name
        locationMode = .custom
    }

    /// The saved spot being watched from, if the custom spot is one.
    var currentSavedSpot: SavedSpot? {
        guard locationMode == .custom else { return nil }
        return savedSpots.first { $0.isAt(customCoordinate) }
    }

    /// Saves a place under a name; one already there is renamed instead.
    @discardableResult
    func saveSpot(named name: String, at coordinate: CLLocationCoordinate2D) -> SavedSpot {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? coordinate.shortDescription : trimmed
        if let i = savedSpots.firstIndex(where: { $0.isAt(coordinate) }) {
            savedSpots[i].name = title
            if currentSavedSpot?.id == savedSpots[i].id { customPlaceName = title }
            return savedSpots[i]
        }
        let spot = SavedSpot(name: title, coordinate: coordinate)
        savedSpots.append(spot)
        if locationMode == .custom, spot.isAt(customCoordinate) { customPlaceName = title }
        return spot
    }

    func removeSpot(_ spot: SavedSpot) {
        savedSpots.removeAll { $0.id == spot.id }
    }

    /// Adds a rule (once), newest last.
    func addToWatchlist(_ rule: WatchlistRule) {
        guard !rule.value.isEmpty, !watchlist.contains(rule) else { return }
        watchlist.append(rule)
    }

    func removeFromWatchlist(_ rule: WatchlistRule) {
        watchlist.removeAll { $0 == rule }
    }

    /// The TV's view, treated as the radar whenever the map is switched off.
    var effectiveTVView: TVView { mapView ? tvView : .radar }

    /// The map's radius: its own, or the radar's.
    var effectiveMapRadius: Double { mapRadiusMiles ?? radiusMiles }

    static let overheadAlertRange: ClosedRange<Double> = 0.5...5
    static let overheadAlertLeadRange: ClosedRange<Double> = 30...600

    var alertRules: TrafficAlertRules {
        TrafficAlertRules(overhead: overheadAlerts, notable: notableAlerts, overheadMiles: overheadAlertMiles,
                          leadSeconds: overheadAlertLeadSeconds, watchlist: watchlist, favorites: favoriteAlerts,
                          firstSeen: firstSeenAlerts)
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
        units = .localeDefault
        dataSource = .automatic
        appearance = .system
        showHelicopters = true
        preferVisible = false
        showsVisibility = true
        weatherFog = true
        topography = .survey
        topographyMotion = .normal
        showCompassBezel = true
        radarSweep = true
        showPhotos = true
        aircraftFacts = true
        cardPhotos = false
        hapticsEnabled = true
        keepScreenAwake = false
        demoTraffic = false
        overheadAlerts = true
        overheadAlertMiles = 1.5
        overheadAlertLeadSeconds = 150
        notableAlerts = true
        spokenAlerts = false
        spokenAlertsHeadphonesOnly = true
        favoriteAlerts = true
        firstSeenAlerts = true
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
        case radius, units, dataSource, locationMode, customLatitude, customLongitude, appearance
        // `showTopography` is only read, to carry an old "off" over to `topography`.
        case showHelicopters, showTopography, topography, topographyMotion, showCompassBezel, radarSweep, showPhotos, cardPhotos
        case haptics, keepAwake, demoTraffic, hasSeenWelcome, customPlaceName, tvFacing
        case overheadAlerts, overheadAlertMiles, overheadAlertLead, notableAlerts, spokenAlerts, keepLogbook, raiseToSkyView
        case mapView, mapScreen, tvView, mapNorthUp, mapRadius, mapType, skySaveToPhotos, pinnedAircraft, favoriteAircraft
        case spokenAlertsHeadphonesOnly, watchlist, favoriteAlerts, firstSeenAlerts
        case savedSpots = "spots"
        case dailyDigest = "digest", digestMinutes = "digestTime"
        case aircraftFacts, preferVisible, weatherFog
        case showsVisibility = "visibilityHints"
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
