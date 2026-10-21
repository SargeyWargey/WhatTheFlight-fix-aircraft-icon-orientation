//
//  WhereaboutsMap.swift
//  WhatTheFlight
//
//  Shared by the iPhone and Apple TV "Where is it now?" screens: the lookup itself
//  (refreshed every 30 seconds while the screen is open) and a map of where the aircraft is
//  relative to you, along its route when the feed knows one.
//

#if os(iOS) || os(tvOS)
import SwiftUI
import MapKit
import Observation

extension EnvironmentValues {
    /// Where the radar is watching from, for "N mi from you" on screens that don't hold the
    /// radar model (the logbook).
    @Entry var radarObserver: CLLocationCoordinate2D?
}

@MainActor
@Observable
final class WhereaboutsLookup {
    enum State: Equatable {
        case loading
        case found(Whereabouts)
        case notFound
        case failed(String)
    }

    private(set) var state: State = .loading
    private(set) var updatedAt: Date?

    @ObservationIgnored private let feed = FlightRadarFeed()

    var whereabouts: Whereabouts? {
        if case .found(let w) = state { return w }
        return nil
    }

    /// Looks the aircraft up now and again every 30 seconds until the calling task ends.
    func track(registration: String?, callsign: String?, seenFlightID: String?, observer: CLLocationCoordinate2D?) async {
        while !Task.isCancelled {
            await refresh(registration: registration, callsign: callsign, seenFlightID: seenFlightID, observer: observer)
            try? await Task.sleep(for: .seconds(30))
        }
    }

    func refresh(registration: String?, callsign: String?, seenFlightID: String?, observer: CLLocationCoordinate2D?) async {
        if whereabouts == nil { state = .loading }
        do {
            let flight = try await feed.locate(registration: registration, callsign: callsign)
            try Task.checkCancellation()
            state = flight.map { .found(Whereabouts(flight: $0, observer: observer, seenFlightID: seenFlightID)) } ?? .notFound
            updatedAt = Date()
        } catch is CancellationError {
            return
        } catch {
            // Keep showing the last fix; only an empty screen gets the error.
            if whereabouts == nil {
                state = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }
}

struct WhereaboutsMap: View {
    let whereabouts: Whereabouts
    let observer: CLLocationCoordinate2D?
    var height: CGFloat = 280
    var iconScale: CGFloat = 1

    @State private var camera: MapCameraPosition = .automatic

    private var flight: Flight { whereabouts.flight }

    /// Half a world away there's no useful map of both: show the aircraft and its route,
    /// and leave the distance to the text.
    private var shownObserver: CLLocationCoordinate2D? {
        guard let observer, (whereabouts.distanceMiles ?? 0) < 2_500 else { return nil }
        return observer
    }
    private var route: (from: CLLocationCoordinate2D, to: CLLocationCoordinate2D)? {
        guard !flight.isOnGround, let from = flight.origin?.coordinate, let to = flight.destination?.coordinate else { return nil }
        return (from, to)
    }

    var body: some View {
        let here = whereabouts.coordinate
        Map(position: $camera, interactionModes: []) {
            if let route {
                MapPolyline(coordinates: [route.from, here], contourStyle: .geodesic)
                    .stroke(Palette.route, style: StrokeStyle(lineWidth: 3 * iconScale, lineCap: .round))
                MapPolyline(coordinates: [here, route.to], contourStyle: .geodesic)
                    .stroke(Palette.signal.opacity(0.85), style: StrokeStyle(lineWidth: 2.5 * iconScale, lineCap: .round, dash: [7, 6]))
                Annotation(flight.origin?.name ?? "", coordinate: route.from, anchor: .bottom) {
                    AirportPin(code: flight.originIATA ?? "", filled: true).scaleEffect(iconScale)
                }
                Annotation(flight.destination?.name ?? "", coordinate: route.to, anchor: .bottom) {
                    AirportPin(code: flight.destinationIATA ?? "", filled: false).scaleEffect(iconScale)
                }
            }
            if let observer = shownObserver {
                MapPolyline(coordinates: [observer, here], contourStyle: .geodesic)
                    .stroke(Palette.ink.opacity(0.45), style: StrokeStyle(lineWidth: 1.5 * iconScale, dash: [3, 5]))
                Annotation("You", coordinate: observer, anchor: .center) {
                    Circle()
                        .fill(Palette.ink)
                        .frame(width: 12 * iconScale, height: 12 * iconScale)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .shadow(radius: 2)
                }
            }
            Annotation(flight.displayIdentifier, coordinate: here, anchor: .center) {
                Group {
                    if flight.kind == .helicopter {
                        Image("helicopter-bottom-view").resizable().renderingMode(.template).scaledToFit()
                            .frame(width: 28 * iconScale, height: 28 * iconScale)
                            .rotationEffect(.degrees(flight.track))
                    } else {
                        Image(systemName: "airplane")
                            .font(.system(size: 26 * iconScale, weight: .semibold))
                            .rotationEffect(.degrees(flight.track - 90))
                    }
                }
                .foregroundStyle(Palette.signal)
                .shadow(color: .black.opacity(0.3), radius: 2)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .frame(height: height)
        .allowsHitTesting(false)
        .clipShape(RoundedRectangle(cornerRadius: 18 * iconScale, style: .continuous))
        .onAppear { frame() }
        .onChange(of: flight.id) { _, _ in frame() }
    }

    /// You, the aircraft and both ends of its route, so the picture answers "how far?".
    private func frame() {
        var points = [whereabouts.coordinate]
        if let observer = shownObserver { points.append(observer) }
        if let route { points += [route.from, route.to] }
        camera = .region(DetailMap.region(fitting: points, padding: 1.4, minimumSpan: flight.isOnGround ? 0.08 : 0.5))
    }
}

extension Flight {
    /// Demo aircraft can't be looked up anywhere but the demo.
    var canLocate: Bool { !id.hasPrefix("demo") && (registration != nil || callsign != nil) }
}

extension Sighting {
    var canLocate: Bool { !id.hasPrefix("demo") && (registration != nil || callsign != nil) }
}
#endif
