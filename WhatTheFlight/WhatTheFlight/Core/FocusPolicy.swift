//
//  FocusPolicy.swift
//  WhatTheFlight
//
//  Decides which aircraft owns the centre of the screen.
//
//  • First launch / nothing focused → the nearest aircraft.
//  • The focused aircraft stays put ("sticky") while it is inside the radius, even if
//    another one becomes closer.
//  • When it leaves the radius (or vanishes from the feed) the current nearest takes over.
//  • A pinned aircraft is kept while the feed still reports it, even outside the radius.
//  • One picked on a map just outside the radius is held (not pinned) while the map still
//    draws it; it becomes an ordinary focus if it flies into the radius.
//  • Swipe right always jumps back to the current nearest.
//

import Foundation

struct RadarFocus: Equatable, Sendable {
    var focusedID: String?
    var isPinned: Bool = false
    /// Picked on a map outside the radius without pinning it.
    var isHeld: Bool = false
}

enum FocusChange: Equatable, Sendable {
    case none
    case initial
    /// The previous aircraft flew out of the radius.
    case leftRange(previous: String)
    /// The previous aircraft disappeared from the feed (landed, lost signal…).
    case lost(previous: String)
}

enum FocusPolicy {
    /// - Parameters:
    ///   - inRange: contacts inside the radius, sorted nearest first.
    ///   - nearby: IDs of aircraft outside the radius that a map still draws (its fringe).
    ///   - available: IDs of every aircraft currently in the feed (in or out of range).
    static func resolve(_ state: RadarFocus, inRange: [RadarContact], nearby: Set<String> = [],
                        available: Set<String>) -> (RadarFocus, FocusChange) {
        guard let current = state.focusedID else {
            guard let nearest = inRange.first else { return (state, .none) }
            return (RadarFocus(focusedID: nearest.id, isPinned: false), .initial)
        }
        if inRange.contains(where: { $0.id == current }) {
            var state = state
            state.isHeld = false
            return (state, .none)
        }
        if state.isPinned, available.contains(current) {
            return (state, .none)
        }
        if state.isHeld, nearby.contains(current) {
            return (state, .none)
        }
        let replacement = RadarFocus(focusedID: inRange.first?.id, isPinned: false)
        let change: FocusChange = available.contains(current) ? .leftRange(previous: current) : .lost(previous: current)
        return (replacement, change)
    }

    static func nearest(_ inRange: [RadarContact]) -> RadarFocus {
        RadarFocus(focusedID: inRange.first?.id, isPinned: false)
    }

    /// The next aircraft farther out than the current one, wrapping to the nearest.
    static func next(after state: RadarFocus, inRange: [RadarContact]) -> RadarFocus {
        guard !inRange.isEmpty else { return state }
        guard let current = state.focusedID,
              let index = inRange.firstIndex(where: { $0.id == current }) else {
            return nearest(inRange)
        }
        return RadarFocus(focusedID: inRange[(index + 1) % inRange.count].id, isPinned: false)
    }

    /// The next aircraft closer in than the current one. Stops at the nearest (no wrap),
    /// so holding ◀ on the remote always lands on the closest aircraft.
    static func previous(before state: RadarFocus, inRange: [RadarContact]) -> RadarFocus {
        guard !inRange.isEmpty else { return state }
        guard let current = state.focusedID,
              let index = inRange.firstIndex(where: { $0.id == current }) else {
            return nearest(inRange)
        }
        return RadarFocus(focusedID: inRange[max(0, index - 1)].id, isPinned: false)
    }
}

/// An aircraft the user pinned. It's followed wherever it is (looked up worldwide when it's
/// outside the feed's box) and drawn on the radar edge and the map with a pin. Remembered by
/// airframe, because Flightradar24 gives each leg a new flight id.
struct PinnedAircraft: Codable, Equatable, Sendable, Identifiable {
    /// The flight id it was last seen under.
    var flightID: String
    var registration: String?
    var callsign: String?
    /// "DL570", for lists while it isn't transmitting.
    var label: String
    /// Orders pins across devices (oldest make way first). nil for pins made before syncing.
    var pinnedAt: Date?

    var id: String { registration ?? callsign ?? flightID }
    /// Demo traffic only exists on the device running the demo, so its pins never sync.
    var isDemo: Bool { flightID.hasPrefix("demo-") }

    init(_ flight: Flight, pinnedAt: Date = Date()) {
        flightID = flight.id
        registration = flight.registration?.uppercased()
        callsign = flight.callsign?.uppercased()
        label = flight.displayIdentifier
        self.pinnedAt = pinnedAt
    }

    /// Same airframe (or, with no registration, same callsign), whatever the flight id.
    func matches(_ flight: Flight) -> Bool {
        if flight.id == flightID { return true }
        if let registration { return flight.registration?.uppercased() == registration }
        if let callsign { return flight.callsign?.uppercased() == callsign }
        return false
    }
}

/// An aircraft the user has favourited. Unlike a pin it isn't followed around the world: it's
/// called out in yellow wherever it turns up (the radar edge, the map, the hero, the search
/// list and the logbook). Remembered by airframe, so it's a favourite on every leg it flies:
/// matched by registration or ICAO hex, and only by callsign when it has neither.
struct FavoriteAircraft: Codable, Equatable, Sendable, Identifiable {
    var registration: String?
    var hex: String?
    var callsign: String?
    /// The flight id it was favourited from. Demo traffic's never leaves its device.
    var flightID: String
    /// "UA994": what it was flying as when it was favourited.
    var label: String
    var typeCode: String?
    /// "United Airlines", for lists while it isn't flying.
    var operatorName: String?
    /// Orders favourites across devices.
    var addedAt: Date?

    var id: String { registration ?? hex ?? callsign ?? flightID }
    /// The tail number, which stays with the airframe from leg to leg.
    var title: String { registration ?? label }
    var typeName: String? { AircraftTypeCatalog.name(forTypeCode: typeCode) }
    var silhouette: AircraftSilhouette { AircraftTypeCatalog.silhouette(forTypeCode: typeCode) }
    var isDemo: Bool { flightID.hasPrefix("demo-") }
    /// Worldwide lookups need a tail number or a callsign.
    var canLocate: Bool { registration != nil || callsign != nil }

    init(registration: String?, hex: String?, callsign: String?, flightID: String, label: String,
         typeCode: String?, operatorName: String?, addedAt: Date = Date()) {
        self.registration = Self.key(registration)
        self.hex = Self.key(hex)
        self.callsign = Self.key(callsign)
        self.flightID = flightID
        self.label = label
        self.typeCode = typeCode
        self.operatorName = operatorName
        self.addedAt = addedAt
    }

    init(_ flight: Flight, operatorName: String?, addedAt: Date = Date()) {
        self.init(registration: flight.registration, hex: flight.hex, callsign: flight.callsign, flightID: flight.id,
                  label: flight.displayIdentifier, typeCode: flight.typeCode, operatorName: operatorName, addedAt: addedAt)
    }

    /// From the logbook: an aircraft seen before, flying or not.
    init(_ sighting: Sighting, addedAt: Date = Date()) {
        self.init(registration: sighting.registration, hex: sighting.hex, callsign: sighting.callsign, flightID: sighting.id,
                  label: sighting.displayIdentifier, typeCode: sighting.typeCode, operatorName: sighting.operatorName,
                  addedAt: addedAt)
    }

    /// Same airframe: its registration or hex, or with neither, its callsign.
    func matches(_ flight: Flight) -> Bool {
        if flight.id == flightID { return true }
        if let registration, Self.key(flight.registration) == registration { return true }
        if let hex, Self.key(flight.hex) == hex { return true }
        if registration == nil, hex == nil, let callsign { return Self.key(flight.callsign) == callsign }
        return false
    }

    /// The same airframe, however each was saved (a sighting gives the registration, a flight
    /// in the feed may only have the hex).
    func matches(_ other: FavoriteAircraft) -> Bool {
        if other.flightID == flightID { return true }
        if let registration, other.registration == registration { return true }
        if let hex, other.hex == hex { return true }
        if registration == nil, hex == nil, other.registration == nil, other.hex == nil, let callsign {
            return other.callsign == callsign
        }
        return false
    }

    /// Uppercased and trimmed, nil when empty: how airframes are compared.
    static func key(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespaces).uppercased(), !value.isEmpty else { return nil }
        return value
    }
}

/// The favourites as a lookup, for everything that calls them out. Views read it as
/// `\.favoriteAircraft`; `RadarSettings.favoriteSet` keeps it up to date.
struct FavoriteSet: Equatable, Sendable {
    private(set) var favorites: [FavoriteAircraft] = []
    private var registrations: Set<String> = []
    private var hexes: Set<String> = []
    /// Only favourites with neither a registration nor a hex go by callsign.
    private var callsigns: Set<String> = []
    private var flightIDs: Set<String> = []

    init(_ favorites: [FavoriteAircraft] = []) {
        self.favorites = favorites
        for f in favorites {
            if let r = f.registration { registrations.insert(r) }
            if let h = f.hex { hexes.insert(h) }
            if f.registration == nil, f.hex == nil, let c = f.callsign { callsigns.insert(c) }
            flightIDs.insert(f.flightID)
        }
    }

    var isEmpty: Bool { favorites.isEmpty }

    func contains(_ flight: Flight) -> Bool {
        matches(id: flight.id, registration: flight.registration, hex: flight.hex, callsign: flight.callsign)
    }

    func contains(_ sighting: Sighting) -> Bool {
        matches(id: sighting.id, registration: sighting.registration, hex: sighting.hex, callsign: sighting.callsign)
    }

    /// A logbook airframe key: a registration, or a hex for aircraft without one.
    func contains(airframe: String) -> Bool {
        guard let key = FavoriteAircraft.key(airframe) else { return false }
        return registrations.contains(key) || hexes.contains(key)
    }

    /// The favourite this flight is, for removing it.
    func favorite(for flight: Flight) -> FavoriteAircraft? {
        favorites.first { $0.matches(flight) }
    }

    private func matches(id: String, registration: String?, hex: String?, callsign: String?) -> Bool {
        guard !favorites.isEmpty else { return false }
        if flightIDs.contains(id) { return true }
        if let r = FavoriteAircraft.key(registration), registrations.contains(r) { return true }
        if let h = FavoriteAircraft.key(hex), hexes.contains(h) { return true }
        if let c = FavoriteAircraft.key(callsign), callsigns.contains(c) { return true }
        return false
    }
}
