//
//  OperatorInfo.swift
//  WhatTheFlight
//
//  "Who's flying this?" — the line under the flight number. Airlines come from the
//  catalog; aircraft flying under their own tail number read "Private aircraft · 🇺🇸 United
//  States"; unknown ICAO operators at least show their designator.
//

import Foundation

struct OperatorInfo: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case airline, military, government, medical, privateAircraft, unlisted, unknown
    }

    let kind: Kind
    /// "Delta Air Lines", "Private aircraft", "Unlisted operator BPX".
    let title: String
    /// Radio callsign and/or country: "Radio “DELTA” · United States", "🇺🇸 United States".
    let subtitle: String?
    /// Country of registry, when the tail number gives it away.
    let countryCode: String?

    /// Title plus flag, for list rows: "Private aircraft 🇺🇸".
    var compact: String {
        guard kind != .airline, let countryCode else { return title }
        return "\(title) \(RegistrationCountry.flag(forCode: countryCode))"
    }

    /// One line for the radar centre: "Private aircraft · 🇺🇸 United States".
    var headline: String {
        guard kind != .airline, let countryCode else { return title }
        return "\(title) · \(RegistrationCountry.flag(forCode: countryCode)) \(RegistrationCountry.countryName(forCode: countryCode))"
    }
}

extension Flight {
    var operatorInfo: OperatorInfo {
        let country = registrationCountryCode
        let countryText = country.map { "\(RegistrationCountry.flag(forCode: $0)) \(RegistrationCountry.countryName(forCode: $0))" }

        if let airline {
            let designator = airline.icao
            let kind: OperatorInfo.Kind
            if AirlineCatalog.militaryDesignators.contains(designator) {
                kind = .military
            } else if AirlineCatalog.governmentDesignators.contains(designator) {
                kind = .government
            } else if AirlineCatalog.medicalWords.contains(designator) || designator == "LFL" {
                kind = .medical
            } else {
                kind = .airline
            }
            var parts: [String] = []
            if let radio = airline.radioCallsign, !radio.isEmpty { parts.append("Radio “\(radio)”") }
            if let home = airline.country, !home.isEmpty { parts.append(home) } else if let countryText { parts.append(countryText) }
            return OperatorInfo(kind: kind, title: airline.name, subtitle: parts.isEmpty ? nil : parts.joined(separator: " · "), countryCode: country)
        }

        if isFlyingUnderRegistration {
            let title = kind == .helicopter ? "Private helicopter" : "Private aircraft"
            return OperatorInfo(kind: .privateAircraft, title: title, subtitle: countryText, countryCode: country)
        }

        if let prefix = AirlineCatalog.icaoPrefix(ofCallsign: callsign) {
            return OperatorInfo(kind: .unlisted, title: "Unlisted operator \(prefix)", subtitle: countryText, countryCode: country)
        }

        return OperatorInfo(kind: .unknown, title: kind == .helicopter ? "Helicopter" : "Private / Unlisted",
                            subtitle: countryText, countryCode: country)
    }

    /// The registry country from the tail number (or a US N-number used as the callsign).
    var registrationCountryCode: String? {
        if let code = RegistrationCountry.countryCode(forRegistration: registration) { return code }
        if let callsign, RegistrationCountry.isUSRegistration(callsign) { return "US" }
        return nil
    }

    /// General aviation flies under its tail number rather than an airline callsign.
    var isFlyingUnderRegistration: Bool {
        func normalized(_ s: String?) -> String? {
            guard let s = s?.uppercased().replacingOccurrences(of: "-", with: ""), !s.isEmpty else { return nil }
            return s
        }
        guard let callsign = normalized(callsign) else {
            return registration != nil && flightNumber == nil
        }
        if let reg = normalized(registration), reg == callsign { return true }
        return RegistrationCountry.isUSRegistration(callsign)
    }
}
