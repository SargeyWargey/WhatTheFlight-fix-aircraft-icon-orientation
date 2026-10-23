//
//  ErrorHandlingTests.swift
//  WhatTheFlightTests
//
//  How feed failures are reported, and that an unreadable logbook is never saved over.
//

import XCTest
@testable import WhatTheFlight

/// Answers every request with whatever the test sets.
final class StubURLProtocol: URLProtocol {
    enum Reply { case failure(URLError.Code), status(Int, Data) }
    nonisolated(unsafe) static var reply: Reply = .status(200, Data())

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        switch Self.reply {
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case .status(let code, let body):
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
}

final class FeedErrorTests: XCTestCase {
    private func feed() -> FlightRadarFeed {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return FlightRadarFeed(session: URLSession(configuration: config))
    }

    private let bounds = GeographicBounds.around(center: TestTraffic.observer, radiusMiles: 10)

    private func error(for reply: StubURLProtocol.Reply) async -> Error? {
        StubURLProtocol.reply = reply
        do {
            _ = try await feed().flights(in: bounds)
            return nil
        } catch {
            return error
        }
    }

    func testConnectivityFailuresReadAsOffline() async {
        let offline = await error(for: .failure(.notConnectedToInternet))
        XCTAssertEqual(offline as? FeedError, .offline)
        let lost = await error(for: .failure(.networkConnectionLost))
        XCTAssertEqual(lost as? FeedError, .offline)
    }

    func testOnlineButUnreachableIsNotCalledOffline() async {
        let dns = await error(for: .failure(.cannotFindHost))
        XCTAssertEqual(dns as? FeedError, .unreachable)
        let tls = await error(for: .failure(.secureConnectionFailed))
        XCTAssertEqual(tls as? FeedError, .unreachable)
    }

    func testTimeoutsStatusesAndBadData() async {
        let timedOut = await error(for: .failure(.timedOut))
        XCTAssertEqual(timedOut as? FeedError, .timedOut)
        let limited = await error(for: .status(429, Data()))
        XCTAssertEqual(limited as? FeedError, .rateLimited)
        let server = await error(for: .status(503, Data()))
        XCTAssertEqual(server as? FeedError, .http(503))
        let garbage = await error(for: .status(200, Data("<html>".utf8)))
        XCTAssertEqual(garbage as? FeedError, .badData)
    }

    func testCancellationIsNotAnError() async {
        let cancelled = await error(for: .failure(.cancelled))
        XCTAssertTrue(cancelled is CancellationError)
    }
}

@MainActor
final class LogbookFileSafetyTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("LogbookFileSafety-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testAnUnreadableLogbookIsSetAsideNotOverwritten() throws {
        let file = directory.appendingPathComponent("Logbook.json")
        let damaged = Data("[{\"id\": \"half a sighting".utf8)
        try damaged.write(to: file)

        let book = Logbook(fileURL: file, photoDirectory: directory.appendingPathComponent("Photos"))
        XCTAssertTrue(book.sightings.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "moved out of the way of the next save")

        let kept = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("Logbook-unreadable-") }
        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(try Data(contentsOf: kept[0]), damaged)
    }

    func testAReadableLogbookLoads() throws {
        let file = directory.appendingPathComponent("Logbook.json")
        let first = Logbook(fileURL: nil)
        first.record([RadarContact(flight: TestTraffic.flight("a", miles: 3), observer: TestTraffic.observer, at: Date())])
        try JSONEncoder().encode(first.sightings).write(to: file)

        let book = Logbook(fileURL: file, photoDirectory: directory.appendingPathComponent("Photos"))
        XCTAssertEqual(book.sightings.map(\.id), ["a"])
    }

    func testUnreadableCopyName() {
        let url = URL(fileURLWithPath: "/tmp/Logbook.json")
        let copy = Logbook.unreadableCopyURL(for: url, at: Date(timeIntervalSince1970: 1_792_771_200))
        XCTAssertEqual(copy.lastPathComponent, "Logbook-unreadable-1792771200.json")
        XCTAssertEqual(copy.deletingLastPathComponent().path, "/tmp")
    }
}
