//
//  ContentProvider.swift
//  WhatTheFlightTopShelf
//
//  The Apple TV's answer to widgets: with WhatTheFlight in the top row of the Home Screen,
//  the Top Shelf shows the aircraft around the spot the TV watches, with photos. Selecting
//  one opens it in the app.
//

import TVServices

final class ContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent() async -> TVTopShelfContent? {
        Catalogs.warmUp()
        let store = SharedRadarStore()
        // nil falls back to the static Top Shelf image.
        guard let snapshot = await NearbyTraffic.latestSnapshot(store: store), !snapshot.flights.isEmpty else { return nil }

        let flights = Array(snapshot.flights.prefix(8))
        let photos = await Self.photos(for: flights, within: .seconds(6))
        let items = flights.map { flight in
            let item = TVTopShelfSectionedItem(identifier: flight.id)
            item.title = [flight.identifier, flight.route, "\(RadarFormat.miles(flight.distanceMiles)) mi \(GeoMath.cardinal(flight.bearing))"]
                .compactMap { $0 }
                .joined(separator: " · ")
            item.imageShape = .hdtv
            if let photo = photos[flight.id] {
                item.setImageURL(photo.imageURL, for: .screenScale1x)
                item.setImageURL(photo.imageURL, for: .screenScale2x)
            }
            if let url = URL(string: "whattheflight://flight/\(flight.id)") {
                item.displayAction = TVTopShelfAction(url: url)
                item.playAction = TVTopShelfAction(url: url)
            }
            return item
        }

        let place = snapshot.placeName.map { " · \($0)" } ?? ""
        let collection = TVTopShelfItemCollection(items: items)
        collection.title = "\(snapshot.inRangeCount) overhead\(place)"
        return TVTopShelfSectionedContent(sections: [collection])
    }

    /// Photo lookups side by side, returning whatever has arrived by `limit`. Top Shelf's
    /// time is short and a lookup can take two requests; a row without photos beats no row.
    /// Lookups still running carry on and land in the cache for the next load.
    private static func photos(for flights: [SnapshotFlight], within limit: Duration) async -> [String: AircraftPhoto] {
        let collector = PhotoCollector(expected: flights.count)
        for flight in flights {
            Task {
                let photo = await AircraftPhotoProvider.shared.photo(registration: flight.registration, hex: flight.hex)
                await collector.add(flight.id, photo)
            }
        }
        // A task group would wait for every lookup before returning, deadline or not.
        let deadline = ContinuousClock.now + limit
        while ContinuousClock.now < deadline, !(await collector.isComplete) {
            try? await Task.sleep(for: .milliseconds(150))
        }
        return await collector.found
    }
}

private actor PhotoCollector {
    private let expected: Int
    private var finished = 0
    private(set) var found: [String: AircraftPhoto] = [:]

    init(expected: Int) { self.expected = expected }

    var isComplete: Bool { finished >= expected }

    func add(_ id: String, _ photo: AircraftPhoto?) {
        finished += 1
        if let photo { found[id] = photo }
    }
}
