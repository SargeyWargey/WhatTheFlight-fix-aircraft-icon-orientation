//
//  AircraftTypeCatalog.swift
//  WhatTheFlight
//
//  ICAO type designators → friendly names, helicopter detection and radar silhouettes.
//

import Foundation

enum AircraftTypeCatalog {
    static func name(forTypeCode code: String?) -> String? {
        guard let code = code?.uppercased(), !code.isEmpty else { return nil }
        return names[code]
    }

    static func kind(forTypeCode code: String?) -> AircraftKind {
        guard let code = code?.uppercased(), !code.isEmpty else { return .airplane }
        return helicopterCodes.contains(code) ? .helicopter : .airplane
    }

    /// Unknown or missing codes get the airliner.
    static func silhouette(forTypeCode code: String?) -> AircraftSilhouette {
        guard let code = code?.uppercased(), !code.isEmpty else { return .airliner }
        if helicopterCodes.contains(code) { return .helicopter }
        return silhouettes[code] ?? .airliner
    }

    private static let silhouettes: [String: AircraftSilhouette] = {
        var table: [String: AircraftSilhouette] = [:]
        for (silhouette, codes) in silhouetteCodes {
            for code in codes { table[code] = silhouette }
        }
        return table
    }()

    /// Airliner-shaped military jets (KC-46, P-8) are listed by shape; the military colour
    /// comes from `NotableTraffic`.
    static let silhouetteCodes: [AircraftSilhouette: Set<String>] = [
        .widebody: [
            "A306", "A30B", "A310", "A332", "A333", "A338", "A339", "A359", "A35K", "A3ST", "A337",
            "B762", "B763", "B764", "B772", "B77L", "B773", "B77W", "B778", "B779", "B788", "B789", "B78X",
            "MD11", "DC10", "L101", "KC46", "K46", "KC10", "IL96",
        ],
        .fourEngine: [
            "A342", "A343", "A345", "A346", "A388", "B741", "B742", "B743", "B744", "B748", "B74S", "BLCF",
            "B703", "B720", "DC8", "DC86", "DC87", "IL62", "K35R", "K35E", "E3TF", "E3CF", "E6", "VC25", "B52",
            "R135", "C135", "BA46", "RJ85", "RJ1H",
        ],
        .regional: [
            "CRJ1", "CRJ2", "CRJ7", "CRJ9", "CRJX", "E135", "E145", "E170", "E175", "E75L", "E75S", "E190",
            "E195", "E290", "E295", "B712", "DC91", "DC93", "DC95", "MD80", "MD81", "MD82", "MD83", "MD87",
            "MD88", "MD90", "F70", "F100",
        ],
        .bizjet: [
            "C25A", "C25B", "C25C", "C25M", "C501", "C510", "C525", "C550", "C551", "C560", "C56X", "C650",
            "C680", "C68A", "C700", "C750", "E35L", "E50P", "E55P", "E545", "E550", "PC24", "CL30", "CL35",
            "CL60", "GL5T", "GLEX", "GL7T", "GL6T", "LJ31", "LJ35", "LJ40", "LJ45", "LJ55", "LJ60", "LJ70",
            "LJ75", "GLF3", "GLF4", "GLF5", "GLF6", "GA5C", "GA6C", "GA7C", "GA8C", "G150", "G280", "GALX",
            "ASTR", "F2TH", "F900", "FA10", "FA20", "FA50", "FA6X", "FA7X", "FA8X", "H25A", "H25B", "H25C",
            "HA4T", "HDJT", "BE40", "PRM1", "SF50", "EA50", "C21A",
        ],
        .twinProp: [
            "AT43", "AT44", "AT45", "AT46", "AT72", "AT73", "AT75", "AT76", "DH8A", "DH8B", "DH8C", "DH8D",
            "DHC6", "DHC7", "SF34", "SB20", "JS31", "JS32", "JS41", "B190", "BE99", "BE20", "BE30", "BE9L",
            "BE9T", "B350", "BE10", "BE55", "BE58", "BE60", "BE76", "C310", "C340", "C402", "C404", "C414",
            "C421", "C425", "C441", "PA23", "PA27", "PA31", "PA34", "PA44", "P68", "DA42", "DA62", "PAY2",
            "PAY3", "PAY4", "MU2", "SW4", "E120", "F50", "D228", "D328", "L410", "C212", "AN24", "AN26",
            "P180", "AC90", "AC95",
        ],
        .light: [
            "C150", "C152", "C162", "C170", "C172", "C177", "C180", "C182", "C185", "C195", "C206", "C207",
            "C208", "C210", "P210", "PA18", "PA20", "PA22", "PA24", "PA28", "PA32", "PA38", "PA46", "P28A",
            "P28B", "P28R", "P28T", "P32R", "P32T", "P46T", "SR20", "SR22", "S22T", "DA20", "DV20", "DA40",
            "DA50", "BE23", "BE33", "BE35", "BE36", "M20P", "M20T", "M20J", "PC6T", "PC12", "PC21", "TBM7",
            "TBM8", "TBM9", "KODI", "GA8", "AA5", "RV7", "RV8", "RV10", "CH7A", "J3", "T6", "TEX2", "GLID",
        ],
        .fighter: [
            "F14", "F15", "F16", "F18H", "F18S", "F22", "F35", "F5", "F117", "A10", "A4", "AV8B", "B1", "B2",
            "T38", "T45", "T7", "HAWK", "EUFI", "RFAL", "M2K", "TOR", "GRIF", "U2",
        ],
        .militaryTransport: [
            "C17", "C130", "C30J", "C5", "C5M", "A400", "A124", "A225", "IL76", "C160", "C27J", "C295",
            "CN35", "KC39", "AN12", "AN22",
        ],
    ]

    /// ICAO designators for rotorcraft.
    static let helicopterCodes: Set<String> = [
        "A109", "A119", "A129", "A139", "A149", "A169", "A189", "ALO2", "ALO3", "AS32", "AS3B", "AS50",
        "AS55", "AS65", "B06", "B06T", "B105", "B212", "B222", "B230", "B407", "B412", "B427", "B429",
        "B430", "B505", "B525", "BK17", "EC20", "EC25", "EC30", "EC35", "EC45", "EC55", "EC75", "EH10",
        "EXPL", "GAZL", "H2", "H269", "H47", "H500", "H53", "H53S", "H60", "H64", "H46", "HUCO", "KA27",
        "KA32", "KA50", "KA52", "LYNX", "MD52", "MD60", "MI8", "MI17", "MI24", "MI26", "MI28", "NH90",
        "PUMA", "R22", "R44", "R66", "S61", "S64", "S76", "S92", "TIGR", "UH1", "UH1Y", "AH1", "V22",
        "EN28", "EN48", "S300", "S330", "CABR", "G2CA", "UH72", "H160", "H125", "H130", "H135", "H145",
        "H155", "H175", "H215", "H225", "AW09", "B47G", "BH06", "BH12",
    ]

    private static let names: [String: String] = {
        var table: [String: String] = [:]
        for line in raw.split(separator: "\n") {
            let parts = line.split(separator: "|", maxSplits: 1)
            guard parts.count == 2 else { continue }
            table[String(parts[0])] = String(parts[1])
        }
        return table
    }()

    private static let raw = """
    A124|Antonov An-124
    A19N|Airbus A319neo
    A20N|Airbus A320neo
    A21N|Airbus A321neo
    A306|Airbus A300-600
    A30B|Airbus A300
    A310|Airbus A310
    A318|Airbus A318
    A319|Airbus A319
    A320|Airbus A320
    A321|Airbus A321
    A332|Airbus A330-200
    A333|Airbus A330-300
    A338|Airbus A330-800neo
    A339|Airbus A330-900neo
    A342|Airbus A340-200
    A343|Airbus A340-300
    A345|Airbus A340-500
    A346|Airbus A340-600
    A359|Airbus A350-900
    A35K|Airbus A350-1000
    A388|Airbus A380-800
    A3ST|Airbus Beluga
    BCS1|Airbus A220-100
    BCS3|Airbus A220-300
    B37M|Boeing 737 MAX 7
    B38M|Boeing 737 MAX 8
    B39M|Boeing 737 MAX 9
    B3XM|Boeing 737 MAX 10
    B712|Boeing 717-200
    B721|Boeing 727-100
    B722|Boeing 727-200
    B732|Boeing 737-200
    B733|Boeing 737-300
    B734|Boeing 737-400
    B735|Boeing 737-500
    B736|Boeing 737-600
    B737|Boeing 737-700
    B738|Boeing 737-800
    B739|Boeing 737-900
    B741|Boeing 747-100
    B742|Boeing 747-200
    B744|Boeing 747-400
    B748|Boeing 747-8
    B74S|Boeing 747SP
    B752|Boeing 757-200
    B753|Boeing 757-300
    B762|Boeing 767-200
    B763|Boeing 767-300
    B764|Boeing 767-400
    B772|Boeing 777-200
    B77L|Boeing 777-200LR
    B773|Boeing 777-300
    B77W|Boeing 777-300ER
    B778|Boeing 777-8
    B779|Boeing 777-9
    B788|Boeing 787-8 Dreamliner
    B789|Boeing 787-9 Dreamliner
    B78X|Boeing 787-10 Dreamliner
    BLCF|Boeing 747 Dreamlifter
    MD11|McDonnell Douglas MD-11
    MD80|McDonnell Douglas MD-80
    MD82|McDonnell Douglas MD-82
    MD83|McDonnell Douglas MD-83
    MD88|McDonnell Douglas MD-88
    MD90|McDonnell Douglas MD-90
    DC10|McDonnell Douglas DC-10
    DC93|McDonnell Douglas DC-9-30
    CRJ1|Bombardier CRJ100
    CRJ2|Bombardier CRJ200
    CRJ7|Bombardier CRJ700
    CRJ9|Bombardier CRJ900
    CRJX|Bombardier CRJ1000
    E135|Embraer ERJ-135
    E145|Embraer ERJ-145
    E170|Embraer E170
    E175|Embraer E175
    E75L|Embraer E175
    E75S|Embraer E175
    E190|Embraer E190
    E195|Embraer E195
    E290|Embraer E190-E2
    E295|Embraer E195-E2
    E35L|Embraer Legacy 600
    E50P|Embraer Phenom 100
    E55P|Embraer Phenom 300
    E545|Embraer Legacy 450
    EA50|Eclipse 500
    E550|Embraer Praetor 600
    AT43|ATR 42-300
    AT45|ATR 42-500
    AT46|ATR 42-600
    AT72|ATR 72
    AT75|ATR 72-500
    AT76|ATR 72-600
    DH8A|Dash 8-100
    DH8B|Dash 8-200
    DH8C|Dash 8-300
    DH8D|Dash 8 Q400
    DHC6|DHC-6 Twin Otter
    SF34|Saab 340
    SB20|Saab 2000
    JS41|Jetstream 41
    B190|Beechcraft 1900
    C208|Cessna 208 Caravan
    C172|Cessna 172 Skyhawk
    C152|Cessna 152
    C150|Cessna 150
    C162|Cessna Skycatcher
    C182|Cessna 182 Skylane
    C206|Cessna 206 Stationair
    C210|Cessna 210 Centurion
    C310|Cessna 310
    C340|Cessna 340
    C414|Cessna 414
    C421|Cessna 421
    C25A|Cessna Citation CJ2
    C25B|Cessna Citation CJ3
    C25C|Cessna Citation CJ4
    C510|Cessna Citation Mustang
    C525|Cessna CitationJet
    C550|Cessna Citation II
    C560|Cessna Citation V
    C56X|Cessna Citation Excel
    C650|Cessna Citation III
    C680|Cessna Citation Sovereign
    C68A|Cessna Citation Latitude
    C700|Cessna Citation Longitude
    C750|Cessna Citation X
    PA28|Piper Cherokee
    PA32|Piper Saratoga
    PA34|Piper Seneca
    PA44|Piper Seminole
    PA46|Piper Malibu
    P28A|Piper Cherokee
    P28B|Piper Turbo Cherokee
    P28R|Piper Arrow
    P32R|Piper Lance
    P46T|Piper Malibu Meridian
    SR20|Cirrus SR20
    SR22|Cirrus SR22
    S22T|Cirrus SR22T
    SF50|Cirrus Vision Jet
    DA40|Diamond DA40
    DA42|Diamond DA42
    DA62|Diamond DA62
    BE20|Beechcraft King Air 200
    BE30|Beechcraft King Air 300
    BE35|Beechcraft Bonanza
    BE36|Beechcraft Bonanza
    BE40|Beechcraft Beechjet
    BE55|Beechcraft Baron
    BE58|Beechcraft Baron
    BE9L|Beechcraft King Air 90
    B350|Beechcraft King Air 350
    M20P|Mooney M20
    M20T|Mooney M20 Turbo
    PC12|Pilatus PC-12
    PC24|Pilatus PC-24
    TBM7|Daher TBM 700
    TBM8|Daher TBM 850
    TBM9|Daher TBM 900
    CL30|Bombardier Challenger 300
    CL35|Bombardier Challenger 350
    CL60|Bombardier Challenger 600
    GL5T|Bombardier Global 5000
    GLEX|Bombardier Global Express
    GL7T|Bombardier Global 7500
    LJ35|Learjet 35
    LJ45|Learjet 45
    LJ60|Learjet 60
    LJ75|Learjet 75
    GLF4|Gulfstream IV
    GLF5|Gulfstream V
    GLF6|Gulfstream G650
    GA6C|Gulfstream G600
    GA7C|Gulfstream G700
    G280|Gulfstream G280
    F2TH|Dassault Falcon 2000
    F900|Dassault Falcon 900
    FA7X|Dassault Falcon 7X
    FA8X|Dassault Falcon 8X
    FA50|Dassault Falcon 50
    H25B|Hawker 800
    HDJT|HondaJet
    C130|Lockheed C-130 Hercules
    C30J|Lockheed C-130J Super Hercules
    C17|Boeing C-17 Globemaster III
    C5M|Lockheed C-5M Super Galaxy
    K35R|Boeing KC-135 Stratotanker
    KC46|Boeing KC-46 Pegasus
    P8|Boeing P-8 Poseidon
    E3TF|Boeing E-3 Sentry
    F16|F-16 Fighting Falcon
    F18S|F/A-18 Super Hornet
    F35|F-35 Lightning II
    T38|Northrop T-38 Talon
    B52|Boeing B-52 Stratofortress
    A400|Airbus A400M Atlas
    GLID|Glider
    BALL|Balloon
    A109|Leonardo AW109
    A119|Leonardo AW119
    A139|Leonardo AW139
    A169|Leonardo AW169
    A189|Leonardo AW189
    AS50|Airbus H125 / AS350
    AS55|Airbus AS355 Ecureuil
    AS65|Airbus AS365 Dauphin
    B06|Bell 206 JetRanger
    B407|Bell 407
    B412|Bell 412
    B429|Bell 429
    B505|Bell 505
    BK17|Airbus BK117
    EC20|Airbus H120
    EC30|Airbus H130
    EC35|Airbus H135
    EC45|Airbus H145
    EC55|Airbus H155
    EC75|Airbus H175
    EC25|Airbus H225
    H60|Sikorsky UH-60 Black Hawk
    H47|Boeing CH-47 Chinook
    H64|Boeing AH-64 Apache
    MD52|MD 520N
    MD60|MD 600N
    EXPL|MD Explorer
    R22|Robinson R22
    R44|Robinson R44
    R66|Robinson R66
    S76|Sikorsky S-76
    S92|Sikorsky S-92
    UH1|Bell UH-1 Iroquois
    V22|Bell Boeing V-22 Osprey
    """
}
