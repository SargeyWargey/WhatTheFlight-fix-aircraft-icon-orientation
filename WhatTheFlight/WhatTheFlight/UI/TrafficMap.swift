//
//  TrafficMap.swift
//  WhatTheFlight
//
//  The ambient map: every aircraft inside the radius on a muted MapKit map, with fading
//  trails, the radius ring, the airports traffic is using right now and the observer. The
//  Apple TV shows it full screen (`TVMapStack`); iPad shows it beside the radar in landscape.
//  The pieces it shares with the flight detail map (ring, observer dot, projected path,
//  airport pin) live here too.
//
//  The camera fits the ring once and stays still: it only moves when the radius, the place
//  or "up" changes, or to keep a pinned aircraft in view after it leaves the radius.
//

#if os(iOS) || os(tvOS)
import SwiftUI
import MapKit

struct TrafficMap: View {
    let observer: CLLocationCoordinate2D
    let radiusMiles: Double
    /// In range, nearest first (`model.contacts`).
    let contacts: [RadarContact]
    /// Just outside, drawn faded (`model.outsideContacts` filtered by the caller).
    var fringe: [RadarContact] = []
    /// The aircraft owning the centre (`model.focusedContact`). Drawn wherever it is.
    let focused: RadarContact?
    var isPinned = false
    /// The aircraft a spoken alert is reading out (Apple TV), pulsed in purple.
    var announcedID: String? = nil
    /// Pinned aircraft: drawn with a pin wherever they are, not just near the ring.
    var pinnedIDs: Set<String> = []
    /// `model.trail(for:)`.
    let trail: (String) -> [RadarModel.TrailPoint]
    /// Bump to rebuild trails and airport pins (`model.trailVersion`).
    let trailVersion: Int
    /// Compass direction for "up"; nil = north up.
    var headingUp: Double? = nil
    var options = Options()
    var onTap: ((String) -> Void)? = nil

    struct Options {
        var scale: CGFloat = 1
        var interactive = false          // iPad: true
        var showsLabels = true
        var showsProjectedPath = true    // focused aircraft only
        var showsFringe = true
        /// Age bands, newest first; anything older isn't drawn.
        var trailBands = TrafficMapGeometry.trailBands
        var trailWidth: CGFloat = 3      // before `scale`
        var ringOpacity: Double = 1      // TV: fainter, so more of the map shows
        var mapType: RadarSettings.MapType = .standard
        var placeName: String? = nil     // "You · Atlanta"
        var cardInset: CGSize = .zero    // TV: keep the ring clear of the hero card
    }

    @State private var camera: MapCameraPosition = .automatic
    @State private var frame: TrafficMapGeometry.Frame?
    /// Camera distance in metres per mile of frame radius, learned from MapKit the first time
    /// it fits a region. A turned map can only be set with a camera, and a camera takes a
    /// distance rather than a span; the ratio holds for as long as the map keeps its size.
    @State private var metresPerMile: Double?
    @State private var awaitingFit = false
    @State private var mapSize: CGSize = .zero
    @State private var visibleBounds: GeographicBounds?
    /// Where each aircraft is drawn. Updated inside an animation so glyphs glide between the
    /// model's once-a-second positions instead of hopping.
    @State private var positions: [String: CLLocationCoordinate2D] = [:]
    @State private var trails: [TrailSegment] = []
    @State private var airports: [Airport] = []

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    // MARK: What's drawn

    private var isImagery: Bool { options.mapType != .standard }

    private var mapStyle: MapStyle {
        switch options.mapType {
        case .standard: return .standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false)
        case .satellite: return .imagery(elevation: .flat)
        case .hybrid: return .hybrid(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false)
        }
    }

    private enum Role { case inRange, fringe, focused }

    private struct Blip: Identifiable {
        let contact: RadarContact
        let role: Role
        var id: String { contact.id }
    }

    private struct TrailSegment: Identifiable {
        let id: String
        let coordinates: [CLLocationCoordinate2D]
        let opacity: Double
    }

    private var blips: [Blip] {
        let focusedID = focused?.id
        var result: [Blip] = []
        if options.showsFringe {
            result += fringe
                .filter { $0.id != focusedID && !pinnedIDs.contains($0.id) && $0.distanceMiles <= radiusMiles * 1.5 }
                .map { Blip(contact: $0, role: .fringe) }
        }
        result += fringe
            .filter { $0.id != focusedID && pinnedIDs.contains($0.id) }
            .map { Blip(contact: $0, role: .inRange) }
        result += contacts.filter { $0.id != focusedID }.map { Blip(contact: $0, role: .inRange) }
        // Last, so it draws on top. A pinned aircraft is drawn even far outside the radius.
        if let focused { result.append(Blip(contact: focused, role: .focused)) }
        return result
    }

    private var heading: Double { headingUp ?? 0 }

    /// A box well beyond anything the camera can show around what it's framing (home, or a
    /// far-away pinned aircraft it's following).
    private var washCorners: [CLLocationCoordinate2D] {
        let center = frame?.center ?? observer
        let lat = center.latitude, lon = center.longitude
        return [(30.0, -40.0), (30, 40), (-30, 40), (-30, -40)].map {
            CLLocationCoordinate2D(latitude: max(-85, min(85, lat + $0.0)), longitude: lon + $0.1)
        }
    }

    /// A pinned aircraft that has left the radius widens the frame.
    private var pinnedOutside: RadarContact? {
        guard isPinned, let focused, !contacts.contains(where: { $0.id == focused.id }) else { return nil }
        return focused
    }

    // MARK: Body

    var body: some View {
        let blips = blips
        // Zoomed out past 2,000 km there's nothing to see, and the wash would show its edge.
        Map(position: $camera, bounds: MapCameraBounds(maximumDistance: 2_000_000),
            interactionModes: options.interactive ? [.pan, .zoom] : []) {
            // `.muted` alone barely quietens the map (least of all in dark mode on tvOS): wash
            // the roads and labels back in paper so the aircraft carry the screen. Imagery gets
            // a lighter, dark wash (see `isImagery`). Everything drawn after it sits at the same
            // level, so stays on top.
            MapPolygon(coordinates: washCorners)
                .foregroundStyle(Palette.paper.opacity(isImagery ? 0.25 : 0.45))
                .mapOverlayLevel(level: .aboveLabels)

            RadiusRings(observer: observer, radiusMiles: radiusMiles, scale: options.scale, echoes: true,
                        opacity: options.ringOpacity)
                .mapOverlayLevel(level: .aboveLabels)

            ForEach(trails) { segment in
                MapPolyline(coordinates: segment.coordinates)
                    .stroke(Palette.route.opacity(segment.opacity),
                            style: StrokeStyle(lineWidth: options.trailWidth * options.scale, lineCap: .round, lineJoin: .round))
                    .mapOverlayLevel(level: .aboveLabels)
            }
            // From the last reported position up to where the aircraft is now, as bright as the
            // newest stretch of trail.
            ForEach(blips) { blip in
                if let last = trail(blip.id).last {
                    let newest = options.trailBands.first?.opacity ?? 0.9
                    MapPolyline(coordinates: [last.coordinate, coordinate(of: blip)])
                        .stroke(Palette.route.opacity(blip.role == .fringe ? newest * 0.4 : newest),
                                style: StrokeStyle(lineWidth: options.trailWidth * options.scale, lineCap: .round))
                        .mapOverlayLevel(level: .aboveLabels)
                }
            }

            if options.showsProjectedPath, let focused {
                ProjectedPath(contact: focused, scale: options.scale)
                    .mapOverlayLevel(level: .aboveLabels)
            }

            ForEach(airports, id: \.iata) { airport in
                if let coordinate = airport.coordinate {
                    Annotation(airport.name, coordinate: coordinate, anchor: .bottom) {
                        AirportPin(code: airport.iata, filled: false, scale: options.scale)
                    }
                    .annotationTitles(.hidden)
                }
            }

            Annotation("You", coordinate: observer, anchor: .center) {
                ObserverDot(scale: options.scale, label: options.placeName.map { "You · \($0)" })
            }
            .annotationTitles(.hidden)

            ForEach(blips) { blip in
                Annotation(blip.contact.flight.displayIdentifier, coordinate: coordinate(of: blip), anchor: .center) {
                    blipView(blip)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(mapStyle)
        // Imagery is dark whatever the appearance: draw labels and the wash for night.
        .environment(\.colorScheme, isImagery ? .dark : colorScheme)
        .safeAreaPadding(.trailing, options.cardInset.width)
        .safeAreaPadding(.bottom, options.cardInset.height)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            // A different size fits a different distance: learn it again.
            if size != mapSize { metresPerMile = nil }
            mapSize = size
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleBounds = GeographicBounds(region: context.region)
            rebuildAirports()
            learnFit(from: context.camera)
        }
        .onChange(of: PlaceKey(observer: observer, radiusMiles: radiusMiles, northUp: headingUp == nil,
                               pinnedOutside: pinnedOutside?.id), initial: true) { old, new in
            reframe(animated: old != new)
        }
        .onChange(of: headingUp) { _, _ in
            // Following a turning iPad: leave a map the user has moved alone.
            guard !(options.interactive && camera.positionedByUser) else { return }
            reframe(animated: true)
        }
        .onChange(of: PositionKey(blips), initial: true) { _, _ in
            let next = Dictionary(blips.map { ($0.id, $0.contact.coordinate) }, uniquingKeysWith: { a, _ in a })
            withAnimation(reduceMotion ? nil : .linear(duration: 1)) { positions = next }
            keepPinnedAircraftInView()
        }
        .onChange(of: trailVersion, initial: true) { _, _ in rebuildTrails() }
        .onChange(of: blips.map(\.id)) { _, _ in rebuildTrails() }
        .overlay(alignment: .bottomTrailing) {
            if options.interactive {
                RecenterButton { reframe(animated: true) }
                    .padding(16)
            }
        }
        .disabled(!options.interactive)
        #if os(tvOS)
        // The remote must never land on the map, or swipes stop reaching the hero.
        .focusable(false)
        #endif
        .accessibilityHidden(!options.interactive)
    }

    private func coordinate(of blip: Blip) -> CLLocationCoordinate2D {
        positions[blip.id] ?? blip.contact.coordinate
    }

    @ViewBuilder
    private func blipView(_ blip: Blip) -> some View {
        let flight = blip.contact.flight
        let isFocused = blip.role == .focused
        let isAnnounced = blip.id == announcedID
        AircraftBlip(flight: flight, screenTrack: flight.track - heading, isFocused: isFocused,
                     isAnnounced: isAnnounced, isPinned: pinnedIDs.contains(blip.id), scale: options.scale)
            .overlay(alignment: .bottom) {
                if options.showsLabels && blip.role != .fringe {
                    VStack(spacing: 0) {
                        Text(flight.displayIdentifier)
                            .font(.mono(13 * options.scale, .bold))
                            .foregroundStyle(isAnnounced ? Palette.announce : isFocused ? Palette.signal : Palette.value)
                        Text("\(RadarFormat.wholeNumber(flight.altitudeFeet)) ft")
                            .font(.mono(11 * options.scale))
                            .foregroundStyle(Palette.caption)
                    }
                    .paperHalo()
                    .fixedSize()
                    .alignmentGuide(.bottom) { $0[.top] }
                }
            }
            .opacity(blip.role == .fringe ? 0.4 : 1)
            .onTapGesture { onTap?(blip.id) }
            .accessibilityElement()
            .accessibilityLabel(SpokenTraffic.mapLabel(for: blip.contact))
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Shows this aircraft in the center of the radar")
    }

    // MARK: Trails and airports

    /// Runs once per feed (and when the set of aircraft changes), not on every tick.
    private func rebuildTrails() {
        let now = Date()
        trails = blips.flatMap { blip in
            let fade = blip.role == .fringe ? 0.4 : 1
            return TrafficMapGeometry.segments(trail(blip.id), now: now, bands: options.trailBands).enumerated().map { index, segment in
                TrailSegment(id: "\(blip.id)-\(index)", coordinates: segment.coordinates, opacity: segment.opacity * fade)
            }
        }
        rebuildAirports()
    }

    private func rebuildAirports() {
        guard let bounds = visibleBounds ?? frame?.bounds else { return }
        let found = TrafficMapGeometry.relevantAirports(for: blips.map(\.contact.flight), in: bounds)
        if found != airports { airports = found }
    }

    // MARK: Camera

    private func reframe(animated: Bool) {
        var target = TrafficMapGeometry.frame(observer: observer, radiusMiles: radiusMiles, padding: 1.08)
        if let pinned = pinnedOutside {
            // Room for where it'll be in five minutes, so the frame doesn't widen every tick.
            let ahead = GeoMath.extrapolate(pinned.coordinate, trackDegrees: pinned.flight.track,
                                            speedKnots: Double(pinned.flight.groundSpeedKnots), seconds: 300)
            if TrafficMapGeometry.followsPinnedAlone(observer: observer, aircraft: pinned.coordinate, radiusMiles: radiusMiles) {
                target = TrafficMapGeometry.frame(observer: pinned.coordinate, radiusMiles: max(radiusMiles, 40), extra: [ahead], padding: 1.08)
            } else {
                target = TrafficMapGeometry.frame(observer: observer, radiusMiles: radiusMiles, extra: [pinned.coordinate, ahead], padding: 1.08)
            }
        }
        frame = target
        let position: MapCameraPosition
        if heading != 0, let metresPerMile {
            position = .camera(MapCamera(centerCoordinate: target.center, distance: target.radiusMiles * metresPerMile,
                                         heading: heading, pitch: 0))
        } else {
            // North up, or the first fit: MapKit sizes a region itself (and `learnFit` turns it).
            awaitingFit = true
            position = .region(target.region)
        }
        withAnimation(animated && !reduceMotion ? .smooth(duration: 1.5) : nil) { camera = position }
    }

    /// After a region fit, note the distance MapKit chose; then turn the map if it should be.
    private func learnFit(from mapCamera: MapCamera) {
        guard awaitingFit, let frame, frame.radiusMiles > 0 else { return }
        awaitingFit = false
        if abs(mapCamera.heading) < 0.5 || abs(mapCamera.heading - 360) < 0.5 {
            metresPerMile = mapCamera.distance / frame.radiusMiles
        }
        if heading != 0, let metresPerMile {
            camera = .camera(MapCamera(centerCoordinate: frame.center, distance: frame.radiusMiles * metresPerMile,
                                       heading: heading, pitch: 0))
        }
    }

    /// A pinned aircraft that is about to leave the frame gets a wider one.
    private func keepPinnedAircraftInView() {
        guard let pinned = pinnedOutside, let frame, !(options.interactive && camera.positionedByUser) else { return }
        if !frame.encloses(pinned.coordinate, margin: 0.92) { reframe(animated: true) }
    }

    private struct PlaceKey: Equatable {
        let latitude: Double
        let longitude: Double
        let radiusMiles: Double
        let northUp: Bool
        let pinnedOutside: String?

        init(observer: CLLocationCoordinate2D, radiusMiles: Double, northUp: Bool, pinnedOutside: String?) {
            latitude = observer.latitude
            longitude = observer.longitude
            self.radiusMiles = radiusMiles
            self.northUp = northUp
            self.pinnedOutside = pinnedOutside
        }
    }

    private struct PositionKey: Equatable {
        let values: [Double]
        init(_ blips: [Blip]) {
            values = blips.flatMap { [$0.contact.coordinate.latitude, $0.contact.coordinate.longitude] }
        }
    }
}

// MARK: - Shared map pieces

/// The dashed radius ring, optionally with fainter rings at half and a quarter of the radius
/// (echoing the radar face's range rings).
struct RadiusRings: MapContent {
    let observer: CLLocationCoordinate2D
    let radiusMiles: Double
    var scale: CGFloat = 1
    var echoes = false
    /// Scales the fill and strokes: below 1, more of the map shows through.
    var opacity: Double = 1

    var body: some MapContent {
        if echoes {
            ForEach([0.25, 0.5], id: \.self) { fraction in
                MapCircle(center: observer, radius: radiusMiles * fraction * GeoMath.kilometersPerMile * 1000)
                    .foregroundStyle(.clear)
                    .stroke(Palette.ink.opacity(0.16 * opacity), style: StrokeStyle(lineWidth: scale, dash: [3 * scale, 5 * scale]))
            }
        }
        MapCircle(center: observer, radius: radiusMiles * GeoMath.kilometersPerMile * 1000)
            .foregroundStyle(Palette.ink.opacity(0.06 * opacity))
            .stroke(Palette.ink.opacity(0.35 * opacity), style: StrokeStyle(lineWidth: scale, dash: [4 * scale, 4 * scale]))
    }
}

/// Where the aircraft will be over the next ten minutes if it holds its track and speed.
struct ProjectedPath: MapContent {
    let contact: RadarContact
    var scale: CGFloat = 1

    var body: some MapContent {
        MapPolyline(coordinates: contact.projectedPath)
            .stroke(Palette.signal.opacity(0.8), style: StrokeStyle(lineWidth: 2 * scale, lineCap: .round, dash: [6 * scale, 5 * scale]))
    }
}

extension RadarContact {
    /// A point a minute for the next ten minutes along the current track.
    var projectedPath: [CLLocationCoordinate2D] {
        let speed = Double(flight.groundSpeedKnots)
        return stride(from: 0.0, through: 600, by: 60).map {
            GeoMath.extrapolate(coordinate, trackDegrees: flight.track, speedKnots: speed, seconds: $0)
        }
    }
}

/// "You": a dot in the radar's ink, with an optional caption underneath.
struct ObserverDot: View {
    var scale: CGFloat = 1
    var label: String? = nil

    var body: some View {
        Circle()
            .fill(Palette.ink)
            .frame(width: 12 * scale, height: 12 * scale)
            .overlay(Circle().stroke(.white, lineWidth: 2 * scale))
            .shadow(radius: 2 * scale)
            .overlay(alignment: .bottom) {
                if let label {
                    Text(label)
                        .font(.mono(12 * scale, .bold))
                        .foregroundStyle(Palette.ink)
                        .paperHalo()
                        .fixedSize()
                        .padding(.top, 4 * scale)
                        .alignmentGuide(.bottom) { $0[.top] }
                }
            }
    }
}

/// An airport marker: the IATA code in a tag over a dot (filled = origin, ring = destination).
struct AirportPin: View {
    let code: String
    let filled: Bool
    var scale: CGFloat = 1

    var body: some View {
        VStack(spacing: 3 * scale) {
            Text(code)
                .font(.mono(12 * scale, .heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 7 * scale)
                .padding(.vertical, 3 * scale)
                .background(Palette.route, in: Capsule())
                .shadow(color: .black.opacity(0.25), radius: 2 * scale, y: scale)
            Circle()
                .fill(filled ? Palette.route : Color.white)
                .frame(width: 10 * scale, height: 10 * scale)
                .overlay(Circle().stroke(Palette.route, lineWidth: 2.5 * scale))
        }
    }
}

/// Back to the fitted frame after panning around (iPad).
private struct RecenterButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "location.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 44, height: 44)
                .glassSurface(in: Circle(), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Recenter map")
        .accessibilityHint("Shows your whole radius again")
    }
}

extension TrafficMapGeometry.Frame {
    var region: MKCoordinateRegion {
        MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta))
    }
}

extension GeographicBounds {
    init(region: MKCoordinateRegion) {
        self.init(northLatitude: region.center.latitude + region.span.latitudeDelta / 2,
                  southLatitude: region.center.latitude - region.span.latitudeDelta / 2,
                  eastLongitude: region.center.longitude + region.span.longitudeDelta / 2,
                  westLongitude: region.center.longitude - region.span.longitudeDelta / 2)
    }
}

#if DEBUG
#Preview("Traffic map") {
    @Previewable @State var model: RadarModel = {
        let model = RadarModel(settings: RadarSettings(defaults: UserDefaults(suiteName: "TrafficMapPreview")!))
        model.settings.demoTraffic = true
        model.setObserver(CLLocationCoordinate2D(latitude: 33.749, longitude: -84.388))
        return model
    }()
    if let observer = model.observer {
        TrafficMap(observer: observer, radiusMiles: model.settings.radiusMiles, contacts: model.contacts,
                   fringe: model.outsideContacts, focused: model.focusedContact, isPinned: model.focus.isPinned,
                   trail: model.trail(for:), trailVersion: model.trailVersion,
                   options: .init(interactive: true, placeName: "Atlanta"),
                   onTap: { model.focus(on: $0) })
            .task { model.start() }
    }
}
#endif
#endif
