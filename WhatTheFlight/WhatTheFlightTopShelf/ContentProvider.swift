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
        let store = SharedRadarStore()
        // nil falls back to the static Top Shelf image.
        guard let snapshot = await NearbyTraffic.latestSnapshot(store: store), !snapshot.flights.isEmpty else { return nil }

        var items: [TVTopShelfSectionedItem] = []
        for flight in snapshot.flights.prefix(8) {
            let item = TVTopShelfSectionedItem(identifier: flight.id)
            item.title = [flight.identifier, flight.route, "\(RadarFormat.miles(flight.distanceMiles)) mi \(GeoMath.cardinal(flight.bearing))"]
                .compactMap { $0 }
                .joined(separator: " · ")
            item.imageShape = .hdtv
            if let photo = await AircraftPhotoProvider.shared.photo(registration: flight.registration, hex: flight.hex) {
                item.setImageURL(photo.imageURL, for: .screenScale1x)
                item.setImageURL(photo.imageURL, for: .screenScale2x)
            }
            if let url = URL(string: "whattheflight://flight/\(flight.id)") {
                item.displayAction = TVTopShelfAction(url: url)
                item.playAction = TVTopShelfAction(url: url)
            }
            items.append(item)
        }

        let place = snapshot.placeName.map { " · \($0)" } ?? ""
        let collection = TVTopShelfItemCollection(items: items)
        collection.title = "\(snapshot.inRangeCount) overhead\(place)"
        return TVTopShelfSectionedContent(sections: [collection])
    }
}
