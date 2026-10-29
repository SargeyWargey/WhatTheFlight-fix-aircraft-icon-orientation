//
//  AirframeFacts.swift
//  WhatTheFlight
//
//  What an airframe is, beyond its type code: the maker and exact variant ("Boeing 717-231"),
//  who it's registered to and where (Enhancements Spec C5). From adsbdb.com, looked up by
//  tail number or ICAO hex (`Services/AircraftFactsProvider.swift`). The registered owner is
//  only shown when it's an organisation: a private owner's name is never shown.
//
//  adsbdb has no build year, so `yearBuilt` stays empty until a source that has one (adsb.fi
//  with permission, or a national register) is added.
//

import Foundation

struct AirframeFacts: Codable, Equatable, Sendable {
    var manufacturer: String?
    /// The exact variant as registered: "717-231", "A321-271NX".
    var model: String?
    var icaoType: String?
    /// Only organisations ("Delta Air Lines", "Wells Fargo Trust Co"); nil for a person.
    var owner: String?
    var ownerCountryISO: String?
    var ownerCountryName: String?
    var yearBuilt: Int?

    /// "Boeing 717-231".
    var title: String? {
        let parts = [manufacturer, model].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// "Registered to Delta Air Lines · 🇺🇸".
    var ownerLine: String? {
        guard let owner else { return nil }
        let flag = ownerCountryISO.map { RegistrationCountry.flag(forCode: $0) }
        return ["Registered to \(owner)", flag].compactMap { $0 }.joined(separator: " · ")
    }

    /// "Built 1998 · 28 years old".
    func ageLine(now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard let yearBuilt else { return nil }
        let age = calendar.component(.year, from: now) - yearBuilt
        return age > 0 ? "Built \(yearBuilt) · \(age) years old" : "Built \(yearBuilt)"
    }

    // MARK: adsbdb

    /// `{"response": {"aircraft": {...}}}`, or nil for "unknown aircraft" (adsbdb answers
    /// `{"response": "unknown aircraft"}`).
    static func parseAdsbdb(_ data: Data) -> AirframeFacts? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = json["response"] as? [String: Any],
              let a = response["aircraft"] as? [String: Any] else { return nil }
        func text(_ key: String) -> String? {
            (a[key] as? String).map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }
        }
        let rawOwner = text("registered_owner")
        return AirframeFacts(
            manufacturer: text("manufacturer").map(tidyManufacturer),
            // adsbdb writes the variant with a space: "717 231".
            model: text("type").map { $0.replacingOccurrences(of: " ", with: "-") },
            icaoType: text("icao_type"),
            owner: rawOwner.flatMap { isOrganisation($0) ? tidyName($0) : nil },
            ownerCountryISO: text("registered_owner_country_iso_name"),
            ownerCountryName: text("registered_owner_country_name"),
            yearBuilt: nil)
    }

    /// Registers spell makers in capitals ("THE BOEING COMPANY"); show them as people do.
    static func tidyManufacturer(_ name: String) -> String {
        let known: [String: String] = [
            "THE BOEING COMPANY": "Boeing", "BOEING": "Boeing", "AIRBUS": "Airbus", "AIRBUS SAS": "Airbus",
            "EMBRAER": "Embraer", "EMBRAER S A": "Embraer", "BOMBARDIER INC": "Bombardier", "CESSNA": "Cessna",
            "TEXTRON AVIATION INC": "Textron Aviation", "PIPER": "Piper", "GULFSTREAM AEROSPACE": "Gulfstream",
            "DE HAVILLAND": "De Havilland", "ATR": "ATR", "ROBINSON HELICOPTER CO": "Robinson",
        ]
        if let hit = known[name.uppercased()] { return hit }
        return tidyName(name)
    }

    /// All-caps register names in title case, keeping short codes ("LLC", "USA") as they are.
    static func tidyName(_ name: String) -> String {
        guard name == name.uppercased(), name.contains(where: \.isLetter) else { return name }
        let keep: Set<String> = ["LLC", "LLP", "LP", "PLC", "USA", "US", "UK", "AG", "SA", "NV", "BV", "GMBH", "II", "III", "FBO", "UPS", "DHL", "FAA", "NASA"]
        return name.split(separator: " ").map { word in
            let w = String(word)
            if keep.contains(w.trimmingCharacters(in: .punctuationCharacters)) { return w }
            return w.prefix(1) + w.dropFirst().lowercased()
        }.joined(separator: " ")
    }

    /// Whether a registered owner is a company, trust, airline or government body rather
    /// than a person. Leans to no: a private owner's name must never show.
    static func isOrganisation(_ name: String) -> Bool {
        let words = Set(name.uppercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
        let markers: Set<String> = [
            "INC", "LLC", "LLP", "LP", "LTD", "LIMITED", "CORP", "CORPORATION", "CO", "COMPANY", "PLC", "GMBH", "AG", "SA", "SAS",
            "NV", "BV", "SPA", "KG", "PTY", "BHD", "TRUST", "TRUSTEE", "BANK", "LEASING", "LEASE", "CAPITAL",
            "FINANCE", "HOLDINGS", "GROUP", "AIRLINES", "AIRLINE", "AIRWAYS", "AIR", "AVIATION", "AEROSPACE", "AERO", "JET", "JETS",
            "EXPRESS", "CARGO", "CHARTER", "CHARTERS", "SERVICES", "UNIVERSITY", "COLLEGE", "SCHOOL", "ACADEMY", "DEPARTMENT",
            "DEPT", "POLICE", "SHERIFF", "STATE", "COUNTY", "CITY", "GOVERNMENT", "MINISTRY", "FORCE", "NAVY", "ARMY", "GUARD",
            "MEDICAL", "HOSPITAL", "HEALTH", "FOUNDATION", "ASSOCIATION", "CLUB", "SOCIETY", "MUSEUM", "PARTNERS", "VENTURES",
            "ENTERPRISES", "INDUSTRIES", "INTERNATIONAL", "INTL", "FLIGHT", "FLYING", "HELICOPTERS", "HELICOPTER", "FEDEX",
        ]
        return !words.isDisjoint(with: markers)
    }
}
