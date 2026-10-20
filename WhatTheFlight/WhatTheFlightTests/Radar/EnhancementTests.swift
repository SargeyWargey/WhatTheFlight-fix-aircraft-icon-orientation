//
//  EnhancementTests.swift
//  WhatTheFlightTests
//
//  Catalogs, operator lines, notable traffic, Sky View geometry, the logbook and alerts.
//

import XCTest
import CoreLocation
@testable import WhatTheFlight

private func flight(callsign: String? = nil, airline: String? = nil, registration: String? = nil,
                    type: String? = "B738", squawk: String? = nil, number: String? = nil,
                    miles: Double = 5, bearing: Double = 0, track: Double = 180, speed: Int = 0,
                    altitude: Int = 10_000, id: String = "f1") -> Flight {
    var f = TestTraffic.flight(id, miles: miles, bearing: bearing, track: track, speed: speed, type: type ?? "")
    f.typeCode = type
    f.callsign = callsign
    f.airlineICAO = airline
    f.registration = registration
    f.squawk = squawk
    f.flightNumber = number
    f.altitudeFeet = altitude
    return f
}

final class CatalogTests: XCTestCase {
    func testCuratedAirlineNamesWinButGainRadioCallsigns() {
        let delta = AirlineCatalog.airline(icao: "DAL")
        XCTAssertEqual(delta?.name, "Delta Air Lines")
        XCTAssertEqual(delta?.radioCallsign, "DELTA")
        XCTAssertEqual(AirlineCatalog.airline(icao: "FDX")?.name, "FedEx Express")
    }

    func testGeneratedCatalogCoversOperatorsMissingFromTheCuratedList() {
        XCTAssertNotNil(AirlineCatalog.airline(icao: "KLM"))
        XCTAssertEqual(AirlineCatalog.airline(icao: "BAW")?.radioCallsign, "SPEEDBIRD")
        // Atlas Air's sister / regional style operators that used to read "Private / Unlisted".
        XCTAssertNotNil(AirlineCatalog.airline(icao: nil, callsign: "LXJ302", flightNumber: nil))
    }

    func testCallsignPrefixNeedsAFlightNumberAfterThreeLetters() {
        XCTAssertEqual(AirlineCatalog.icaoPrefix(ofCallsign: "DAL1032"), "DAL")
        XCTAssertNil(AirlineCatalog.icaoPrefix(ofCallsign: "LIFE2"))
        XCTAssertNil(AirlineCatalog.icaoPrefix(ofCallsign: "N5404T"))
    }

    func testSpecialCallsignWords() {
        XCTAssertEqual(AirlineCatalog.airline(icao: nil, callsign: "SAM44", flightNumber: nil)?.name, "US Air Force · Special Air Mission")
        XCTAssertEqual(AirlineCatalog.airline(icao: nil, callsign: "LIFE2", flightNumber: nil)?.name, "Air ambulance")
    }

    func testAirportsHaveCoordinatesAndCuratedNames() throws {
        let atl = try XCTUnwrap(AirportCatalog.airport(iata: "ATL"))
        XCTAssertEqual(atl.name, "Hartsfield–Jackson Atlanta Intl")
        let coordinate = try XCTUnwrap(atl.coordinate)
        XCTAssertEqual(coordinate.latitude, 33.64, accuracy: 0.05)
        XCTAssertEqual(coordinate.longitude, -84.43, accuracy: 0.05)
        // Small airports that weren't in the curated list now resolve too.
        XCTAssertEqual(AirportCatalog.airport(iata: "FTY")?.city, "Atlanta")
        XCTAssertEqual(AirportCatalog.airport(iata: "LHR")?.countryCode, "GB")
    }
}

final class OperatorInfoTests: XCTestCase {
    func testRegistrationCountries() {
        XCTAssertEqual(RegistrationCountry.countryCode(forRegistration: "N685DA"), "US")
        XCTAssertEqual(RegistrationCountry.countryCode(forRegistration: "C-FTJP"), "CA")
        XCTAssertEqual(RegistrationCountry.countryCode(forRegistration: "G-EUPT"), "GB")
        XCTAssertEqual(RegistrationCountry.countryCode(forRegistration: "A6-EUA"), "AE")
        XCTAssertEqual(RegistrationCountry.countryCode(forRegistration: "VP-BJS"), "BM")
        XCTAssertEqual(RegistrationCountry.countryCode(forRegistration: "B-HNR"), "HK")
        XCTAssertEqual(RegistrationCountry.countryCode(forRegistration: "B-18908"), "TW")
        XCTAssertEqual(RegistrationCountry.countryCode(forRegistration: "JA873A"), "JP")
        XCTAssertNil(RegistrationCountry.countryCode(forRegistration: "XYZ"))
        XCTAssertEqual(RegistrationCountry.flag(forCode: "US"), "🇺🇸")
    }

    func testAirlineOperator() {
        let info = flight(callsign: "DAL570", airline: "DAL", registration: "N685DA").operatorInfo
        XCTAssertEqual(info.kind, .airline)
        XCTAssertEqual(info.headline, "Delta Air Lines")
        XCTAssertEqual(info.subtitle, "Radio “DELTA” · United States")
    }

    func testPrivateAircraftFlyingUnderItsTailNumber() {
        let info = flight(callsign: "N5404T", registration: "N5404T", type: "C172").operatorInfo
        XCTAssertEqual(info.kind, .privateAircraft)
        XCTAssertEqual(info.headline, "Private aircraft · 🇺🇸 United States")
    }

    func testPrivateHelicopter() {
        let info = flight(callsign: "N44RH", registration: "N44RH", type: "R44").operatorInfo
        XCTAssertEqual(info.title, "Private helicopter")
    }

    func testUnknownOperatorStillShowsItsDesignator() {
        let info = flight(callsign: "QZX270", registration: "N1289Y", type: "C172").operatorInfo
        XCTAssertEqual(info.kind, .unlisted)
        XCTAssertEqual(info.headline, "Unlisted operator QZX · 🇺🇸 United States")
    }

    func testMilitaryOperator() {
        XCTAssertEqual(flight(callsign: "RCH123", type: "C17").operatorInfo.kind, .military)
    }
}

final class NotableTrafficTests: XCTestCase {
    func testEmergencySquawkComesFirst() {
        let tags = flight(callsign: "UAE211", airline: "UAE", type: "A388", squawk: "7700").notable.map(\.tag)
        XCTAssertEqual(tags, [.emergency, .rare])
    }

    func testMilitaryByTypeOrOperator() {
        XCTAssertEqual(flight(callsign: "RCH123", type: "C17").notable.map(\.tag), [.military])
        XCTAssertTrue(flight(callsign: "N12345", type: "F16").notable.map(\.tag).contains(.military))
    }

    func testAirAmbulanceAndOrdinaryTraffic() {
        XCTAssertEqual(flight(callsign: "LIFE2", type: "EC45").notable.map(\.tag), [.medical])
        XCTAssertTrue(flight(callsign: "DAL570", airline: "DAL", type: "B752").notable.isEmpty)
    }

    func testRareBadge() {
        XCTAssertEqual(flight(type: "B748").notable.first?.badge, "RARE · 747-8")
    }
}

final class SkyGeometryTests: XCTestCase {
    func testElevation() {
        // 10,000 ft at ~1.9 mi is ~45°.
        XCTAssertEqual(GeoMath.elevationDegrees(groundDistanceMiles: 10_000 / 5280, altitudeFeet: 10_000), 45, accuracy: 0.1)
        // Earth curvature: 35,000 ft at 200 mi sits just below the horizon.
        XCTAssertLessThan(GeoMath.elevationDegrees(groundDistanceMiles: 200, altitudeFeet: 35_000), 0.5)
        XCTAssertEqual(GeoMath.elevationDegrees(groundDistanceMiles: 0, altitudeFeet: 5000), 90)
    }

    func testProjectorCentreAndSides() {
        let size = CGSize(width: 400, height: 800)
        let cam = SkyProjector(azimuth: 90, pitch: 30, focalLength: 400, size: size)
        let centre = cam.project(azimuth: 90, elevation: 30)
        XCTAssertTrue(centre.isInFront)
        XCTAssertEqual(centre.point.x, 200, accuracy: 0.001)
        XCTAssertEqual(centre.point.y, 400, accuracy: 0.001)
        // Something further clockwise (south of east) appears to the right; higher appears above.
        XCTAssertGreaterThan(cam.project(azimuth: 100, elevation: 30).point.x, 200)
        XCTAssertLessThan(cam.project(azimuth: 90, elevation: 40).point.y, 400)
        // Behind the camera: not in front, but the arrow still points somewhere sensible.
        XCTAssertFalse(cam.project(azimuth: 270, elevation: 0).isInFront)
        XCTAssertEqual(cam.lookAzimuth, 90, accuracy: 0.001)
        XCTAssertEqual(cam.lookElevation, 30, accuracy: 0.001)
    }

    func testFocalLength() {
        // 90° across 400 pt → focal length 200.
        XCTAssertEqual(SkyProjector.focalLength(fieldOfView: 90, across: 400), 200, accuracy: 0.001)
    }
}

@MainActor
final class LogbookTests: XCTestCase {
    func testRecordsOncePerFlightAndKeepsTheClosestPass() {
        let book = Logbook(fileURL: nil)
        let far = RadarContact(flight: flight(callsign: "DAL1", airline: "DAL", registration: "N1DL", miles: 8), observer: TestTraffic.observer, at: Date())
        let near = RadarContact(flight: flight(callsign: "DAL1", airline: "DAL", registration: "N1DL", miles: 2), observer: TestTraffic.observer, at: Date())
        book.record([far])
        book.record([near])
        book.record([far])
        XCTAssertEqual(book.sightings.count, 1)
        XCTAssertEqual(book.sightings[0].closestMiles, 2, accuracy: 0.05)
        XCTAssertEqual(book.sightings[0].operatorName, "Delta Air Lines")
        XCTAssertEqual(book.timesSeen(airframe: "N1DL"), 1)
    }

    func testStatsAndAchievements() {
        let book = Logbook(fileURL: nil)
        book.record([
            RadarContact(flight: flight(callsign: "UAE211", airline: "UAE", registration: "A6-EUA", type: "A388", miles: 0.3, id: "a"), observer: TestTraffic.observer, at: Date()),
            RadarContact(flight: flight(callsign: "N44RH", registration: "N44RH", type: "R44", miles: 3, id: "b"), observer: TestTraffic.observer, at: Date()),
        ])
        let stats = LogbookStats(book.sightings)
        XCTAssertEqual(stats.total, 2)
        XCTAssertEqual(stats.helicopters, 1)
        XCTAssertEqual(stats.uniqueAirlines, 1)
        XCTAssertEqual(stats.closest?.id, "a")
        let unlocked = Set(Achievement.all(for: book.sightings).filter(\.isUnlocked).map(\.id))
        XCTAssertTrue(unlocked.isSuperset(of: ["first", "superjumbo", "overhead"]))
        XCTAssertFalse(unlocked.contains("queen"))

        let all = Achievement.all(for: book.sightings)
        let jumbo = try! XCTUnwrap(all.first { $0.id == "superjumbo" })
        XCTAssertEqual(jumbo.unlockedBy?.id, "a")
        XCTAssertEqual(jumbo.examples.map(\.id), ["a"])
        let spotter = try! XCTUnwrap(all.first { $0.id == "spotter" })
        XCTAssertNil(spotter.unlockedBy)
        XCTAssertEqual(spotter.examples.map(\.id), ["b", "a"], "newest first")
    }

    func testDistinctBadgesListOneSightingPerAirline() {
        let book = Logbook(fileURL: nil)
        for (i, airline) in ["DAL", "DAL", "UAL"].enumerated() {
            book.record([RadarContact(flight: flight(callsign: "\(airline)\(i + 1)", airline: airline, miles: 4, id: "f\(i)"), observer: TestTraffic.observer, at: Date())])
        }
        let globetrotter = Achievement.all(for: book.sightings).first { $0.id == "airlines" }
        XCTAssertEqual(globetrotter?.progress, 2)
        XCTAssertEqual(globetrotter?.examples.map(\.id), ["f2", "f0"])
    }

    func testPersistsToDisk() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("logbook-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let book = Logbook(fileURL: url)
        book.record([RadarContact(flight: flight(callsign: "DAL1", miles: 4), observer: TestTraffic.observer, at: Date())])
        let deadline = Date().addingTimeInterval(3)
        while !FileManager.default.fileExists(atPath: url.path), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        // Let the background write finish.
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(Logbook(fileURL: url).sightings.count, 1)
    }
}

final class TrafficAlertTests: XCTestCase {
    func testOverheadAlertFiresOnceForAnApproachingAircraft() {
        // 3 mi north, flying south at 300 kts: passes straight over in ~31 s.
        let contact = RadarContact(flight: flight(callsign: "DAL570", miles: 3, bearing: 0, track: 180, speed: 300), observer: TestTraffic.observer, at: Date())
        var engine = TrafficAlertEngine()
        let first = engine.evaluate([contact], rules: TrafficAlertRules())
        XCTAssertEqual(first.map(\.reason), [.overhead])
        XCTAssertTrue(first[0].title.hasPrefix("DAL570 overhead in"))
        XCTAssertTrue(engine.evaluate([contact], rules: TrafficAlertRules()).isEmpty)
    }

    func testNoAlertForDistantOrDepartingTraffic() {
        let away = RadarContact(flight: flight(miles: 3, bearing: 0, track: 0, speed: 300), observer: TestTraffic.observer, at: Date())
        let wide = RadarContact(flight: flight(miles: 6, bearing: 0, track: 90, speed: 300, id: "f2"), observer: TestTraffic.observer, at: Date())
        var engine = TrafficAlertEngine()
        XCTAssertTrue(engine.evaluate([away, wide], rules: TrafficAlertRules()).isEmpty)
    }

    func testNotableAlertRespectsTheSwitch() {
        let c17 = RadarContact(flight: flight(callsign: "RCH123", type: "C17", miles: 8, bearing: 90, track: 90, speed: 300), observer: TestTraffic.observer, at: Date())
        var engine = TrafficAlertEngine()
        XCTAssertTrue(engine.evaluate([c17], rules: TrafficAlertRules(notable: false)).isEmpty)
        var fresh = TrafficAlertEngine()
        XCTAssertEqual(fresh.evaluate([c17], rules: TrafficAlertRules()).map(\.reason), [.notable])
    }
}

final class RouteAndSnapshotTests: XCTestCase {
    func testRouteProgressSplitsTheGreatCircle() throws {
        // Halfway-ish between Atlanta and Chicago O'Hare.
        var f = flight(callsign: "DAL1", airline: "DAL", speed: 450)
        f.originIATA = "ATL"
        f.destinationIATA = "ORD"
        let atl = try XCTUnwrap(AirportCatalog.airport(iata: "ATL")?.coordinate)
        let ord = try XCTUnwrap(AirportCatalog.airport(iata: "ORD")?.coordinate)
        let total = GeoMath.distanceMiles(from: atl, to: ord)
        let mid = GeoMath.destination(from: atl, bearingDegrees: GeoMath.bearing(from: atl, to: ord), distanceMiles: total / 2)
        let progress = try XCTUnwrap(RouteProgress(flight: f, position: mid))
        XCTAssertEqual(progress.fraction, 0.5, accuracy: 0.01)
        XCTAssertEqual(progress.flownMiles + progress.remainingMiles, total, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(progress.remainingSeconds) / 60, (total / 2) / (450 * GeoMath.milesPerKnotHour) * 60, accuracy: 1)
        XCTAssertEqual(RouteProgress.duration(3900), "1h 05m")
        XCTAssertEqual(RouteProgress.duration(720), "12m")
    }

    func testRouteProgressNeedsBothAirports() {
        var f = flight()
        f.originIATA = "ATL"
        f.destinationIATA = "ZZZ"
        XCTAssertNil(RouteProgress(flight: f, position: TestTraffic.observer))
    }

    func testSnapshotRoundTripsThroughTheSharedStore() throws {
        let suite = "wtf-tests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SharedRadarStore(defaults: defaults)
        XCTAssertNil(store.observer)
        store.observer = TestTraffic.observer
        store.radiusMiles = 25
        let contacts = [RadarContact(flight: flight(callsign: "UAE211", airline: "UAE", registration: "A6-EUA", type: "A388", miles: 3), observer: TestTraffic.observer, at: Date())]
        store.snapshot = RadarSnapshot(placeName: "Atlanta", radiusMiles: 25, contacts: contacts)

        let read = try XCTUnwrap(store.snapshot)
        XCTAssertEqual(read.inRangeCount, 1)
        XCTAssertEqual(read.flights.first?.notableBadge, "RARE · A380")
        XCTAssertEqual(read.flights.first?.registration, "A6-EUA")
        XCTAssertEqual(store.observer?.latitude ?? 0, TestTraffic.observer.latitude, accuracy: 1e-9)
        XCTAssertEqual(store.radiusMiles, 25)
    }
}

final class SpokenTrafficTests: XCTestCase {
    func testAirlineFlightsReadNaturally() {
        var f = flight(callsign: "DAL1199", airline: "DAL", number: "DL1199", miles: 3, bearing: 0, track: 180, speed: 300, altitude: 9_480)
        f.originIATA = "ATL"
        f.destinationIATA = "ORD"
        let contact = RadarContact(flight: f, observer: TestTraffic.observer, at: Date())
        let sentence = SpokenTraffic.sentence(for: contact, reason: .overhead)
        XCTAssertTrue(sentence.hasPrefix("Delta Air Lines flight 1199, from Atlanta to Chicago, is approaching overhead"), sentence)
        XCTAssertTrue(sentence.contains("at 9,500 feet. Look north."), sentence)
    }

    func testAirlineCodesWithDigitsAreStripped() {
        XCTAssertEqual(SpokenTraffic.spokenName(flight(callsign: "JBU1897", airline: "JBU", number: "B61897")), "JetBlue flight 1897")
        XCTAssertEqual(SpokenTraffic.spokenName(flight(callsign: "UPS1303", airline: "UPS", number: "5X1303")), "UPS Airlines flight 1303")
        XCTAssertEqual(SpokenTraffic.spokenName(flight(callsign: "DAL570", airline: "DAL")), "Delta Air Lines flight 570")
    }

    func testPrivateAircraftAreSpelledOut() {
        let f = flight(callsign: "N5404T", registration: "N5404T", type: "C172", miles: 0.3)
        XCTAssertEqual(SpokenTraffic.spokenName(f), "Private aircraft N 5 4 0 4 T")
        let contact = RadarContact(flight: f, observer: TestTraffic.observer, at: Date())
        XCTAssertTrue(SpokenTraffic.sentence(for: contact, reason: .overhead).contains("is passing overhead now"))
    }

    func testEmergencySquawkIsSpokenDigitByDigit() {
        let f = flight(callsign: "UAL902", airline: "UAL", type: "B789", squawk: "7700", number: "UA902", miles: 8, bearing: 90)
        let contact = RadarContact(flight: f, observer: TestTraffic.observer, at: Date())
        let sentence = SpokenTraffic.sentence(for: contact, reason: .notable)
        XCTAssertTrue(sentence.contains("United Airlines flight 902"), sentence)
        XCTAssertTrue(sentence.contains("squawking 7 7 0 0, general emergency"), sentence)
        XCTAssertFalse(sentence.contains("("))
    }
}
