//
//  AirportDatabase.swift
//  WhatTheFlight
//
//  Created by Claude on 8/3/25.
//

import Foundation

/// Service for looking up airport names from IATA codes
/// Uses a local database of major airports for fast, offline lookups
class AirportDatabase {
    
    static let shared = AirportDatabase()
    
    private let airports: [String: String]
    
    private init() {
        // Initialize with a comprehensive list of major world airports
        // This covers the most common airports that commercial flights use
        self.airports = [
            // North America - Major Hubs
            "ATL": "Hartsfield-Jackson Atlanta International Airport",
            "LAX": "Los Angeles International Airport",
            "ORD": "Chicago O'Hare International Airport",
            "DFW": "Dallas/Fort Worth International Airport",
            "DEN": "Denver International Airport",
            "JFK": "John F. Kennedy International Airport",
            "SFO": "San Francisco International Airport",
            "SEA": "Seattle-Tacoma International Airport",
            "LAS": "Harry Reid International Airport",
            "MCO": "Orlando International Airport",
            "EWR": "Newark Liberty International Airport",
            "CLT": "Charlotte Douglas International Airport",
            "PHX": "Phoenix Sky Harbor International Airport",
            "IAH": "George Bush Intercontinental Airport",
            "MIA": "Miami International Airport",
            "BOS": "Boston Logan International Airport",
            "MSP": "Minneapolis-Saint Paul International Airport",
            "FLL": "Fort Lauderdale-Hollywood International Airport",
            "DTW": "Detroit Metropolitan Wayne County Airport",
            "PHL": "Philadelphia International Airport",
            "LGA": "LaGuardia Airport",
            "BWI": "Baltimore/Washington International Airport",
            "SLC": "Salt Lake City International Airport",
            "IAD": "Washington Dulles International Airport",
            "DCA": "Ronald Reagan Washington National Airport",
            "MDW": "Chicago Midway International Airport",
            "TPA": "Tampa International Airport",
            "PDX": "Portland International Airport",
            "STL": "St. Louis Lambert International Airport",
            "HNL": "Daniel K. Inouye International Airport",
            
            // Canada
            "YYZ": "Toronto Pearson International Airport",
            "YVR": "Vancouver International Airport",
            "YUL": "Montréal-Pierre Elliott Trudeau International Airport",
            "YYC": "Calgary International Airport",
            "YEG": "Edmonton International Airport",
            "YOW": "Ottawa Macdonald-Cartier International Airport",
            "YHZ": "Halifax Stanfield International Airport",
            "YWG": "Winnipeg James Armstrong Richardson International Airport",
            
            // Europe - Major Hubs
            "LHR": "London Heathrow Airport",
            "CDG": "Charles de Gaulle Airport",
            "AMS": "Amsterdam Airport Schiphol",
            "FRA": "Frankfurt Airport",
            "MAD": "Adolfo Suárez Madrid-Barajas Airport",
            "BCN": "Barcelona-El Prat Airport",
            "FCO": "Leonardo da Vinci International Airport",
            "LGW": "London Gatwick Airport",
            "MUC": "Munich Airport",
            "ZUR": "Zurich Airport",
            "VIE": "Vienna International Airport",
            "CPH": "Copenhagen Airport",
            "ARN": "Stockholm Arlanda Airport",
            "OSL": "Oslo Airport",
            "HEL": "Helsinki Airport",
            "DUB": "Dublin Airport",
            "BRU": "Brussels Airport",
            "LIS": "Lisbon Airport",
            "ATH": "Athens International Airport",
            "IST": "Istanbul Airport",
            "SVO": "Sheremetyevo International Airport",
            "LED": "Pulkovo Airport",
            
            // UK Regional
            "MAN": "Manchester Airport",
            "EDI": "Edinburgh Airport",
            "GLA": "Glasgow Airport",
            "BHX": "Birmingham Airport",
            "STN": "London Stansted Airport",
            "LTN": "London Luton Airport",
            "NCL": "Newcastle Airport",
            "LPL": "Liverpool John Lennon Airport",
            
            // Asia-Pacific - Major Hubs
            "NRT": "Narita International Airport",
            "HND": "Tokyo Haneda Airport",
            "ICN": "Incheon International Airport",
            "PEK": "Beijing Capital International Airport",
            "PVG": "Shanghai Pudong International Airport",
            "HKG": "Hong Kong International Airport",
            "SIN": "Singapore Changi Airport",
            "BKK": "Suvarnabhumi Airport",
            "KUL": "Kuala Lumpur International Airport",
            "CGK": "Soekarno-Hatta International Airport",
            "MNL": "Ninoy Aquino International Airport",
            "SYD": "Sydney Kingsford Smith Airport",
            "MEL": "Melbourne Airport",
            "BNE": "Brisbane Airport",
            "PER": "Perth Airport",
            "AKL": "Auckland Airport",
            "CHC": "Christchurch Airport",
            "DEL": "Indira Gandhi International Airport",
            "BOM": "Chhatrapati Shivaji Maharaj International Airport",
            "BLR": "Kempegowda International Airport",
            "MAA": "Chennai International Airport",
            
            // Middle East & Africa
            "DXB": "Dubai International Airport",
            "DOH": "Hamad International Airport",
            "AUH": "Abu Dhabi International Airport",
            "KWI": "Kuwait International Airport",
            "RUH": "King Khalid International Airport",
            "JED": "King Abdulaziz International Airport",
            "CAI": "Cairo International Airport",
            "JNB": "O.R. Tambo International Airport",
            "CPT": "Cape Town International Airport",
            "DUR": "King Shaka International Airport",
            "ADD": "Addis Ababa Bole International Airport",
            "NBO": "Jomo Kenyatta International Airport",
            "LOS": "Murtala Muhammed International Airport",
            "ACC": "Kotoka International Airport",
            
            // South America
            "GRU": "São Paulo/Guarulhos International Airport",
            "GIG": "Rio de Janeiro/Galeão International Airport",
            "EZE": "Ezeiza International Airport",
            "BOG": "El Dorado International Airport",
            "LIM": "Jorge Chávez International Airport",
            "SCL": "Arturo Merino Benítez International Airport",
            "UIO": "Mariscal Sucre International Airport",
            "CCS": "Simón Bolívar International Airport",
            
            // Regional US Airports
            "SAN": "San Diego International Airport",
            "AUS": "Austin-Bergstrom International Airport",
            "RDU": "Raleigh-Durham International Airport",
            "MCI": "Kansas City International Airport",
            "SMF": "Sacramento International Airport",
            "SJC": "Norman Y. Mineta San José International Airport",
            "OAK": "Oakland International Airport",
            "BUR": "Hollywood Burbank Airport",
            "SNA": "John Wayne Airport",
            "PSP": "Palm Springs International Airport",
            "FAT": "Fresno Yosemite International Airport",
            "RNO": "Reno-Tahoe International Airport",
            "ABQ": "Albuquerque International Sunport",
            "ELP": "El Paso International Airport",
            "SAT": "San Antonio International Airport",
            "MSY": "Louis Armstrong New Orleans International Airport",
            "MEM": "Memphis International Airport",
            "BNA": "Nashville International Airport",
            "JAX": "Jacksonville International Airport",
            "RSW": "Southwest Florida International Airport",
            "PBI": "Palm Beach International Airport",
            "FTL": "Fort Lauderdale Executive Airport",
            "CLE": "Cleveland Hopkins International Airport",
            "CMH": "John Glenn Columbus International Airport",
            "CVG": "Cincinnati/Northern Kentucky International Airport",
            "IND": "Indianapolis International Airport",
            "MKE": "Milwaukee Mitchell International Airport",
            "GRR": "Gerald R. Ford International Airport",
            "DSM": "Des Moines International Airport",
            "OMA": "Eppley Airfield",
            "ICT": "Wichita Dwight D. Eisenhower National Airport",
            "TUL": "Tulsa International Airport",
            "OKC": "Will Rogers World Airport",
            "LIT": "Bill and Hillary Clinton National Airport",
            "XNA": "Northwest Arkansas Regional Airport",
            "HSV": "Huntsville International Airport",
            "BHM": "Birmingham-Shuttlesworth International Airport",
            "MOB": "Mobile Regional Airport",
            "PNS": "Pensacola International Airport",
            "TLH": "Tallahassee International Airport",
            "GNV": "Gainesville Regional Airport",
            "DAB": "Daytona Beach International Airport",
            "SRQ": "Sarasota-Bradenton International Airport",
            "PIE": "St. Pete-Clearwater International Airport",
            "MLB": "Melbourne Orlando International Airport",
            "PFN": "Panama City-Bay County International Airport",
            "VPS": "Destin-Fort Walton Beach Airport",
            "MOD": "Modesto City-County Airport",
            "STS": "Charles M. Schulz Sonoma County Airport",
            "MRY": "Monterey Regional Airport",
            "SBP": "San Luis Obispo County Regional Airport",
            "SBA": "Santa Barbara Municipal Airport",
            "BFL": "Meadows Field",
            "IYK": "Inyokern Airport",
            
            // Additional International
            "TPE": "Taiwan Taoyuan International Airport",
            "KIX": "Kansai International Airport",
            "CTS": "New Chitose Airport",
            "FUK": "Fukuoka Airport",
            "OKA": "Naha Airport",
            "GMP": "Gimpo International Airport",
            "PUS": "Gimhae International Airport",
            "CJU": "Jeju International Airport",
            "SHA": "Shanghai Hongqiao International Airport",
            "CAN": "Guangzhou Baiyun International Airport",
            "SZX": "Shenzhen Bao'an International Airport",
            "XIY": "Xi'an Xianyang International Airport",
            "CTU": "Chengdu Tianfu International Airport",
            "KMG": "Kunming Changshui International Airport",
            "URC": "Ürümqi Diwopu International Airport",
            "TSN": "Tianjin Binhai International Airport",
            "NKG": "Nanjing Lukou International Airport",
            "HGH": "Hangzhou Xiaoshan International Airport",
            "WUH": "Wuhan Tianhe International Airport",
            "CGO": "Zhengzhou Xinzheng International Airport",
            "DLC": "Dalian Zhoushuizi International Airport",
            "SHE": "Shenyang Taoxian International Airport",
            "HRB": "Harbin Taiping International Airport",
            "LHW": "Lanzhou Zhongchuan International Airport"
        ]
    }
    
    /// Looks up the full airport name for a given IATA code
    /// - Parameter iataCode: The 3-letter IATA airport code (e.g., "LAX")
    /// - Returns: The full airport name, or nil if not found
    func getAirportName(for iataCode: String) -> String? {
        return airports[iataCode.uppercased()]
    }
    
    /// Looks up the full airport name with fallback to the IATA code
    /// - Parameter iataCode: The 3-letter IATA airport code (e.g., "LAX")
    /// - Returns: The full airport name, or the IATA code if not found
    func getAirportNameWithFallback(for iataCode: String) -> String {
        return getAirportName(for: iataCode) ?? iataCode
    }
    
    /// Returns all supported airport codes
    var supportedAirportCodes: Set<String> {
        return Set(airports.keys)
    }
    
    /// Returns the number of airports in the database
    var airportCount: Int {
        return airports.count
    }
}