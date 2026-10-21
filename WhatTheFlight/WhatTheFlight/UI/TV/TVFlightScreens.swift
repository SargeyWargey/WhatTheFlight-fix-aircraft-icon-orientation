//
//  TVFlightScreens.swift
//  WhatTheFlight
//
//  Apple TV flight detail and the full aircraft list.
//

#if os(tvOS)
import SwiftUI

struct TVFlightDetailView: View {
    let flightID: String
    let model: RadarModel
    let settings: RadarSettings
    var logbook: Logbook?
    let onClose: () -> Void

    @State private var lastContact: RadarContact?
    @State private var photo: AircraftPhoto?
    @State private var showsLog = false
    @State private var showWhereabouts = false
    /// `-wtf.debugMapMode route` opens on the full route (screenshots).
    @State private var mapMode = DetailMap.Mode(rawValue: UserDefaults.standard.string(forKey: "wtf.debugMapMode") ?? "") ?? .nearby

    private var contact: RadarContact? { model.contact(id: flightID) ?? lastContact }

    var body: some View {
        ZStack {
            RadarBackdrop(showTopography: settings.showTopography, showSweep: false, isActive: true)
                .ignoresSafeArea()
            if let contact {
                content(contact)
            } else {
                Text("This aircraft is no longer being tracked.")
                    .font(.mono(30))
                    .foregroundStyle(Palette.caption)
            }
        }
        .preferredColorScheme(settings.appearance.colorScheme)
        .onChange(of: model.contact(id: flightID), initial: true) { _, new in
            if let new { lastContact = new }
        }
        .task(id: flightID) {
            guard settings.showPhotos, let flight = contact?.flight else { return }
            photo = await AircraftPhotoProvider.shared.photo(registration: flight.registration, hex: flight.hex)
        }
        .fullScreenCover(isPresented: $showsLog) {
            if let logbook, let airframe = contact?.flight.registration ?? contact?.flight.hex {
                TVAirframeHistoryView(airframe: airframe, logbook: logbook, showTopography: settings.showTopography,
                                      showPhotos: settings.showPhotos, isLive: { model.contact(id: $0) != nil }) { id in
                    showsLog = false
                    model.focus(on: id)
                    onClose()
                }
                .environment(\.radarObserver, model.observer)
                .preferredColorScheme(settings.appearance.colorScheme)
            }
        }
        .fullScreenCover(isPresented: $showWhereabouts) {
            if let f = contact?.flight {
                TVWhereaboutsView(title: f.displayIdentifier, registration: f.registration, callsign: f.callsign,
                                  seenFlightID: f.id, observer: model.observer, showTopography: settings.showTopography)
                    .preferredColorScheme(settings.appearance.colorScheme)
            }
        }
    }

    /// Two columns (who and what on the left, live numbers and map on the right) with every
    /// action in one full-width row along the bottom, so no button label gets squeezed.
    private func content(_ contact: RadarContact) -> some View {
        VStack(alignment: .leading, spacing: 36) {
            HStack(alignment: .top, spacing: 70) {
                identity(contact)
                    .frame(width: 700, alignment: .leading)
                VStack(alignment: .leading, spacing: 26) {
                    stats(contact)
                    if let observer = model.observer {
                        DetailMap(contact: contact, observer: observer, radiusMiles: settings.radiusMiles,
                                  trail: model.trail(for: contact.id).map(\.coordinate), mode: mapMode,
                                  height: 300, interactive: false)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            actions(contact)
        }
        .padding(.horizontal, 90)
        .padding(.top, 50)
        .padding(.bottom, 40)
    }

    private func identity(_ contact: RadarContact) -> some View {
        let f = contact.flight
        return VStack(alignment: .leading, spacing: 16) {
            Text(f.operatorInfo.headline)
                .radarCaptionTV()
            if let subtitle = f.operatorInfo.subtitle, f.operatorInfo.kind == .airline {
                Text(subtitle)
                    .font(.mono(20))
                    .foregroundStyle(Palette.caption)
            }
            NotableBadgeRow(flight: f, scale: 1.8)
            HStack(spacing: 18) {
                if model.focus.focusedID == f.id && model.focus.isPinned {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Palette.signal)
                }
                Text(f.displayIdentifier)
                    .font(.mono(96, .heavy))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            if f.hasRoute {
                RouteLine(flight: f)
                    .scaleEffect(1.8, anchor: .leading)
                    .frame(height: 100, alignment: .leading)
                if let progress = RouteProgress(flight: f, position: contact.coordinate) {
                    RouteProgressView(progress: progress, scale: 1.8)
                }
            }
            if let name = f.typeName ?? f.typeCode {
                Text(name)
                    .font(.mono(28, .medium))
                    .foregroundStyle(Palette.caption)
            }
            // The photo takes whatever height is left, so the button row always fits.
            photoView
                .frame(width: 700)
                .frame(minHeight: 180, maxHeight: 400)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .layoutPriority(-1)
            if let photo {
                Text("Photo © \(photo.photographer ?? "Unknown") · Planespotters.net")
                    .font(.mono(18))
                    .foregroundStyle(Palette.caption)
                    .lineLimit(1)
            }
        }
    }

    private func actions(_ contact: RadarContact) -> some View {
        let f = contact.flight
        return HStack(spacing: 24) {
            if model.focus.focusedID == f.id {
                pill(model.focus.isPinned ? "Unpin" : "Pin", prominent: true) {
                    withAnimation(.snappy) { model.togglePin() }
                }
            } else {
                pill("Show on Radar", prominent: true) {
                    model.focus(on: f.id)
                    onClose()
                }
            }
            if !model.contacts.contains(where: { $0.id == f.id }), f.canLocate {
                pill("Where Is It Now?") { showWhereabouts = true }
            }
            if DetailMap.canShowRoute(f) {
                pill(mapMode == .route ? "Nearby Map" : "Full Route") {
                    withAnimation(.smooth) { mapMode = mapMode == .route ? .nearby : .route }
                }
            }
            if let logbook, let airframe = f.registration ?? f.hex {
                // Every time you've seen this airframe; click for the full log.
                let count = logbook.summary(airframe: airframe).count
                Button { showsLog = true } label: {
                    TVLogbookCountLabel(count: count)
                        .fixedSize()
                }
                .buttonStyle(TVPillButtonStyle(prominent: false))
                .disabled(count == 0)
            }
            Spacer(minLength: 0)
            pill("Close", action: onClose)
        }
        .focusSection()
    }

    private func pill(_ title: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .lineLimit(1)
                .fixedSize()
        }
        .buttonStyle(TVPillButtonStyle(prominent: prominent))
    }

    @ViewBuilder
    private var photoView: some View {
        if let photo {
            AsyncImage(url: photo.imageURL, transaction: Transaction(animation: .smooth)) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    Palette.paperShade.opacity(0.4).overlay(ProgressView())
                }
            }
        } else {
            ZStack {
                Palette.paperShade.opacity(0.35)
                Image(systemName: contact?.flight.kind == .helicopter ? "fan.fill" : "airplane")
                    .font(.system(size: 120, weight: .light))
                    .foregroundStyle(Palette.faint)
            }
        }
    }

    private func stats(_ contact: RadarContact) -> some View {
        let f = contact.flight
        let cpa = contact.isApproaching
            ? "\(RadarFormat.miles(contact.closestApproach.distanceMiles)) mi in \(RadarFormat.countdown(contact.closestApproach.secondsFromNow))"
            : "Moving away"
        let rows: [(String, String)] = [
            ("Altitude", "\(RadarFormat.wholeNumber(f.altitudeFeet)) ft"),
            ("Speed", "\(RadarFormat.wholeNumber(f.groundSpeedKnots)) kts"),
            ("Distance", "\(RadarFormat.miles(contact.distanceMiles)) mi \(GeoMath.cardinal(contact.bearing))"),
            ("Vertical", f.verticalRateFPM == 0 ? "Level" : "\(f.verticalRateFPM > 0 ? "+" : "")\(RadarFormat.wholeNumber(f.verticalRateFPM)) fpm"),
            ("Track", "\(Int(f.track.rounded()))° \(GeoMath.cardinal(f.track))"),
            ("Closest pass", cpa),
            ("Registration", f.registration ?? "—"),
            ("Callsign", f.callsign ?? "—"),
            ("Squawk", f.squawk ?? "—"),
        ]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: 3), spacing: 20) {
            ForEach(rows, id: \.0) { row in
                VStack(alignment: .leading, spacing: 8) {
                    Text(row.0).radarCaptionTV()
                    Text(row.1)
                        .font(.mono(28, .semibold))
                        .foregroundStyle(Palette.value)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(22)
                .background(Palette.paperShade.opacity(0.35), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
    }
}

struct TVAircraftListView: View {
    let model: RadarModel
    let heading: Double
    let onPick: (String) -> Void

    var body: some View {
        ZStack {
            RadarBackdrop(showTopography: true, showSweep: false, isActive: true)
                .ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    Text("Aircraft")
                        .font(.mono(56, .heavy))
                        .foregroundStyle(Palette.ink)
                        .padding(.bottom, 10)
                    if model.allContacts.isEmpty {
                        Text("Nothing in the sky right now.")
                            .font(.mono(28))
                            .foregroundStyle(Palette.caption)
                    }
                    if !model.contacts.isEmpty {
                        TVSectionHeader(title: "In range · \(model.contacts.count)")
                        ForEach(model.contacts) { row($0) }
                    }
                    if !model.outsideContacts.isEmpty {
                        TVSectionHeader(title: "Just outside · \(model.outsideContacts.count)")
                        ForEach(model.outsideContacts) { row($0) }
                    }
                }
                .padding(.horizontal, 160)
                .padding(.vertical, 60)
            }
        }
    }

    private func row(_ contact: RadarContact) -> some View {
        Button {
            onPick(contact.id)
        } label: {
            AircraftRow(contact: contact, heading: heading, isFocusedAircraft: model.focus.focusedID == contact.id)
        }
        .buttonStyle(TVRowButtonStyle())
    }

    private struct AircraftRow: View {
        let contact: RadarContact
        let heading: Double
        let isFocusedAircraft: Bool
        @Environment(\.tvRowFocused) private var focused

        var body: some View {
            let f = contact.flight
            HStack(spacing: 28) {
                AircraftBlip(kind: f.kind, screenTrack: f.track - heading, isFocused: isFocusedAircraft, scale: 1.3)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 16) {
                        Text(f.displayIdentifier).font(.mono(32, .bold))
                        if f.hasRoute {
                            Text("\(f.originIATA ?? "") → \(f.destinationIATA ?? "")")
                                .font(.mono(24, .semibold))
                                .foregroundStyle(focused ? .white.opacity(0.9) : Palette.route)
                        }
                        if let top = f.notable.first {
                            NotableBadge(info: top, scale: 1.5)
                        }
                    }
                    Text([f.operatorInfo.compact, f.typeName ?? f.typeCode].compactMap { $0 }.joined(separator: " · "))
                        .font(.mono(20))
                        .foregroundStyle(focused ? .white.opacity(0.8) : Palette.caption)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text("\(RadarFormat.miles(contact.distanceMiles)) mi")
                        .font(.mono(30, .bold))
                    Text("\(RadarFormat.wholeNumber(f.altitudeFeet)) ft")
                        .font(.mono(20))
                        .foregroundStyle(focused ? .white.opacity(0.8) : Palette.caption)
                }
            }
        }
    }
}
#endif
