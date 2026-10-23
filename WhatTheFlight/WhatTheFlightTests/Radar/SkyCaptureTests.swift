//
//  SkyCaptureTests.swift
//  WhatTheFlightTests
//
//  Sky View zoom, visual lock-on and photos: field of view per zoom, lens stops, the dot
//  detector, the compass correction, frame reprojection, and photos in the logbook.
//

import XCTest
import CoreLocation
import simd
@testable import WhatTheFlight

final class CameraZoomTests: XCTestCase {
    /// An iPhone Pro: ultra-wide at factor 1 (0.5×), wide at 2 (1×), 5× telephoto at 10.
    private let pro = CameraZoom(baseFieldOfView: 106, displayMultiplier: 0.5, lensSwitchFactors: [2, 10], maxFactor: 190)

    func testZoomNarrowsTheTangentNotTheAngle() {
        XCTAssertEqual(pro.fieldOfView(at: 1), 106, accuracy: 1e-9)
        let at5x = pro.fieldOfView(at: 10)
        XCTAssertEqual(tan(at5x.radians / 2), tan(53.0.radians) / 10, accuracy: 1e-9)
        XCTAssertLessThan(at5x, 106.0 / 10 * 1.6)
    }

    func testStopsCoverEachLensPlusTwoX() {
        let labels = pro.stops.map { CameraZoom.label(pro.displayZoom(for: $0)) }
        XCTAssertEqual(labels, ["0.5", "1", "2", "5"])
        XCTAssertEqual(pro.standardFactor, 2)
    }

    func testDisplayZoomIsCapped() {
        XCTAssertEqual(pro.displayZoom(for: pro.maxFactor), CameraZoom.maxDisplayZoom, accuracy: 1e-9)
        XCTAssertEqual(pro.clamp(500), pro.maxFactor)
        XCTAssertEqual(pro.clamp(0.2), 1)
    }

    func testSingleLensPhoneStillHasOneAndTwoX() {
        let basic = CameraZoom(baseFieldOfView: 70, maxFactor: 16)
        XCTAssertEqual(basic.stops.map { CameraZoom.label(basic.displayZoom(for: $0)) }, ["1"])
        let dual = CameraZoom(baseFieldOfView: 70, lensSwitchFactors: [3], maxFactor: 16)
        XCTAssertEqual(dual.stops.map { CameraZoom.label(dual.displayZoom(for: $0)) }, ["1", "2", "3"])
    }

    func testLabels() {
        XCTAssertEqual(CameraZoom.label(0.5), "0.5")
        XCTAssertEqual(CameraZoom.label(2.04), "2")
        XCTAssertEqual(CameraZoom.label(2.4), "2.4")
    }
}

final class SkyProjectorFrameTests: XCTestCase {
    func testUnprojectInvertsProject() {
        let p = SkyProjector(azimuth: 120, pitch: 30, focalLength: 600, size: CGSize(width: 390, height: 844))
        let direction = SkyProjector.direction(azimuth: 126, elevation: 34)
        let point = p.project(direction).point
        let back = SkyProjector.azimuthElevation(p.unproject(point))
        XCTAssertEqual(back.azimuth, 126, accuracy: 1e-6)
        XCTAssertEqual(back.elevation, 34, accuracy: 1e-6)
    }

    func testReframedPhotoKeepsTheCentreAndScalesWithFieldOfView() {
        let screen = SkyProjector(azimuth: 0, pitch: 20, focalLength: 500, size: CGSize(width: 390, height: 844))
        let photo = screen.reframed(to: CGSize(width: 3024, height: 4032), longSideFieldOfView: 60)
        let centre = photo.project(azimuth: 0, elevation: 20).point
        XCTAssertEqual(centre.x, 1512, accuracy: 1e-6)
        XCTAssertEqual(centre.y, 2016, accuracy: 1e-6)
        // Half the long side away is half the field of view off-axis.
        let up = photo.project(SkyProjector.direction(azimuth: 0, elevation: 50)).point
        XCTAssertEqual(up.y, 0, accuracy: 1e-6)
    }
}

final class SkyBlobDetectorTests: XCTestCase {
    /// A noisy sky with optional dark dots and a dark band.
    private func sky(width: Int = 240, height: Int = 200, dots: [(Int, Int)] = [], bandRows: Range<Int>? = nil) -> [UInt8] {
        var generator = SystemRandomNumberGeneratorStub(seed: 7)
        var pixels = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                pixels[y * width + x] = UInt8(176 + Int(generator.next() % 7))
            }
        }
        for (cx, cy) in dots {
            for y in (cy - 1)...(cy + 1) { for x in (cx - 1)...(cx + 1) { pixels[y * width + x] = 70 } }
        }
        if let bandRows {
            for y in bandRows { for x in 0..<width { pixels[y * width + x] = 40 } }
        }
        return pixels
    }

    private func detect(_ pixels: [UInt8], width: Int = 240, height: Int = 200, around: CGPoint, radius: Double) -> SkyBlobDetector.Blob? {
        pixels.withUnsafeBufferPointer {
            SkyBlobDetector.detect(luma: $0.baseAddress!, width: width, height: height, bytesPerRow: width, around: around, radius: radius)
        }
    }

    func testFindsADarkDotNearThePrediction() {
        let blob = detect(sky(dots: [(131, 92)]), around: CGPoint(x: 115, y: 105), radius: 60)
        XCTAssertNotNil(blob)
        XCTAssertEqual(Double(blob?.point.x ?? 0), 131, accuracy: 1.5)
        XCTAssertEqual(Double(blob?.point.y ?? 0), 92, accuracy: 1.5)
    }

    func testEmptySkyFindsNothing() {
        XCTAssertNil(detect(sky(), around: CGPoint(x: 120, y: 100), radius: 60))
    }

    func testClutterIsNotTrusted() {
        XCTAssertNil(detect(sky(dots: [(131, 92)], bandRows: 110..<150), around: CGPoint(x: 120, y: 100), radius: 80))
    }

    func testTwoEqualDotsAreAmbiguous() {
        XCTAssertNil(detect(sky(dots: [(100, 100), (150, 100)]), around: CGPoint(x: 125, y: 100), radius: 60))
    }
}

final class SkyCorrectionTests: XCTestCase {
    func testLearnsACompassOffset() {
        var correction = SkyCorrection()
        let trueAzimuth = 207.0, compassThinks = 200.0
        for _ in 0..<30 {
            let predicted = SkyProjector.direction(azimuth: correction.azimuth(compassThinks), elevation: 20)
            correction.observe(predicted: predicted, observed: SkyProjector.direction(azimuth: trueAzimuth, elevation: 20))
        }
        XCTAssertEqual(correction.yaw, 7, accuracy: 0.3)
    }

    func testRejectsFarMatchesAndTheZenith() {
        var correction = SkyCorrection()
        XCTAssertFalse(correction.observe(predicted: SkyProjector.direction(azimuth: 10, elevation: 20),
                                          observed: SkyProjector.direction(azimuth: 40, elevation: 20)))
        XCTAssertFalse(correction.observe(predicted: SkyProjector.direction(azimuth: 10, elevation: 80),
                                          observed: SkyProjector.direction(azimuth: 30, elevation: 80)))
        XCTAssertEqual(correction.yaw, 0)
    }

    func testFixesExpire() {
        let now = Date()
        let fix = VisualFix(flightID: "a", direction: SIMD3(0, 1, 0), time: now)
        XCTAssertTrue(fix.isFresh(at: now.addingTimeInterval(0.3)))
        XCTAssertFalse(fix.isFresh(at: now.addingTimeInterval(1)))
    }
}

@MainActor
final class SpotPhotoLogbookTests: XCTestCase {
    private func contact(_ id: String, miles: Double, at date: Date = Date()) -> RadarContact {
        RadarContact(flight: TestTraffic.flight(id, miles: miles, at: date), observer: TestTraffic.observer, at: date)
    }

    private func photo(of contact: RadarContact, id: String = UUID().uuidString, at date: Date = Date()) -> SpotPhoto {
        SpotPhoto(id: id, contact: contact, takenAt: date, device: .iPhone, elevationDegrees: 12,
                  observer: TestTraffic.observer, placeName: "Atlanta, GA", displayZoom: 5,
                  framePoint: CGPoint(x: 0.5, y: 0.4), visuallyLocked: true, pixelWidth: 1200, pixelHeight: 1600)
    }

    func testPhotographingAnAircraftOutsideTheRadiusLogsIt() {
        let book = Logbook(fileURL: nil, device: .iPhone)
        let c = contact("far", miles: 40)
        var savedPhotos = Set<String>()
        book.onLocalPhotoChange = { saved, _ in savedPhotos.formUnion(saved) }
        let p = photo(of: c, id: "p1")
        XCTAssertTrue(book.addPhoto(p, imageData: Data([1, 2, 3]), contact: c, observer: TestTraffic.observer))
        XCTAssertEqual(book.sighting(id: "far")?.spotPhotos.map(\.id), ["p1"])
        XCTAssertEqual(book.photoStore.data("p1"), Data([1, 2, 3]))
        XCTAssertEqual(savedPhotos, ["p1"])
        XCTAssertEqual(book.allPhotoIDs, ["p1"])
    }

    func testRemovingAPhotoDeletesItsImageAndSticksThroughAMerge() {
        let phone = Logbook(fileURL: nil, device: .iPhone)
        let c = contact("a", miles: 3)
        phone.addPhoto(photo(of: c, id: "p1"), imageData: Data([9]), contact: c)
        let olderCopy = phone.sightings
        phone.removePhoto(id: "p1")
        XCTAssertNil(phone.photoStore.data("p1"))
        XCTAssertEqual(phone.sighting(id: "a")?.spotPhotos, [])

        // Another device still has the photo: merging its copy must not bring it back.
        let differs = phone.merge(remote: olderCopy)
        XCTAssertEqual(phone.sighting(id: "a")?.spotPhotos, [])
        XCTAssertEqual(differs, ["a"], "Our copy knows about the deletion, so it goes back up")
    }

    func testPhotosFromTwoDevicesMerge() {
        let phone = Logbook(fileURL: nil, device: .iPhone)
        let ipad = Logbook(fileURL: nil, device: .iPad)
        let c = contact("a", miles: 3)
        let now = Date()
        phone.addPhoto(photo(of: c, id: "p1", at: now), imageData: Data([1]), contact: c)
        ipad.addPhoto(photo(of: c, id: "p2", at: now.addingTimeInterval(5)), imageData: Data([2]), contact: c)
        phone.merge(remote: ipad.sightings)
        XCTAssertEqual(phone.sighting(id: "a")?.spotPhotos.map(\.id), ["p1", "p2"])
    }

    func testDeletingASightingDeletesItsPhotos() {
        let book = Logbook(fileURL: nil, device: .iPhone)
        let c = contact("a", miles: 3)
        var deletedPhotos = Set<String>()
        book.onLocalPhotoChange = { _, deleted in deletedPhotos.formUnion(deleted) }
        book.addPhoto(photo(of: c, id: "p1"), imageData: Data([1]), contact: c)
        book.delete(["a"])
        XCTAssertNil(book.photoStore.data("p1"))
        XCTAssertEqual(deletedPhotos, ["p1"])
    }

    func testOldSightingsWithoutPhotosStillDecode() throws {
        let book = Logbook(fileURL: nil, device: .iPhone)
        book.record([contact("a", miles: 3)])
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(book.sightings[0])) as! [String: Any]
        json["photos"] = nil
        json["removedPhotoIDs"] = nil
        let decoded = try JSONDecoder().decode(Sighting.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.spotPhotos, [])
    }

    func testRouteMilesComeFromTheAirports() {
        var p = photo(of: contact("a", miles: 3))
        p.originIATA = "ATL"
        p.destinationIATA = "JFK"
        let miles = try? XCTUnwrap(p.routeMiles)
        XCTAssertNotNil(miles)
        XCTAssertEqual((miles?.flown ?? 0) + (miles?.remaining ?? 0), 760, accuracy: 30)
    }
}

/// Deterministic noise for the synthetic sky.
private struct SystemRandomNumberGeneratorStub {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state >> 33
    }
}
