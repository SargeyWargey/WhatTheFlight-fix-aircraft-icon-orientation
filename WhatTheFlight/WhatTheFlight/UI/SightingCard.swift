//
//  SightingCard.swift
//  WhatTheFlight
//
//  A shareable card for any aircraft, live or in the logbook (Enhancements Spec C4): its
//  silhouette, flight, operator, route with cities, type, altitude, speed, closest pass,
//  where and when, over a map of its track. 360 × 450 pt rendered at 3× (1080 × 1350, the
//  4 : 5 Instagram size). No Planespotters photo: their terms don't cover redistribution, so
//  the silhouette and map carry it. Sky View photos get the boarding pass (`SpotCard`).
//

#if os(iOS)
import SwiftUI
import MapKit

/// Everything the card shows, from a live contact or a logbook sighting.
struct SightingCardInfo: Sendable {
    var identifier: String
    var operatorName: String
    var typeName: String?
    var registration: String?
    var origin: (code: String, city: String?)?
    var destination: (code: String, city: String?)?
    var altitudeFeet: Int
    var speedKnots: Int
    /// Closest pass so far (a sighting), or the distance now (live).
    var closestMiles: Double
    var closestLabel: String
    var date: Date
    var placeName: String?
    var silhouette: AircraftSilhouette
    var track: Double?
    var aircraft: CLLocationCoordinate2D?
    var observer: CLLocationCoordinate2D?
    var trail: [CLLocationCoordinate2D]
    var badge: String?

    init(contact: RadarContact, observer: CLLocationCoordinate2D?, trail: [CLLocationCoordinate2D], placeName: String?) {
        let f = contact.flight
        identifier = f.displayIdentifier
        operatorName = contact.profile.operatorInfo.title
        typeName = contact.profile.typeName ?? f.typeCode
        registration = f.registration
        origin = f.hasRoute ? (f.originIATA ?? "", f.origin?.city) : nil
        destination = f.hasRoute ? (f.destinationIATA ?? "", f.destination?.city) : nil
        altitudeFeet = contact.altitudeFeet
        speedKnots = f.groundSpeedKnots
        closestMiles = contact.isApproaching ? contact.closestApproach.distanceMiles : contact.distanceMiles
        closestLabel = contact.isApproaching ? "Closest pass" : "Distance"
        date = Date()
        self.placeName = placeName
        silhouette = contact.profile.silhouette
        track = f.track
        aircraft = contact.coordinate
        self.observer = observer
        self.trail = trail + [contact.coordinate]
        badge = contact.profile.notable.first?.badge
    }

    init(sighting s: Sighting) {
        identifier = s.displayIdentifier
        operatorName = s.operatorName
        typeName = s.typeName ?? s.typeCode
        registration = s.registration
        origin = s.originIATA.map { ($0, s.origin?.city) }
        destination = s.destinationIATA.map { ($0, s.destination?.city) }
        altitudeFeet = s.altitudeAtClosestFeet
        speedKnots = s.speedKnots
        closestMiles = s.closestMiles
        closestLabel = "Closest pass"
        date = s.firstSeen
        placeName = s.placeName
        silhouette = s.silhouette
        track = s.trackAtClosest
        aircraft = s.closestCoordinate
        observer = s.observerCoordinate
        // A sighting keeps one point: draw a short stretch of its heading through it.
        if let at = s.closestCoordinate, let track = s.trackAtClosest {
            trail = [GeoMath.extrapolate(at, trackDegrees: track + 180, speedKnots: 300, seconds: 60), at]
        } else {
            trail = []
        }
        badge = s.tags.first?.rawValue.capitalized
    }
}

struct SightingShareCard: View {
    let info: SightingCardInfo
    /// The map behind the top half, with where to draw the trail, you and the aircraft.
    let map: SightingCardRenderer.MapSnapshot?

    static let size = CGSize(width: 360, height: 450)
    static let mapHeight: CGFloat = 196

    private enum Ink {
        static let paper = Color(UIColor(rgb: 0xF4F1EA))
        static let text = Color(UIColor(rgb: 0x1C2140))
        static let ink = Color(UIColor(rgb: 0x3A33D6))
        static let accent = Color(UIColor(rgb: 0xE5483B))
        static let route = Color(UIColor(rgb: 0x5A5FD8))
        static let muted = Color(UIColor(rgb: 0x6F6A60))
        static let rule = Color(UIColor(rgb: 0xDAD3C6))
    }

    var body: some View {
        VStack(spacing: 0) {
            mapArea
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(info.operatorName.uppercased())
                            .font(.mono(10, .bold))
                            .tracking(1.2)
                            .foregroundStyle(Ink.muted)
                            .lineLimit(1)
                        Text(info.identifier)
                            .font(.mono(40, .heavy))
                            .foregroundStyle(Ink.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                    Spacer(minLength: 8)
                    if let badge = info.badge {
                        Text(badge.uppercased())
                            .font(.mono(9, .heavy))
                            .tracking(1)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Ink.accent, in: Capsule())
                    }
                }
                if let origin = info.origin, let destination = info.destination {
                    HStack(alignment: .top, spacing: 10) {
                        endpoint(origin)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Ink.accent)
                            .padding(.top, 5)
                        endpoint(destination)
                        Spacer(minLength: 0)
                    }
                }
                Rectangle().fill(Ink.rule).frame(height: 1).padding(.vertical, 2)
                HStack(alignment: .top, spacing: 0) {
                    stat("Altitude", RadarFormat.altitudeText(info.altitudeFeet))
                    stat("Speed", RadarFormat.speedText(info.speedKnots))
                    stat(info.closestLabel, RadarFormat.preciseDistance(info.closestMiles))
                }
                HStack(alignment: .top, spacing: 0) {
                    stat("Aircraft", info.typeName ?? "—")
                    stat("Tail", info.registration ?? "—")
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 10, weight: .bold))
                    Text([info.placeName, info.date.formatted(date: .abbreviated, time: .shortened)].compactMap { $0 }.joined(separator: " · "))
                        .font(.mono(10, .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 4)
                    Text("WHAT THE FLIGHT?")
                        .font(.mono(9, .heavy))
                        .tracking(1)
                        .foregroundStyle(Ink.ink)
                }
                .foregroundStyle(Ink.muted)
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, 16)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Ink.paper)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .environment(\.colorScheme, .light)
    }

    private var mapArea: some View {
        ZStack(alignment: .topLeading) {
            if let map {
                Image(uiImage: map.image)
                    .resizable()
                    .frame(width: Self.size.width, height: Self.mapHeight)
                    .overlay(Ink.paper.opacity(0.25))
                Path { path in
                    guard let first = map.trail.first else { return }
                    path.move(to: first)
                    for p in map.trail.dropFirst() { path.addLine(to: p) }
                }
                .stroke(Ink.ink.opacity(0.75), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                if let you = map.observer {
                    Circle().fill(Ink.accent)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .position(you)
                }
                if let at = map.aircraft {
                    AircraftGlyph(silhouette: info.silhouette, size: 34, spinsRotor: false)
                        .foregroundStyle(Ink.ink)
                        .rotationEffect(.degrees(info.track ?? 0))
                        .shadow(color: .white, radius: 2)
                        .position(at)
                }
            } else {
                LinearGradient(colors: [Color(UIColor(rgb: 0x5B94DB)), Color(UIColor(rgb: 0xBCD9F2))], startPoint: .top, endPoint: .bottom)
                AircraftGlyph(silhouette: info.silhouette, size: 96, spinsRotor: false)
                    .foregroundStyle(.white.opacity(0.9))
                    .rotationEffect(.degrees(info.track ?? 45))
                    .frame(width: Self.size.width, height: Self.mapHeight)
            }
        }
        .frame(width: Self.size.width, height: Self.mapHeight, alignment: .topLeading)
        .clipped()
    }

    private func endpoint(_ end: (code: String, city: String?)) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(end.code)
                .font(.mono(26, .bold))
                .foregroundStyle(Ink.route)
            if let city = end.city {
                Text(city)
                    .font(.mono(9, .medium))
                    .foregroundStyle(Ink.muted)
                    .lineLimit(1)
                    .frame(maxWidth: 110, alignment: .leading)
            }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.mono(8, .bold))
                .tracking(1.2)
                .foregroundStyle(Ink.muted)
            Text(value)
                .font(.mono(14, .bold))
                .foregroundStyle(Ink.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor
enum SightingCardRenderer {
    /// A map image and where the trail, the observer and the aircraft fall on it.
    struct MapSnapshot {
        let image: UIImage
        let trail: [CGPoint]
        let observer: CGPoint?
        let aircraft: CGPoint?
    }

    /// The card as an image, map and all. Nil only if rendering fails.
    static func render(_ info: SightingCardInfo) async -> UIImage? {
        let map = await snapshot(info, size: CGSize(width: SightingShareCard.size.width, height: SightingShareCard.mapHeight))
        let card = SightingShareCard(info: info, map: map)
            .padding(20)
            .background(LinearGradient(colors: [Color(UIColor(rgb: 0x0E1630)), Color(UIColor(rgb: 0x23305C))],
                                       startPoint: .top, endPoint: .bottom))
        let renderer = ImageRenderer(content: card)
        renderer.proposedSize = ProposedViewSize(width: SightingShareCard.size.width + 40, height: SightingShareCard.size.height + 40)
        renderer.scale = 3
        renderer.isOpaque = true
        return renderer.uiImage
    }

    static func snapshot(_ info: SightingCardInfo, size: CGSize) async -> MapSnapshot? {
        let points = info.trail + [info.observer, info.aircraft].compactMap { $0 }
        guard !points.isEmpty else { return nil }
        let lats = points.map(\.latitude), lons = points.map(\.longitude)
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lons.min()! + lons.max()!) / 2)
        // At least ~6 mi across, with room around the edges, at the card's aspect.
        let latSpan = max(0.09, (lats.max()! - lats.min()!) * 1.5)
        let lonSpan = max(0.09 * size.width / size.height / max(0.2, cos(center.latitude * .pi / 180)), (lons.max()! - lons.min()!) * 1.5)
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: lonSpan))
        options.size = size
        options.scale = 3
        options.mapType = .mutedStandard
        options.pointOfInterestFilter = .excludingAll
        options.traitCollection = UITraitCollection(userInterfaceStyle: .light)
        do {
            let shot = try await MKMapSnapshotter(options: options).start()
            return MapSnapshot(image: shot.image,
                               trail: info.trail.map { shot.point(for: $0) },
                               observer: info.observer.map { shot.point(for: $0) },
                               aircraft: info.aircraft.map { shot.point(for: $0) })
        } catch {
            Log.ui.info("Card map snapshot failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

/// A Share button that offers the card once it's ready (and the text straight away).
struct SightingShareButton<Label: View>: View {
    let info: SightingCardInfo
    let text: String
    @ViewBuilder var label: () -> Label

    @State private var card: UIImage?

    var body: some View {
        Group {
            if let card {
                ShareLink(item: SpotCardShare(image: card, name: "\(info.identifier) · What The Flight"),
                          message: Text(text),
                          preview: SharePreview(info.identifier, image: Image(uiImage: card)), label: label)
            } else {
                ShareLink(item: text, label: label)
            }
        }
        .task(id: info.identifier) {
            card = await SightingCardRenderer.render(info)
        }
    }
}
#endif
