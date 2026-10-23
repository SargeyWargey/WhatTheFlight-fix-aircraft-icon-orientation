//
//  RegistrationCountry.swift
//  WhatTheFlight
//
//  Aircraft registration (tail number) → country of registry, from the ICAO nationality
//  marks: "N685DA" → US, "G-EUPT" → GB, "A6-EUA" → AE.
//

import Foundation

enum RegistrationCountry {
    /// ISO 3166 country code for a registration, or nil if it isn't recognisable.
    static func countryCode(forRegistration registration: String?) -> String? {
        guard let reg = registration?.uppercased().trimmingCharacters(in: .whitespaces), reg.count >= 3 else { return nil }
        if isUSRegistration(reg) { return "US" }
        if let dash = reg.firstIndex(of: "-") {
            let mark = String(reg[..<dash])
            let rest = reg[reg.index(after: dash)...]
            if mark == "B" {
                // China shares "B-" with Hong Kong (B-H/K/L), Macau (B-M) and Taiwan (5 digits).
                switch rest.first {
                case "H", "K", "L": return "HK"
                case "M": return "MO"
                default: return rest.count == 5 && rest.allSatisfy(\.isNumber) ? "TW" : "CN"
                }
            }
            // British overseas territories carry one more letter: VP-B (Bermuda), VP-C (Cayman)…
            if let letter = rest.first, let territory = marks["\(mark)-\(letter)"] { return territory }
            return marks[mark]
        }
        // A few registries write their marks without a hyphen.
        for prefix in ["JA", "HL", "HI"] where reg.hasPrefix(prefix) {
            return marks[prefix]
        }
        return nil
    }

    /// "N" followed by 1–5 characters, starting with a digit 1–9 ("N5404T", "N44RH").
    static func isUSRegistration(_ value: String) -> Bool {
        let chars = Array(value.uppercased())
        guard chars.count >= 2, chars.count <= 6, chars[0] == "N", let first = chars[1].wholeNumberValue, first > 0 else { return false }
        return chars.dropFirst().allSatisfy { ($0.isASCII && $0.isLetter) || $0.isNumber }
    }

    /// "GXLEI" → ["G-XLEI"], "A6EUI" → ["A6-EUI"]: what a tail number typed without its hyphen
    /// could be. Flightradar24 only matches registrations as written, hyphen included.
    static func hyphenatedForms(of value: String) -> [String] {
        let reg = value.uppercased()
        guard !reg.contains("-"), !isUSRegistration(reg) else { return [] }
        return marks.keys
            .filter { !$0.contains("-") && reg.hasPrefix($0) && reg.count > $0.count + 1 }
            .map { "\($0)-\(reg.dropFirst($0.count))" }
            .sorted()
    }

    /// English country name for an ISO code ("US" → "United States").
    static func countryName(forCode code: String) -> String {
        Locale(identifier: "en_US").localizedString(forRegionCode: code) ?? code
    }

    /// 🇺🇸 from "US".
    static func flag(forCode code: String) -> String {
        let base: UInt32 = 127_397
        return code.uppercased().unicodeScalars.compactMap { UnicodeScalar(base + $0.value) }.map(String.init).joined()
    }

    private static let marks: [String: String] = {
        var table: [String: String] = [:]
        for pair in raw.split(whereSeparator: \.isWhitespace) {
            let p = pair.split(separator: ":")
            guard p.count == 2 else { continue }
            table[String(p[0])] = String(p[1])
        }
        return table
    }()

    // nationality mark:ISO country
    private static let raw = """
    C:CA CF:CA CG:CA CI:CA G:GB D:DE F:FR I:IT EC:ES PH:NL OO:BE HB:CH OE:AT SE:SE LN:NO OY:DK OH:FI
    TF:IS EI:IE CS:PT SX:GR TC:TR SP:PL OK:CZ OM:SK HA:HU YR:RO LZ:BG 9A:HR S5:SI YU:RS UR:UA RA:RU
    RF:RU EW:BY ES:EE YL:LV LY:LT ER:MD Z3:MK ZA:AL T9:BA E7:BA 4O:ME 9H:MT 5B:CY LX:LU 3A:MC T7:SM
    HV:VA M:IM 2:GG ZJ:JE 4X:IL A6:AE A7:QA A9C:BH A4O:OM HZ:SA 9K:KW EP:IR YI:IQ JY:JO OD:LB YK:SY
    7O:YE SU:EG CN:MA 7T:DZ TS:TN 5A:LY ST:SD ET:ET 5Y:KE 5H:TZ 5X:UG 9XR:RW ZS:ZA ZT:ZA ZU:ZA 5N:NG
    9G:GH 6V:SN TU:CI TJ:CM 9Q:CD D2:AO C9:MZ A2:BW V5:NA 9J:ZM Z:ZW 5R:MG 3B:MU S7:SC D4:CV TR:GA
    VT:IN AP:PK S2:BD 4R:LK 8Q:MV 9N:NP A5:BT JA:JP HL:KR P:KP HS:TH 9M:MY 9V:SG PK:ID RP:PH VN:VN
    XU:KH RDPL:LA XY:MM UP:KZ UK:UZ EX:KG EY:TJ EZ:TM 4K:AZ 4L:GE EK:AM JU:MN YA:AF VH:AU ZK:NZ
    P2:PG DQ:FJ YJ:VU H4:SB A3:TO 5W:WS T3:KI V7:MH V6:FM C2:NR XA:MX XB:MX XC:MX TI:CR HP:PA
    TG:GT YS:SV HR:HN YN:NI V3:BZ HI:DO CU:CU HH:HT 6Y:JM C6:BS 8P:BB 9Y:TT J3:GD J6:LC J8:VC
    V2:AG V4:KN J7:DM VP-A:AI VP-B:BM VQ-B:BM VP-C:KY VP-F:FK VP-L:VG VP-M:MS VQ-T:TC PJ:CW P4:AW
    HK:CO YV:VE HC:EC OB:PE CP:BO CC:CL LV:AR LQ:AR CX:UY ZP:PY PP:BR PR:BR PT:BR PS:BR PU:BR 8R:GY
    PZ:SR
    """
}
