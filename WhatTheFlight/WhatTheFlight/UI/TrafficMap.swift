//
//  TrafficMap.swift
//  WhatTheFlight
//
//  The ambient map: every aircraft inside the radius on a muted MapKit map, with fading
//  trails, the radius ring, the airports traffic is using right now and the observer. The
//  Apple TV shows it full screen (`TVMapStack`); iPad shows it beside the radar (below it in
//  portrait) in its Split view, and iPhone and iPad swap it in for the radar from the bar's
//  Map button (`RadarScreen`).
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
    /// Pinned aircraft: drawn wherever they are, not just near the ring, with a yellow trail
    /// (`Palette.pinned`, the pin's colour on the hero) to tell them apart.
    var pinnedIDs: Set<String> = []
    /// `model.trail(for:)`.
    let trail: (String) -> [RadarModel.TrailPoint]
    /// Bump to rebuild trails and airport pins (`model.trailVersion`).
    let trailVersion: Int
    /// Compass direction for "up"; nil = north up. Asked of the camera: the aircraft turn by
    /// the heading the map actually has (`cameraHeading`), which stays behind once the user
    /// has moved an interactive map.
    var headingUp: Double? = nil
    var options = Options()
    var onTap: ((String) -> Void)? = nil

    struct Options {
        var scale: CGFloat = 1
        var interactive = false          // iPad: true
        var showsProjectedPath = true    // focused aircraft only
        var showsFringe = true
        /// Age bands, newest first; anything older isn't drawn.
        var trailBands = TrafficMapGeometry.trailBands
        var trailWidth: CGFloat = 1.5    // before `scale`; iPhone / iPad (the TV sets its own)
        var ringOpacity: Double = 1      // TV: fainter, so more of the map shows
        /// The paper wash over the standard map; imagery gets 0.2 less.
        var washOpacity: Double = 0.45
        var mapType: RadarSettings.MapType = .standard
        var placeName: String? = nil     // "You · Atlanta"
        var cardInset: CGSize = .zero    // TV, iPhone: keep the ring clear of the hero card
        /// Running under the status bar: its height, so the compass (and the ring) sit below
        /// the clock and battery rather than behind them.
        var topInset: CGFloat = 0
        /// Clouds and fog over the map (Settings → Radar → Clouds and fog); nil, none.
        var fog: WeatherFog? = nil
        /// On screen and awake: the clouds drift.
        var fogDrifts = true
        /// The fog is Apple Weather's: its mark goes in the corner, above the Maps logo.
        var fogAttribution = false
    }

    @State private var camera: MapCameraPosition = .automatic
    @State private var frame: TrafficMapGeometry.Frame?
    /// Camera distance in metres per mile of frame radius, learned from MapKit the first time
    /// it fits a region. A turned map can only be set with a camera, and a camera takes a
    /// distance rather than a span; the ratio holds for as long as the map keeps its size.
    @State private var metresPerMile: Double?
    @State private var awaitingFit = false
    /// The heading the map is drawn at, from MapKit as the camera moves. The glyphs turn by
    /// this rather than `headingUp`, so they stay with the map: a map the user has dragged
    /// doesn't follow the phone round, and while the camera turns they turn with it. Like the
    /// fog's placement, an object only the glyphs read, so a turning camera redraws them alone.
    @LazyState private var cameraHeading = MapCameraHeading()
    @State private var mapSize: CGSize = .zero
    @State private var visibleBounds: GeographicBounds?
    @State private var trails: [TrailSegment] = []
    @State private var airports: [Airport] = []
    /// Where the fog's square sits on screen, kept out of this view's body so a moving camera
    /// redraws only the fog.
    @LazyState private var fogPlacement = MapFogPlacement()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverOn
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.favoriteAircraft) private var favorites

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
        let isPinned: Bool
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

    /// The user has dragged or zoomed a map that would otherwise turn with them: it holds
    /// still, ignoring `headingUp`, until Recentre.
    private var isHeldByUser: Bool { options.interactive && headingUp != nil && camera.positionedByUser }

    /// Yellow reads less strongly than the blue on a pale map, so a pinned trail is wider.
    private func trailWidth(pinned: Bool) -> CGFloat {
        options.trailWidth * options.scale * (pinned ? 1.5 : 1)
    }

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
        MapReader { proxy in
            map(proxy)
        }
    }

    /// Keeps the fog's square on the ground as the camera moves.
    private func placeFog(_ proxy: MapProxy) {
        guard options.fog != nil else { return }
        fogPlacement.update(proxy: proxy, center: observer, halfMiles: WeatherFog.reachMiles(radius: radiusMiles), space: .local)
    }

    @ViewBuilder
    private func map(_ proxy: MapProxy) -> some View {
        let blips = blips
        let positionKey = PositionKey(blips)
        // Imagery is dark whatever the appearance (see `.environment` below).
        let ink = MapInk(isImagery ? .dark : colorScheme)
        // Zoomed out past 2,000 km there's nothing to see, and the wash would show its edge.
        Map(position: $camera, bounds: MapCameraBounds(maximumDistance: 2_000_000),
            interactionModes: options.interactive ? [.pan, .zoom] : []) {
            // `.muted` alone barely quietens the map (least of all in dark mode on tvOS): wash
            // the roads and labels back in paper so the aircraft carry the screen. Imagery gets
            // a lighter, dark wash (see `isImagery`). Everything drawn after it sits at the same
            // level, so stays on top.
            MapPolygon(coordinates: washCorners)
                .foregroundStyle(ink.paper(max(0, options.washOpacity - (isImagery ? 0.2 : 0))))
                .mapOverlayLevel(level: .aboveLabels)

            RadiusRings(observer: observer, radiusMiles: radiusMiles, scale: options.scale, echoes: true,
                        opacity: options.ringOpacity, ink: ink)
                .mapOverlayLevel(level: .aboveLabels)

            ForEach(trails) { segment in
                MapPolyline(coordinates: segment.coordinates)
                    .stroke(segment.isPinned ? ink.pinned(segment.opacity) : ink.route(segment.opacity),
                            style: StrokeStyle(lineWidth: trailWidth(pinned: segment.isPinned), lineCap: .round, lineJoin: .round))
                    .mapOverlayLevel(level: .aboveLabels)
            }
            // From the last reported position up to where the aircraft is now, as bright as the
            // newest stretch of trail.
            ForEach(blips) { blip in
                if let last = trail(blip.id).last {
                    let newest = options.trailBands.first?.opacity ?? 0.9
                    let opacity = blip.role == .fringe ? newest * 0.4 : newest
                    let isPinned = pinnedIDs.contains(blip.id)
                    MapPolyline(coordinates: [last.coordinate, blip.contact.coordinate])
                        .stroke(isPinned ? ink.pinned(opacity) : ink.route(opacity),
                                style: StrokeStyle(lineWidth: trailWidth(pinned: isPinned), lineCap: .round))
                        .mapOverlayLevel(level: .aboveLabels)
                }
            }

            if options.showsProjectedPath, let focused {
                ProjectedPath(contact: focused, scale: options.scale, ink: ink)
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
                Annotation(blip.contact.flight.displayIdentifier, coordinate: blip.contact.coordinate, anchor: .center) {
                    blipView(blip)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(mapStyle)
        // Over the base map and the aircraft, under the recentre button.
        .overlay(alignment: .topLeading) {
            if let fog = options.fog {
                MapFogOverlay(fog: fog, center: observer, radiusMiles: radiusMiles, placement: fogPlacement,
                              look: .map(colorScheme, imagery: isImagery), isActive: options.fogDrifts)
            }
        }
        // Glyphs move to each once-a-second position instead of hopping (MapKit plays the move
        // in about a quarter of a second, whatever the length asked for). Animated as part of
        // the tick's own update: setting positions from `onChange` cost the map a second full
        // update every second.
        .animation(reduceMotion ? nil : .linear(duration: 1), value: positionKey)
        // Imagery is dark whatever the appearance: draw labels and the wash for night.
        .environment(\.colorScheme, isImagery ? .dark : colorScheme)
        .safeAreaPadding(.top, options.topInset)
        .safeAreaPadding(.trailing, options.cardInset.width)
        .safeAreaPadding(.bottom, options.cardInset.height)
        .overlay(alignment: .bottomLeading) {
            if options.fogAttribution || (options.fog != nil && WeatherAttributionView.showsStandIn) {
                // MapKit keeps its logo inside the map's safe area, the card's inset included
                // (counted from the screen's edge, like the recentre button's): stand just above it.
                GeometryReader { geo in
                    WeatherAttributionView(compact: true, markHeight: 11 * options.scale)
                        .padding(.leading, geo.safeAreaInsets.leading + 10 * options.scale)
                        .padding(.bottom, max(options.cardInset.height, geo.safeAreaInsets.bottom) + 34 * options.scale)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .environment(\.colorScheme, isImagery ? .dark : colorScheme)
                }
                .ignoresSafeArea()
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            // A different size fits a different distance: learn it again.
            if size != mapSize { metresPerMile = nil }
            mapSize = size
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleBounds = GeographicBounds(region: context.region)
            rebuildAirports()
            learnFit(from: context.camera)
            placeFog(proxy)
            cameraHeading.note(context.camera.heading, tolerance: 0)
        }
        .onMapCameraChange(frequency: .continuous) { context in
            placeFog(proxy)
            cameraHeading.note(context.camera.heading, tolerance: 0.25)
        }
        .onChange(of: FogPlaceKey(on: options.fog != nil, radiusMiles: radiusMiles, latitude: observer.latitude,
                                  longitude: observer.longitude, size: mapSize)) { _, _ in placeFog(proxy) }
        .onChange(of: PlaceKey(observer: observer, radiusMiles: radiusMiles, northUp: headingUp == nil,
                               pinnedOutside: pinnedOutside?.id), initial: true) { old, new in
            reframe(animated: old != new)
        }
        .onChange(of: headingUp) { _, _ in
            // Following a turning iPad: leave a map the user has moved alone.
            guard !(options.interactive && camera.positionedByUser) else { return }
            reframe(animated: true)
        }
        .onChange(of: positionKey) { _, _ in keepPinnedAircraftInView() }
        // A set: the order changes whenever two aircraft swap places by distance, and a
        // rebuild replaces every trail on the map.
        .onChange(of: TrailKey(version: trailVersion, ids: Set(blips.map(\.id)), pinnedIDs: pinnedIDs), initial: true) { _, _ in
            rebuildTrails()
        }
        .overlay(alignment: .bottomTrailing) {
            if options.interactive {
                RecenterButton(isHeld: isHeldByUser) { reframe(animated: true) }
                    .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: isHeldByUser)
                    .padding(16)
                // iPhone's map: above the hero card and the bar.
                .padding(.trailing, options.cardInset.width)
                .padding(.bottom, options.cardInset.height)
            }
        }
        .disabled(!options.interactive)
        #if os(tvOS)
        // The remote must never land on the map, or swipes stop reaching the hero.
        .focusable(false)
        #endif
        .accessibilityHidden(!options.interactive)
    }

    @ViewBuilder
    private func blipView(_ blip: Blip) -> some View {
        let flight = blip.contact.flight
        let isFocused = blip.role == .focused
        let isAnnounced = blip.id == announcedID
        // Glyph only: the radar or the hero card beside the map already names the focus.
        MapBlip(profile: blip.contact.profile, track: flight.track, heading: cameraHeading, isFocused: isFocused,
                isAnnounced: isAnnounced, isFavorite: favorites.contains(flight), scale: options.scale)
            .opacity(blip.role == .fringe ? 0.4 : 1)
            .onTapGesture { onTap?(blip.id) }
            .accessibilityElement()
            // Distance and altitude change every tick, and a changed label re-renders every
            // glyph on the map: spell them out only for VoiceOver. The flight is name enough
            // for Voice Control.
            .accessibilityLabel(voiceOverOn ? SpokenTraffic.mapLabel(for: blip.contact) : flight.displayIdentifier)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Shows this aircraft in the center of the radar")
    }

    // MARK: Trails and airports

    /// Runs once per feed (and when the set of aircraft changes), not on every tick.
    private func rebuildTrails() {
        let now = Date()
        let all = blips.flatMap { blip in
            let fade = blip.role == .fringe ? 0.4 : 1
            let isPinned = pinnedIDs.contains(blip.id)
            return TrafficMapGeometry.segments(trail(blip.id), now: now, bands: options.trailBands).enumerated().map { index, segment in
                TrailSegment(id: "\(blip.id)-\(index)", coordinates: segment.coordinates, opacity: segment.opacity * fade,
                             isPinned: isPinned)
            }
        }
        // Pinned trails last, so other traffic never crosses over the yellow.
        trails = all.filter { !$0.isPinned } + all.filter(\.isPinned)
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

    private struct FogPlaceKey: Equatable {
        let on: Bool
        let radiusMiles: Double
        let latitude: Double
        let longitude: Double
        let size: CGSize
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

    private struct TrailKey: Equatable {
        let version: Int
        let ids: Set<String>
        /// Pinning or unpinning recolours a trail straight away, not at the next feed.
        let pinnedIDs: Set<String>
    }
}

/// Fixed colours for what `TrafficMap` draws into the map: the wash, rings, trails (yellow
/// for pinned aircraft) and the projected path. MapKit turns an overlay's SwiftUI colour into a UIColor every time it
/// touches the overlay's renderer, and an adaptive colour (all of `Palette`) is then resolved
/// through SwiftUI on every touch, a large share of each update on a busy map. Resolved once
/// for the appearance, they're plain RGB.
struct MapInk {
    private let routeColor, inkColor, paperColor, signalColor, pinnedColor: UIColor

    init(_ scheme: ColorScheme) {
        let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
        func fixed(_ color: Color) -> UIColor { UIColor(color).resolvedColor(with: traits) }
        routeColor = fixed(Palette.route)
        inkColor = fixed(Palette.ink)
        paperColor = fixed(Palette.paper)
        signalColor = fixed(Palette.signal)
        pinnedColor = fixed(Palette.pinned)
    }

    func route(_ opacity: Double) -> Color { Color(uiColor: routeColor.withAlphaComponent(opacity)) }
    func ink(_ opacity: Double) -> Color { Color(uiColor: inkColor.withAlphaComponent(opacity)) }
    func paper(_ opacity: Double) -> Color { Color(uiColor: paperColor.withAlphaComponent(opacity)) }
    func signal(_ opacity: Double) -> Color { Color(uiColor: signalColor.withAlphaComponent(opacity)) }
    func pinned(_ opacity: Double) -> Color { Color(uiColor: pinnedColor.withAlphaComponent(opacity)) }
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
    /// Fixed colours from a map that redraws every second; nil uses `Palette`'s.
    var ink: MapInk? = nil

    var body: some MapContent {
        if echoes {
            ForEach([0.25, 0.5], id: \.self) { fraction in
                MapCircle(center: observer, radius: radiusMiles * fraction * GeoMath.kilometersPerMile * 1000)
                    .foregroundStyle(.clear)
                    .stroke(color(0.16 * opacity), style: StrokeStyle(lineWidth: scale, dash: [3 * scale, 5 * scale]))
            }
        }
        MapCircle(center: observer, radius: radiusMiles * GeoMath.kilometersPerMile * 1000)
            .foregroundStyle(color(0.06 * opacity))
            .stroke(color(0.35 * opacity), style: StrokeStyle(lineWidth: scale, dash: [4 * scale, 4 * scale]))
    }

    private func color(_ opacity: Double) -> Color {
        ink?.ink(opacity) ?? Palette.ink.opacity(opacity)
    }
}

/// Where the aircraft will be over the next ten minutes if it holds its track and speed.
struct ProjectedPath: MapContent {
    let contact: RadarContact
    var scale: CGFloat = 1
    /// Fixed colours from a map that redraws every second; nil uses `Palette`'s.
    var ink: MapInk? = nil

    var body: some MapContent {
        MapPolyline(coordinates: contact.projectedPath)
            .stroke(ink?.signal(0.8) ?? Palette.signal.opacity(0.8),
                    style: StrokeStyle(lineWidth: 2 * scale, lineCap: .round, dash: [6 * scale, 5 * scale]))
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
/// The round glass button that refits the map. Once the user has dragged a map that turns
/// with them it holds still, which can look stuck when the phone turns and the map doesn't:
/// the button then stretches leftward into a pill carrying "Tap to turn with you again" in
/// the pin's yellow. The caller animates `isHeld`.
private struct RecenterButton: View {
    var isHeld = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                if isHeld {
                    Text("Tap to turn with you again")
                        .font(.mono(11, .semibold))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(Palette.pinned)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.leading, 16)
                        .transition(.opacity)
                }
                Image(systemName: "location.fill")
                    .font(.system(size: 17, weight: .semibold))
                    // Yellow with the note, so the whole pill reads as one message.
                    .foregroundStyle(isHeld ? Palette.pinned : Palette.ink)
                    .frame(width: 44, height: 44)
            }
            // A capsule round 44 × 44 is the circle; held, it grows into the pill.
            .glassSurface(in: Capsule(), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Recenter map")
        .accessibilityHint(isHeld ? Text("Shows your whole radius again and turns the map with you")
                                  : Text("Shows your whole radius again"))
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
                   onTap: { model.focus(on: $0, pinning: false) })
            .task { model.start() }
    }
}
#endif

// MARK: - Camera heading

/// The heading MapKit is drawing the map at (`onMapCameraChange`), which the glyphs turn by
/// so they always lie along their track on the map. Only `MapBlip` reads it, so a turning
/// camera redraws the glyphs and not the map.
@Observable
final class MapCameraHeading {
    private(set) var degrees: Double = 0

    /// A pan or zoom leaves the heading alone, so this changes anything only while the camera
    /// is turning; `tolerance` 0 takes the settled value exactly.
    func note(_ heading: Double, tolerance: Double) {
        let turned = GeoMath.normalize(heading)
        guard turned != degrees, abs(GeoMath.shortestDelta(from: degrees, to: turned)) >= tolerance else { return }
        degrees = turned
    }
}

/// An aircraft on the map, turned to its track on the map as the camera has it. Its own view
/// so that reading the heading tracks this glyph alone.
private struct MapBlip: View {
    let profile: FlightProfile
    let track: Double
    let heading: MapCameraHeading
    let isFocused: Bool
    let isAnnounced: Bool
    let isFavorite: Bool
    let scale: CGFloat

    var body: some View {
        AircraftBlip(profile: profile, screenTrack: track - heading.degrees, isFocused: isFocused,
                     isAnnounced: isAnnounced, isFavorite: isFavorite, scale: scale)
    }
}
#endif
