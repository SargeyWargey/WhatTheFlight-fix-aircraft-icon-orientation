//
//  Units.swift
//  WhatTheFlight
//
//  Imperial (miles, feet, knots: what the app always showed) or metric (kilometers, meters,
//  km/h). Everything inside stays in miles, feet and knots; only what's shown and said
//  changes, so every distance, altitude and speed on screen or in a sentence goes through
//  `RadarFormat`'s unit-aware helpers below rather than appending "mi" / "ft" / "kts".
//

import Foundation
import os

enum UnitSystem: String, CaseIterable, Identifiable, Codable, Sendable {
    case imperial, metric

    var id: String { rawValue }

    var title: String { self == .imperial ? String(localized: "Imperial") : String(localized: "Metric") }
    var subtitle: String { self == .imperial ? String(localized: "Miles, feet and knots") : String(localized: "Kilometers, meters and km/h") }

    /// What a new install starts with: metric unless the region uses miles (the US, the UK…).
    static var localeDefault: UnitSystem {
        Locale.current.measurementSystem == .metric ? .metric : .imperial
    }

    static let kilometersPerMile = 1.609344
    static let metersPerFoot = 0.3048
    static let kmhPerKnot = 1.852
}

/// The units in use, readable from any thread: views, alert sentences, widgets and Siri all
/// format through it. `RadarSettings` sets it on launch and whenever the choice changes;
/// extensions set it from the shared App Group store.
enum Units {
    /// Where the app leaves the choice for its extensions (App Group defaults).
    static let sharedKey = "wtf.shared.units"
    static let appGroup = "group.SargeyWargey.WhatTheFlight"

    private static let state = OSAllocatedUnfairLock(initialState: stored ?? UnitSystem.localeDefault)

    static var current: UnitSystem {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }

    static var isMetric: Bool { current == .metric }

    /// The app's choice as last shared with its extensions.
    static var stored: UnitSystem? {
        UserDefaults(suiteName: appGroup)?.string(forKey: sharedKey).flatMap(UnitSystem.init(rawValue:))
    }

    /// Sets the units in use here and shares them with the extensions.
    static func adopt(_ units: UnitSystem) {
        current = units
        UserDefaults(suiteName: appGroup)?.set(units.rawValue, forKey: sharedKey)
    }

    /// Extensions: pick up a change the app made since this process started.
    static func reload() {
        if let stored { current = stored }
    }
}

extension RadarFormat {
    // MARK: Distance

    /// Whole units, like the perimeter labels: "12", or "<1" under half a unit. The unit is
    /// `distanceUnit`.
    static func distance(_ miles: Double, in units: UnitSystem = Units.current) -> String {
        let value = units == .metric ? miles * UnitSystem.kilometersPerMile : miles
        return value < 0.5 ? "<1" : wholeNumber(Int(value.rounded()))
    }

    static func distanceUnit(_ units: UnitSystem = Units.current) -> String { units == .metric ? "km" : "mi" }

    /// "12 mi" / "19 km".
    static func distanceText(_ miles: Double, in units: UnitSystem = Units.current) -> String {
        "\(distance(miles, in: units)) \(distanceUnit(units))"
    }

    /// One decimal under 10 units, whole above: "1.5 mi" / "2.4 km", "230 mi". For settings and
    /// records, where "<1" would say too little.
    static func preciseDistance(_ miles: Double, in units: UnitSystem = Units.current) -> String {
        let value = units == .metric ? miles * UnitSystem.kilometersPerMile : miles
        let number = value < 10
            ? value.formatted(.number.precision(.fractionLength(0...1)))
            : wholeNumber(Int(value.rounded()))
        return "\(number) \(distanceUnit(units))"
    }

    /// A short distance as precisely as it matters: "0.25 mi" / "400 m". Metric reads meters
    /// below a kilometer, rounded to 10.
    static func shortDistance(_ miles: Double, in units: UnitSystem = Units.current) -> String {
        if units == .metric {
            let km = miles * UnitSystem.kilometersPerMile
            if km < 1 { return "\(wholeNumber(Int((km * 100).rounded()) * 10)) m" }
            return "\(km.formatted(.number.precision(.fractionLength(0...1)))) km"
        }
        return "\(miles.formatted(.number.precision(.fractionLength(0...2)))) mi"
    }

    /// A radius or range setting in whole units: "20 mi" / "32 km".
    static func radius(_ miles: Double, in units: UnitSystem = Units.current) -> String {
        wholeDistance(miles, in: units)
    }

    /// Whole units, never "<1": "2,266 mi" / "3,647 km". Route lengths, miles flown.
    static func wholeDistance(_ miles: Double, in units: UnitSystem = Units.current) -> String {
        let value = units == .metric ? miles * UnitSystem.kilometersPerMile : miles
        return "\(wholeNumber(Int(value.rounded()))) \(distanceUnit(units))"
    }

    // MARK: Altitude

    /// "35,000" / "10,670" (meters to the nearest 10). The unit is `altitudeUnit`.
    static func altitude(_ feet: Int, in units: UnitSystem = Units.current) -> String {
        guard units == .metric else { return wholeNumber(feet) }
        let meters = Double(feet) * UnitSystem.metersPerFoot
        return wholeNumber(Int((meters / 10).rounded()) * 10)
    }

    static func altitudeUnit(_ units: UnitSystem = Units.current) -> String { units == .metric ? "m" : "ft" }

    /// "35,000 ft" / "10,670 m".
    static func altitudeText(_ feet: Int, in units: UnitSystem = Units.current) -> String {
        "\(altitude(feet, in: units)) \(altitudeUnit(units))"
    }

    /// The altitude as a number in the display unit, for charts and numeric transitions.
    static func altitudeValue(_ feet: Int, in units: UnitSystem = Units.current) -> Double {
        units == .metric ? Double(feet) * UnitSystem.metersPerFoot : Double(feet)
    }

    // MARK: Speed

    /// "450" / "833". The unit is `speedUnit`.
    static func speed(_ knots: Int, in units: UnitSystem = Units.current) -> String {
        units == .metric ? wholeNumber(Int((Double(knots) * UnitSystem.kmhPerKnot).rounded())) : wholeNumber(knots)
    }

    static func speedUnit(_ units: UnitSystem = Units.current) -> String { units == .metric ? "km/h" : "kts" }

    /// "450 kts" / "833 km/h".
    static func speedText(_ knots: Int, in units: UnitSystem = Units.current) -> String {
        "\(speed(knots, in: units)) \(speedUnit(units))"
    }

    static func speedValue(_ knots: Int, in units: UnitSystem = Units.current) -> Double {
        units == .metric ? Double(knots) * UnitSystem.kmhPerKnot : Double(knots)
    }

    /// "+1,500 fpm" / "+7.6 m/s", or "Level".
    static func verticalRate(_ fpm: Int, in units: UnitSystem = Units.current) -> String {
        guard fpm != 0 else { return "Level" }
        let sign = fpm > 0 ? "+" : "−"
        if units == .metric {
            let mps = abs(Double(fpm)) * UnitSystem.metersPerFoot / 60
            return "\(sign)\(mps.formatted(.number.precision(.fractionLength(1)))) m/s"
        }
        return "\(sign)\(wholeNumber(abs(fpm))) fpm"
    }

    // MARK: Spoken

    /// For the ear, whole units: "3 miles", "1 mile" / "5 kilometers".
    static func spokenDistance(_ miles: Double, in units: UnitSystem = Units.current) -> String {
        let value = max(1, Int((units == .metric ? miles * UnitSystem.kilometersPerMile : miles).rounded()))
        let word = units == .metric ? (value == 1 ? "kilometer" : "kilometers") : (value == 1 ? "mile" : "miles")
        return "\(wholeNumber(value)) \(word)"
    }

    /// For the ear, rounded so it's quick to say: "30,000 feet" (to 100 ft) / "9,150 meters"
    /// (to 50 m).
    static func spokenAltitude(_ feet: Int, in units: UnitSystem = Units.current) -> String {
        if units == .metric {
            let meters = Double(feet) * UnitSystem.metersPerFoot
            return "\(wholeNumber(Int((meters / 50).rounded()) * 50)) meters"
        }
        return "\(wholeNumber(Int((Double(feet) / 100).rounded()) * 100)) feet"
    }

    /// "500 knots" / "926 kilometers an hour".
    static func spokenSpeed(_ knots: Int, in units: UnitSystem = Units.current) -> String {
        units == .metric
            ? "\(wholeNumber(Int((Double(knots) * UnitSystem.kmhPerKnot).rounded()))) kilometers an hour"
            : "\(wholeNumber(knots)) knots"
    }
}
