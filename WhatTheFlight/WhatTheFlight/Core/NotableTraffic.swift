//
//  NotableTraffic.swift
//  WhatTheFlight
//
//  Picks out aircraft worth a second look: emergency squawks, military and government
//  flights, air ambulances, and rare or iconic types (A380, 747, Beluga, B-52…).
//

import Foundation

enum NotableTag: String, CaseIterable, Codable, Sendable, Comparable {
    case hijack, emergency, radioFailure, medical, military, government, rare

    /// Lower sorts first: the most urgent tag wins the badge.
    var priority: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    static func < (lhs: NotableTag, rhs: NotableTag) -> Bool { lhs.priority < rhs.priority }

    var isEmergency: Bool { self == .hijack || self == .emergency || self == .radioFailure }

    var symbol: String {
        switch self {
        case .hijack, .emergency: return "exclamationmark.triangle.fill"
        case .radioFailure: return "antenna.radiowaves.left.and.right.slash"
        case .medical: return "cross.case.fill"
        case .military: return "shield.lefthalf.filled"
        case .government: return "building.columns.fill"
        case .rare: return "star.fill"
        }
    }
}

struct NotableInfo: Equatable, Sendable {
    let tag: NotableTag
    /// Short badge text: "EMERGENCY 7700", "MILITARY", "RARE · A380".
    let badge: String
    /// Sentence for alerts: "squawking 7700 (general emergency)".
    let reason: String
}

enum NotableTraffic {
    static func classify(_ flight: Flight) -> [NotableInfo] {
        var found: [NotableInfo] = []
        switch flight.squawk {
        case "7500": found.append(NotableInfo(tag: .hijack, badge: "SQUAWK 7500", reason: "squawking 7500 (unlawful interference)"))
        case "7700": found.append(NotableInfo(tag: .emergency, badge: "EMERGENCY 7700", reason: "squawking 7700 (general emergency)"))
        case "7600": found.append(NotableInfo(tag: .radioFailure, badge: "RADIO FAIL 7600", reason: "squawking 7600 (lost radio contact)"))
        default: break
        }

        let operatorKind = flight.operatorInfo.kind
        let type = flight.typeCode?.uppercased() ?? ""
        if operatorKind == .medical || isAirAmbulanceCallsign(flight.callsign) {
            found.append(NotableInfo(tag: .medical, badge: "AIR AMBULANCE", reason: "is an air ambulance"))
        }
        if operatorKind == .military || militaryTypes[type] != nil {
            found.append(NotableInfo(tag: .military, badge: "MILITARY", reason: "is a military \(militaryTypes[type] ?? "flight")"))
        } else if operatorKind == .government {
            found.append(NotableInfo(tag: .government, badge: "GOVERNMENT", reason: "is a government flight"))
        }
        if let rare = rareTypes[type] {
            found.append(NotableInfo(tag: .rare, badge: "RARE · \(rare.short)", reason: "is a \(rare.name)"))
        }
        return found.sorted { $0.tag < $1.tag }
    }

    private static func isAirAmbulanceCallsign(_ callsign: String?) -> Bool {
        guard let callsign = callsign?.uppercased() else { return false }
        let letters = String(callsign.prefix { $0.isLetter })
        return AirlineCatalog.medicalWords.contains(letters)
    }

    /// Types that are worth running outside for.
    static let rareTypes: [String: (short: String, name: String)] = [
        "A388": ("A380", "Airbus A380 superjumbo"),
        "B741": ("747", "Boeing 747-100"),
        "B742": ("747", "Boeing 747-200"),
        "B743": ("747", "Boeing 747-300"),
        "B744": ("747", "Boeing 747-400, the Queen of the Skies"),
        "B748": ("747-8", "Boeing 747-8, the Queen of the Skies"),
        "B74S": ("747SP", "Boeing 747SP"),
        "BLCF": ("DREAMLIFTER", "Boeing 747 Dreamlifter"),
        "A3ST": ("BELUGA", "Airbus Beluga"),
        "A337": ("BELUGA XL", "Airbus BelugaXL"),
        "A124": ("AN-124", "Antonov An-124 Ruslan"),
        "A225": ("AN-225", "Antonov An-225 Mriya"),
        "AN22": ("AN-22", "Antonov An-22"),
        "C5M": ("C-5", "Lockheed C-5 Galaxy"),
        "C5": ("C-5", "Lockheed C-5 Galaxy"),
        "B52": ("B-52", "Boeing B-52 Stratofortress"),
        "VC25": ("AIR FORCE ONE", "VC-25 (Air Force One's jet)"),
        "U2": ("U-2", "Lockheed U-2 Dragon Lady"),
        "CONC": ("CONCORDE", "Concorde"),
        "L101": ("TRISTAR", "Lockheed L-1011 TriStar"),
        "DC10": ("DC-10", "McDonnell Douglas DC-10"),
        "MD11": ("MD-11", "McDonnell Douglas MD-11"),
        "B703": ("707", "Boeing 707"),
        "DC3": ("DC-3", "Douglas DC-3"),
        "C47": ("C-47", "Douglas C-47 Skytrain"),
        "DC6": ("DC-6", "Douglas DC-6"),
        "B17": ("B-17", "Boeing B-17 Flying Fortress"),
        "B29": ("B-29", "Boeing B-29 Superfortress"),
        "P51": ("P-51", "North American P-51 Mustang"),
        "SPIT": ("SPITFIRE", "Supermarine Spitfire"),
        "A342": ("A340", "Airbus A340-200"),
        "A343": ("A340", "Airbus A340-300"),
        "A345": ("A340", "Airbus A340-500"),
        "A346": ("A340", "Airbus A340-600"),
        "BALL": ("BALLOON", "hot-air balloon"),
        "SHIP": ("AIRSHIP", "airship"),
    ]

    /// Military-only types (the airframe gives it away whatever the callsign).
    static let militaryTypes: [String: String] = [
        "C17": "C-17 Globemaster III", "C130": "C-130 Hercules", "C30J": "C-130J Super Hercules",
        "C5M": "C-5 Galaxy", "K35R": "KC-135 Stratotanker", "E3TF": "E-3 Sentry (AWACS)",
        "E3CF": "E-3 Sentry (AWACS)", "E6": "E-6 Mercury", "P8": "P-8 Poseidon", "F16": "F-16 Fighting Falcon",
        "F15": "F-15 Eagle", "F18H": "F/A-18 Hornet", "F18S": "F/A-18 Super Hornet", "F35": "F-35 Lightning II",
        "F22": "F-22 Raptor", "A10": "A-10 Thunderbolt II", "B52": "B-52 Stratofortress", "B1": "B-1 Lancer",
        "V22": "V-22 Osprey", "H60": "Black Hawk", "H47": "Chinook", "H64": "Apache", "T38": "T-38 Talon",
        "U2": "U-2 Dragon Lady", "A400": "A400M Atlas", "VC25": "VC-25",
    ]
}

extension Flight {
    var notable: [NotableInfo] { NotableTraffic.classify(self) }
}
