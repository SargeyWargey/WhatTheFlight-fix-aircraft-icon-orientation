//
//  WatchSettings.swift
//  WhatTheFlightWatch
//
//  Preferences only the Watch has. Shared preferences (radius, helicopters, alerts…) live in
//  `RadarSettings` like on the iPhone; the radius defaults to 10 mi here and isn't synced.
//

import Foundation
import CoreLocation
import Observation

@MainActor
@Observable
final class WatchSettings {
    enum LocationSource: String, CaseIterable, Identifiable {
        case here, phone
        var id: String { rawValue }
        var title: String { self == .here ? "Here" : "iPhone's Spot" }
    }

    static let radiusChoices: [Double] = [2, 5, 10, 15, 20, 30, 50]

    var locationSource: LocationSource { didSet { defaults.set(locationSource.rawValue, forKey: Key.locationSource) } }
    /// Keep north at the top instead of turning the radar with the wrist.
    var northUp: Bool { didSet { defaults.set(northUp, forKey: Key.northUp) } }
    /// Load aircraft photos over the Watch's own cellular connection.
    var photosOnCellular: Bool { didSet { defaults.set(photosOnCellular, forKey: Key.photosOnCellular) } }
    /// Point & Find: use the other end of the forearm axis, if pointing comes out backwards.
    var flipPointing: Bool { didSet { defaults.set(flipPointing, forKey: Key.flipPointing) } }
    /// Identify and Find: point with your arm, or aim the Watch's top edge.
    var aimStyle: WristPointing.AimStyle { didSet { defaults.set(aimStyle.rawValue, forKey: Key.aimStyle) } }
    /// Point: show the screen half a turn round from what the sensors pick.
    var flipScreen: Bool { didSet { defaults.set(flipScreen, forKey: Key.flipScreen) } }
    /// Identify reads out what you're pointing at.
    var speakIdentification: Bool { didSet { defaults.set(speakIdentification, forKey: Key.speakIdentification) } }
    /// Updates less often, no sweep, no springy animations, a coarser compass. Identify and
    /// Find are unchanged: pointing is the point.
    var batterySaver: Bool { didSet { defaults.set(batterySaver, forKey: Key.batterySaver) } }
    /// The first-run tour has been shown (or skipped).
    var hasSeenTour: Bool { didSet { defaults.set(hasSeenTour, forKey: Key.hasSeenTour) } }

    /// Where the iPhone's radar last watched from (its custom spot or its GPS).
    private(set) var phoneObserver: CLLocationCoordinate2D?
    private(set) var phonePlaceName: String?

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        locationSource = LocationSource(rawValue: defaults.string(forKey: Key.locationSource) ?? "") ?? .here
        northUp = defaults.bool(forKey: Key.northUp)
        photosOnCellular = defaults.bool(forKey: Key.photosOnCellular)
        flipPointing = defaults.bool(forKey: Key.flipPointing)
        flipScreen = defaults.bool(forKey: Key.flipScreen)
        aimStyle = WristPointing.AimStyle(rawValue: defaults.string(forKey: Key.aimStyle) ?? "") ?? .point
        speakIdentification = defaults.object(forKey: Key.speakIdentification) == nil ? true : defaults.bool(forKey: Key.speakIdentification)
        hasSeenTour = defaults.bool(forKey: Key.hasSeenTour)
        batterySaver = defaults.bool(forKey: Key.batterySaver)
        if defaults.object(forKey: Key.phoneLatitude) != nil {
            phoneObserver = CLLocationCoordinate2D(latitude: defaults.double(forKey: Key.phoneLatitude),
                                                   longitude: defaults.double(forKey: Key.phoneLongitude))
        }
        phonePlaceName = defaults.string(forKey: Key.phonePlaceName)
    }

    /// Takes what the iPhone shared: its spot, and the preferences both devices agree on.
    func apply(_ context: WatchSync.Context, to settings: RadarSettings) {
        if let observer = context.observer {
            phoneObserver = observer
            defaults.set(observer.latitude, forKey: Key.phoneLatitude)
            defaults.set(observer.longitude, forKey: Key.phoneLongitude)
        }
        phonePlaceName = context.placeName
        defaults.set(context.placeName, forKey: Key.phonePlaceName)
        if settings.showHelicopters != context.showHelicopters { settings.showHelicopters = context.showHelicopters }
        if settings.overheadAlerts != context.overheadAlerts { settings.overheadAlerts = context.overheadAlerts }
        if settings.overheadAlertMiles != context.overheadAlertMiles { settings.overheadAlertMiles = context.overheadAlertMiles }
        if settings.notableAlerts != context.notableAlerts { settings.notableAlerts = context.notableAlerts }
        if let raw = context.units, let units = UnitSystem(rawValue: raw), settings.units != units { settings.units = units }
        if let lead = context.overheadAlertLeadSeconds, settings.overheadAlertLeadSeconds != lead {
            settings.overheadAlertLeadSeconds = lead.clamped(to: RadarSettings.overheadAlertLeadRange)
        }
        if let watchlist = context.watchlist, settings.watchlist != watchlist { settings.watchlist = watchlist }
        if let favorites = context.favoriteAlerts, settings.favoriteAlerts != favorites { settings.favoriteAlerts = favorites }
        if let keep = context.keepLogbook, settings.keepLogbook != keep { settings.keepLogbook = keep }
        if let sync = context.syncLogbook, settings.syncLogbook != sync { settings.syncLogbook = sync }
    }

    private enum Key {
        static let locationSource = "wtf.watch.locationSource"
        static let northUp = "wtf.watch.northUp"
        static let photosOnCellular = "wtf.watch.photosOnCellular"
        static let flipPointing = "wtf.watch.flipPointing"
        static let flipScreen = "wtf.watch.flipScreen"
        static let aimStyle = "wtf.watch.aimStyle"
        static let speakIdentification = "wtf.watch.speakIdentification"
        static let hasSeenTour = "wtf.watch.hasSeenTour"
        static let batterySaver = "wtf.watch.batterySaver"
        static let phoneLatitude = "wtf.watch.phoneLatitude"
        static let phoneLongitude = "wtf.watch.phoneLongitude"
        static let phonePlaceName = "wtf.watch.phonePlaceName"
    }
}

extension WristPointing.AimStyle {
    var title: String { self == .point ? "Point" : "Aim" }
    var symbol: String { self == .point ? "hand.point.up.left.fill" : "scope" }
    var summary: String {
        switch self {
        case .point: return "Arm out, finger at the plane. The screen turns to face you, but watchOS may dim it; the call-out and the lock's tap still reach you."
        case .aim: return "Hold your Watch as if reading it and aim its top edge: turn your body, tilt your wrist. Stays bright."
        }
    }
}
