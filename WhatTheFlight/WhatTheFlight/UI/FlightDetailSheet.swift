//
//  FlightDetailSheet.swift
//  WhatTheFlight
//
//  Everything about one aircraft: photo, live map with projected track, full telemetry,
//  and shortcuts out to Flightradar24.
//

#if os(iOS) || os(tvOS)
import SwiftUI
import MapKit

#if os(iOS)
struct FlightDetailSheet: View {
    let flightID: String
    let model: RadarModel
    let settings: RadarSettings
    var logbook: Logbook?
    /// Opens Sky View pointing the way to this aircraft.
    var onFindInSky: ((String) -> Void)?

    @Environment(\.dismiss) private var dismiss
    /// Keeps the last known state so the sheet doesn't blank out if the aircraft drops off.
    @State private var lastContact: RadarContact?
    /// `-wtf.debugMapMode route` opens on the full route (screenshots).
    @State private var mapMode = DetailMap.Mode(rawValue: UserDefaults.standard.string(forKey: "wtf.debugMapMode") ?? "") ?? .nearby

    private var contact: RadarContact? { model.contact(id: flightID) ?? lastContact }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let contact {
                    VStack(spacing: 18) {
                        header(contact)
                        if settings.showPhotos {
                            PhotoCard(flight: contact.flight)
                        }
                        if let observer = model.observer {
                            VStack(spacing: 8) {
                                if DetailMap.canShowRoute(contact.flight) {
                                    Picker("Map", selection: $mapMode) {
                                        ForEach(DetailMap.Mode.allCases) { Text($0.title).tag($0) }
                                    }
                                    .pickerStyle(.segmented)
                                }
                                DetailMap(contact: contact, observer: observer, radiusMiles: settings.radiusMiles,
                                          trail: model.trail(for: contact.id).map(\.coordinate), mode: mapMode,
                                          height: mapMode == .route ? 300 : 230)
                            }
                        }
                        telemetry(contact)
                        routeCard(contact)
                        actions(contact)
                        Text("Live data: Flightradar24 (unofficial feed). Positions between updates are estimated.")
                            .font(.mono(10))
                            .foregroundStyle(Palette.faint)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 30)
                } else {
                    ContentUnavailableView("Aircraft out of range", systemImage: "airplane.departure", description: Text("This aircraft is no longer being tracked."))
                        .padding(.top, 80)
                }
            }
            .background(Palette.paper.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.mono(15, .semibold))
                }
            }
        }
        .onChange(of: model.contact(id: flightID), initial: true) { _, new in
            if let new { lastContact = new }
        }
    }

    // MARK: Sections

    private func header(_ contact: RadarContact) -> some View {
        let flight = contact.flight
        let info = flight.operatorInfo
        return VStack(spacing: 4) {
            NotableBadgeRow(flight: flight)
                .padding(.bottom, 4)
            Text(info.title)
                .radarCaption()
            if let subtitle = info.subtitle {
                Text(subtitle)
                    .font(.mono(11))
                    .foregroundStyle(Palette.faint)
            }
            Text(flight.displayIdentifier)
                .font(.mono(44, .heavy))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if flight.hasRoute {
                RouteLine(flight: flight)
            }
            if let name = flight.typeName ?? flight.typeCode {
                Text(name)
                    .font(.mono(13, .medium))
                    .foregroundStyle(Palette.caption)
                    .padding(.top, 4)
            }
            if let logbook, let airframe = flight.registration ?? flight.hex {
                seenCounter(airframe: airframe, logbook: logbook)
                    .padding(.top, 6)
            }
        }
        .padding(.top, 8)
    }

    /// "Logbook  4": every time you've seen this airframe; tap for the full log.
    @ViewBuilder
    private func seenCounter(airframe: String, logbook: Logbook) -> some View {
        let count = logbook.summary(airframe: airframe).count
        if count > 0 {
            NavigationLink {
                AirframeHistoryView(airframe: airframe, logbook: logbook, onTrack: { id in
                    model.focus(on: id)
                    dismiss()
                }, isLive: { model.contact(id: $0) != nil })
            } label: {
                LogbookCountLabel(count: count)
            }
            .buttonStyle(.plain)
        } else {
            LogbookCountLabel(count: 0)
        }
    }

    private func telemetry(_ contact: RadarContact) -> some View {
        let f = contact.flight
        let vs: String = f.verticalRateFPM == 0 ? "Level" : "\(f.verticalRateFPM > 0 ? "+" : "")\(RadarFormat.wholeNumber(f.verticalRateFPM)) fpm"
        let cpa = contact.isApproaching
            ? "\(RadarFormat.miles(contact.closestApproach.distanceMiles)) mi in \(RadarFormat.countdown(contact.closestApproach.secondsFromNow))"
            : "Moving away"
        let rows: [(String, String)] = [
            ("Altitude", "\(RadarFormat.wholeNumber(f.altitudeFeet)) ft"),
            ("Vertical", vs),
            ("Speed", "\(RadarFormat.wholeNumber(f.groundSpeedKnots)) kts"),
            ("Track", "\(Int(f.track.rounded()))° \(GeoMath.cardinal(f.track))"),
            ("Distance", "\(RadarFormat.miles(contact.distanceMiles)) mi"),
            ("Bearing", "\(Int(contact.bearing.rounded()))° \(GeoMath.cardinal(contact.bearing))"),
            ("Closest pass", cpa),
            ("Squawk", f.squawk ?? "—"),
            ("Registration", f.registration ?? "—"),
            ("Callsign", f.callsign ?? "—"),
            ("Type", f.typeCode ?? "—"),
            ("ICAO hex", f.hex ?? "—"),
        ]
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(rows, id: \.0) { row in
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.0).radarCaption()
                    Text(row.1)
                        .font(.mono(15, .semibold))
                        .foregroundStyle(Palette.value)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Palette.paperShade.opacity(0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityElement(children: .combine)
            }
        }
        .animation(.smooth, value: contact.distanceMiles.rounded())
    }

    @ViewBuilder
    private func routeCard(_ contact: RadarContact) -> some View {
        let f = contact.flight
        if f.hasRoute {
            VStack(alignment: .leading, spacing: 12) {
                Text("Route").radarCaption()
                airportRow(label: "From", code: f.originIATA, airport: f.origin)
                airportRow(label: "To", code: f.destinationIATA, airport: f.destination)
                if let progress = RouteProgress(flight: f, position: contact.coordinate) {
                    RouteProgressView(progress: progress)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Palette.paperShade.opacity(0.35), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func airportRow(label: String, code: String?, airport: Airport?) -> some View {
        HStack(spacing: 12) {
            Text(code ?? "—")
                .font(.mono(20, .bold))
                .foregroundStyle(Palette.route)
                .frame(width: 58, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(airport?.name ?? "Unknown airport")
                    .font(.mono(13, .semibold))
                    .foregroundStyle(Palette.value)
                Text(airport?.city ?? label)
                    .font(.mono(11))
                    .foregroundStyle(Palette.caption)
            }
        }
    }

    private func actions(_ contact: RadarContact) -> some View {
        let isFocused = model.focus.focusedID == contact.id
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    if isFocused {
                        model.togglePin()
                    } else {
                        model.focus(on: contact.id)
                        dismiss()
                    }
                } label: {
                    Label(isFocused ? (model.focus.isPinned ? "Unpin" : "Pin") : "Track on Radar",
                          systemImage: isFocused ? (model.focus.isPinned ? "lock.open" : "lock") : "scope")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(RadarButtonStyle(prominent: true))

                ShareLink(item: shareText(contact)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(RadarButtonStyle(prominent: false))
            }
            if !model.contacts.contains(where: { $0.id == contact.id }), contact.flight.canLocate {
                // Out of the radius (or off the feed's query box): look for it anywhere.
                NavigationLink {
                    WhereaboutsView(title: contact.flight.displayIdentifier, registration: contact.flight.registration,
                                    callsign: contact.flight.callsign, seenFlightID: contact.id, observer: model.observer)
                } label: {
                    Label("Where Is It Now?", systemImage: "location.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(RadarButtonStyle(prominent: true))
            }
            if let onFindInSky {
                Button {
                    onFindInSky(contact.id)
                } label: {
                    Label("Find in the Sky", systemImage: "camera.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(RadarButtonStyle(prominent: false))
            }
            if let url = flightradarURL(contact.flight) {
                Link(destination: url) {
                    Label("Open in Flightradar24", systemImage: "safari")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(RadarButtonStyle(prominent: false))
            }
        }
    }

    private func shareText(_ contact: RadarContact) -> String {
        let f = contact.flight
        var text = "✈️ \(f.displayIdentifier)"
        if f.hasRoute { text += " \(f.originIATA ?? "") → \(f.destinationIATA ?? "")" }
        if let type = f.typeName ?? f.typeCode { text += " · \(type)" }
        text += " — \(RadarFormat.wholeNumber(f.altitudeFeet)) ft, \(RadarFormat.miles(contact.distanceMiles)) mi away. Spotted with WhatTheFlight."
        return text
    }

    private func flightradarURL(_ flight: Flight) -> URL? {
        guard !flight.id.hasPrefix("demo") else { return nil }
        let slug = (flight.callsign ?? flight.flightNumber ?? flight.registration ?? "").lowercased()
        return URL(string: "https://www.flightradar24.com/\(slug.isEmpty ? "data" : slug)/\(flight.id)")
    }
}

#endif

struct RadarButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.mono(14, .bold))
            .padding(.vertical, 13)
            .padding(.horizontal, 12)
            .foregroundStyle(prominent ? Color.white : Palette.ink)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(prominent ? Palette.ink : Palette.ink.opacity(0.1))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - Photo

struct PhotoCard: View {
    let flight: Flight
    @State private var photo: AircraftPhoto?
    @State private var loaded = false

    var body: some View {
        Group {
            if let photo {
                VStack(alignment: .trailing, spacing: 6) {
                    AsyncImage(url: photo.imageURL, transaction: Transaction(animation: .smooth)) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            Rectangle().fill(Palette.paperShade.opacity(0.4))
                                .overlay(ProgressView())
                        }
                    }
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    if let pageURL = photo.pageURL {
                        Link(destination: pageURL) {
                            Text("Photo © \(photo.photographer ?? "Unknown") · Planespotters.net")
                                .font(.mono(10))
                                .foregroundStyle(Palette.caption)
                        }
                    }
                }
            } else if !loaded {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Palette.paperShade.opacity(0.3))
                    .frame(height: 200)
                    .overlay(ProgressView())
            }
        }
        .task(id: flight.registration ?? flight.hex) {
            photo = await AircraftPhotoProvider.shared.photo(registration: flight.registration, hex: flight.hex)
            withAnimation(.smooth) { loaded = true }
        }
    }
}

// MARK: - Map

struct DetailMap: View {
    enum Mode: String, CaseIterable, Identifiable {
        case nearby, route
        var id: String { rawValue }
        var title: String { self == .nearby ? "Nearby" : "Full Route" }
    }

    let contact: RadarContact
    let observer: CLLocationCoordinate2D
    let radiusMiles: Double
    /// Where the feed has seen this aircraft while we watched (oldest first).
    var trail: [CLLocationCoordinate2D] = []
    var mode: Mode = .nearby
    var height: CGFloat = 230
    var interactive = true

    @State private var camera: MapCameraPosition = .automatic

    private var flight: Flight { contact.flight }
    private var originCoordinate: CLLocationCoordinate2D? { flight.origin?.coordinate }
    private var destinationCoordinate: CLLocationCoordinate2D? { flight.destination?.coordinate }

    /// The route can be drawn once both airports have a position.
    static func canShowRoute(_ flight: Flight) -> Bool {
        flight.origin?.coordinate != nil && flight.destination?.coordinate != nil
    }

    private var showsRoute: Bool { mode == .route && Self.canShowRoute(flight) }

    private var projectedPath: [CLLocationCoordinate2D] {
        let start = contact.coordinate
        let speed = Double(flight.groundSpeedKnots)
        return stride(from: 0.0, through: 600, by: 60).map {
            GeoMath.extrapolate(start, trackDegrees: flight.track, speedKnots: speed, seconds: $0)
        }
    }

    var body: some View {
        Map(position: $camera, interactionModes: interactive ? [.pan, .zoom] : []) {
            MapCircle(center: observer, radius: radiusMiles * 1609.344)
                .foregroundStyle(Palette.ink.opacity(0.06))
                .stroke(Palette.ink.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

            if showsRoute, let from = originCoordinate, let to = destinationCoordinate {
                // Flown: from the origin, through every position we saw, to where it is now.
                MapPolyline(coordinates: [from] + trail + [contact.coordinate], contourStyle: .geodesic)
                    .stroke(Palette.route, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                // Still to fly.
                MapPolyline(coordinates: [contact.coordinate, to], contourStyle: .geodesic)
                    .stroke(Palette.signal.opacity(0.85), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [7, 6]))

                Annotation(flight.origin?.name ?? "", coordinate: from, anchor: .bottom) {
                    AirportPin(code: flight.originIATA ?? "", filled: true)
                }
                Annotation(flight.destination?.name ?? "", coordinate: to, anchor: .bottom) {
                    AirportPin(code: flight.destinationIATA ?? "", filled: false)
                }
            } else {
                if trail.count >= 2 {
                    MapPolyline(coordinates: trail + [contact.coordinate])
                        .stroke(Palette.route.opacity(0.9), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }
                MapPolyline(coordinates: projectedPath)
                    .stroke(Palette.signal.opacity(0.8), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 5]))
            }

            Annotation("You", coordinate: observer, anchor: .center) {
                Circle()
                    .fill(Palette.ink)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .shadow(radius: 2)
            }

            Annotation(flight.displayIdentifier, coordinate: contact.coordinate, anchor: .center) {
                Group {
                    if flight.kind == .helicopter {
                        Image("helicopter-bottom-view").resizable().renderingMode(.template).scaledToFit()
                            .frame(width: 26, height: 26)
                            .rotationEffect(.degrees(flight.track))
                    } else {
                        Image(systemName: "airplane")
                            .font(.system(size: 24, weight: .semibold))
                            .rotationEffect(.degrees(flight.track - 90))
                    }
                }
                .foregroundStyle(Palette.signal)
                .shadow(color: .black.opacity(0.3), radius: 2)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .frame(height: height)
        .disabled(!interactive)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onAppear { frame() }
        .onChange(of: contact.id) { _, _ in frame() }
        .onChange(of: mode) { _, _ in withAnimation(.smooth) { frame() } }
    }

    private func frame() {
        if showsRoute, let from = originCoordinate, let to = destinationCoordinate {
            camera = .region(Self.region(fitting: [from, to, contact.coordinate], padding: 1.35, minimumSpan: 0.5))
        } else {
            camera = .region(Self.region(fitting: [observer, contact.coordinate] + projectedPath.suffix(1), padding: 1.6, minimumSpan: 0.05))
        }
    }

    /// A region around the points. Longitudes are unwrapped so a trans-Pacific route frames
    /// the short way across the date line.
    static func region(fitting points: [CLLocationCoordinate2D], padding: Double, minimumSpan: Double) -> MKCoordinateRegion {
        guard let first = points.first else { return MKCoordinateRegion() }
        let lats = points.map(\.latitude)
        let lons = points.map { p -> Double in
            var lon = p.longitude
            while lon - first.longitude > 180 { lon -= 360 }
            while lon - first.longitude < -180 { lon += 360 }
            return lon
        }
        let minLat = lats.min()!, maxLat = lats.max()!, minLon = lons.min()!, maxLon = lons.max()!
        var centerLon = (minLon + maxLon) / 2
        if centerLon > 180 { centerLon -= 360 } else if centerLon < -180 { centerLon += 360 }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: centerLon)
        let span = MKCoordinateSpan(latitudeDelta: min(170, max(minimumSpan, (maxLat - minLat) * padding)),
                                    longitudeDelta: min(355, max(minimumSpan, (maxLon - minLon) * padding)))
        return MKCoordinateRegion(center: center, span: span)
    }
}

/// An airport marker: the IATA code in a tag over a dot (filled = origin, ring = destination).
struct AirportPin: View {
    let code: String
    let filled: Bool

    var body: some View {
        VStack(spacing: 3) {
            Text(code)
                .font(.mono(12, .heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Palette.route, in: Capsule())
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            Circle()
                .fill(filled ? Palette.route : Color.white)
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(Palette.route, lineWidth: 2.5))
        }
    }
}

/// "1,204 mi flown · 386 mi to go · ~52m" with a progress bar.
struct RouteProgressView: View {
    let progress: RouteProgress
    var scale: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 8 * scale) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.ink.opacity(0.12))
                    Capsule().fill(Palette.route)
                        .frame(width: max(6 * scale, geo.size.width * progress.fraction))
                    Image(systemName: "airplane")
                        .font(.system(size: 13 * scale, weight: .bold))
                        .foregroundStyle(Palette.signal)
                        .offset(x: max(0, geo.size.width * progress.fraction - 8 * scale))
                }
            }
            .frame(height: 6 * scale)
            .padding(.vertical, 4 * scale)
            HStack {
                Text("\(RadarFormat.wholeNumber(Int(progress.flownMiles.rounded()))) mi flown")
                Spacer()
                Text(remainingText)
            }
            .font(.mono(11 * scale, .semibold))
            .foregroundStyle(Palette.caption)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int(progress.fraction * 100)) percent of the way. \(remainingText).")
    }

    private var remainingText: String {
        let miles = "\(RadarFormat.wholeNumber(Int(progress.remainingMiles.rounded()))) mi to go"
        guard let seconds = progress.remainingSeconds else { return miles }
        return "\(miles) · ~\(RouteProgress.duration(seconds))"
    }
}
#endif
