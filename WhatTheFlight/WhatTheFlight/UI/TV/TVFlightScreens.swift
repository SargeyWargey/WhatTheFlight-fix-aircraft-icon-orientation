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
                if model.isPinned(f.id) {
                    Image(systemName: "pin.fill")
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
            ProviderPhoto(photo: photo) {
                Palette.paperShade.opacity(0.4).overlay(ProgressView())
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

/// Every aircraft the radar can see, a search field for any aircraft in the world (tail
/// number, flight number or callsign), and the pinned ones. Click a row to show it on the
/// radar; the pin button beside it follows it wherever it goes.
struct TVAircraftListView: View {
    let model: RadarModel
    let heading: Double
    let onPick: (String) -> Void

    #if DEBUG
    @State private var query = UserDefaults.standard.string(forKey: "wtf.debugAircraftSearch") ?? ""
    #else
    @State private var query = ""
    #endif
    @State private var worldwide: [RadarContact] = []
    @State private var worldwideState = FlightSearchState.idle

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }
    private var searchesWorldwide: Bool { trimmedQuery.filter { !$0.isWhitespace }.count >= 3 }

    var body: some View {
        // Pinned aircraft are listed once, in their own section.
        let pinnedIDs = model.pinnedIDs
        let inRange = model.contacts.filter { !pinnedIDs.contains($0.id) && $0.flight.matches(search: query) }
        let outside = model.outsideContacts.filter { !pinnedIDs.contains($0.id) && $0.flight.matches(search: query) }
        let pins = model.pins.filter(matches)
        let known = Set((inRange + outside).map(\.id)).union(pinnedIDs)
        let remote = worldwide.filter { !known.contains($0.id) }
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if trimmedQuery.isEmpty {
                        Text("Aircraft")
                            .font(.mono(56, .heavy))
                            .foregroundStyle(Palette.ink)
                            .padding(.bottom, 10)
                    }
                    if !pins.isEmpty {
                        TVSectionHeader(title: "Pinned · \(pins.count)")
                        ForEach(pins) { pinRow($0) }
                    }
                    if !inRange.isEmpty {
                        TVSectionHeader(title: "In range · \(inRange.count)")
                        ForEach(inRange) { row($0) }
                    }
                    if !outside.isEmpty {
                        TVSectionHeader(title: "Just outside · \(outside.count)")
                        ForEach(outside) { row($0) }
                    }
                    if searchesWorldwide {
                        TVSectionHeader(title: remote.isEmpty ? "Worldwide" : "Worldwide · \(remote.count)")
                        ForEach(remote) { row($0, isRemote: true) }
                    }
                    status(hasResults: !(inRange.isEmpty && outside.isEmpty && pins.isEmpty && remote.isEmpty))
                }
                .padding(.horizontal, 160)
                .padding(.vertical, 40)
            }
            .scrollClipDisabled()
            .searchable(text: $query, prompt: "Tail number, flight, airline…")
            .task(id: trimmedQuery) { await searchWorldwide() }
        }
        .background(RadarBackdrop(showTopography: true, showSweep: false, isActive: true).ignoresSafeArea())
    }

    @ViewBuilder
    private func status(hasResults: Bool) -> some View {
        Group {
            if trimmedQuery.isEmpty {
                if model.allContacts.isEmpty && model.pins.isEmpty {
                    Text("Nothing in the sky right now.")
                }
                Label("Search above for any aircraft in the world by tail number (N509DN), flight (DL121) or callsign (DAL121), then pin it to follow it on the radar.",
                      systemImage: "magnifyingglass")
                    .padding(.top, 20)
            } else if !searchesWorldwide {
                if !hasResults { Label("Keep typing to search worldwide", systemImage: "keyboard") }
            } else {
                switch worldwideState {
                case .searching: Label("Searching Flightradar24…", systemImage: "magnifyingglass")
                case .done where !hasResults: Label("No aircraft found for “\(trimmedQuery)”", systemImage: "airplane.circle")
                case .failed(let message): Label(message, systemImage: "exclamationmark.triangle")
                default: EmptyView()
                }
            }
        }
        .font(.mono(24))
        .labelStyle(TVLabelStyle())
        .foregroundStyle(Palette.caption)
    }

    private func searchWorldwide() async {
        worldwide = []
        worldwideState = .idle
        guard searchesWorldwide else { return }
        // Wait for a pause in typing: every search is three Flightradar24 requests.
        try? await Task.sleep(for: .milliseconds(700))
        guard !Task.isCancelled else { return }
        worldwideState = .searching
        do {
            let found = try await model.searchAnywhere(trimmedQuery)
            guard !Task.isCancelled else { return }
            worldwide = found
            worldwideState = .done
        } catch {
            guard !Task.isCancelled else { return }
            worldwideState = .failed((error as? LocalizedError)?.errorDescription ?? "Search failed")
        }
    }

    private func matches(_ pin: PinnedAircraft) -> Bool {
        if trimmedQuery.isEmpty { return true }
        if case .visible(let contact) = model.state(of: pin), contact.flight.matches(search: query) { return true }
        return [pin.label, pin.registration, pin.callsign].contains { $0?.lowercased().contains(trimmedQuery.lowercased()) == true }
    }

    // MARK: Rows

    @ViewBuilder
    private func pinRow(_ pin: PinnedAircraft) -> some View {
        switch model.state(of: pin) {
        case .visible(let contact):
            row(contact)
        case .onGround(let flight):
            unseenRow(pin, status: flight.destinationIATA.map { "On the ground · \($0)" } ?? "On the ground")
        case .unseen:
            unseenRow(pin, status: "Not transmitting right now")
        }
    }

    /// A pin that isn't flying: it comes back on the radar once it is.
    private func unseenRow(_ pin: PinnedAircraft, status: String) -> some View {
        HStack(spacing: 20) {
            HStack(spacing: 28) {
                Image(systemName: "airplane")
                    .font(.system(size: 36))
                    .foregroundStyle(Palette.faint)
                    .frame(width: 57)
                VStack(alignment: .leading, spacing: 6) {
                    Text(pin.label).font(.mono(32, .bold))
                    Text([pin.registration == pin.label ? nil : pin.registration, status].compactMap { $0 }.joined(separator: " · "))
                        .font(.mono(20))
                        .foregroundStyle(Palette.caption)
                }
                Spacer()
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.paperShade.opacity(0.25), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            pinButton(isPinned: true) { withAnimation(.snappy) { model.unpin(pin) } }
        }
    }

    private func row(_ contact: RadarContact, isRemote: Bool = false) -> some View {
        let isPinned = model.isPinned(contact.id)
        return HStack(spacing: 20) {
            Button {
                open(contact, isRemote: isRemote)
            } label: {
                AircraftRow(contact: contact, heading: heading, isFocusedAircraft: model.focus.focusedID == contact.id,
                            isPinned: isPinned, showsRegistration: isRemote)
            }
            .buttonStyle(TVRowButtonStyle())
            pinButton(isPinned: isPinned) {
                withAnimation(.snappy) {
                    if isPinned { model.unpin(contact.id) } else { model.pin(contact.flight) }
                }
            }
        }
    }

    private func pinButton(isPinned: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: isPinned ? "pin.slash.fill" : "pin.fill")
                .font(.system(size: 30, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(TVRowButtonStyle())
        .frame(width: 130)
        .accessibilityLabel(isPinned ? "Unpin" : "Pin")
    }

    /// Anything from the worldwide search is pinned as it's opened, so the radar keeps
    /// following it however far away it is.
    private func open(_ contact: RadarContact, isRemote: Bool) {
        if isRemote, !model.track(contact.flight) {
            model.post(notice: "\(contact.flight.displayIdentifier) is pinned — it shows up once it's in the air", symbol: "pin.fill")
        }
        onPick(contact.id)
    }

    private struct AircraftRow: View {
        let contact: RadarContact
        let heading: Double
        let isFocusedAircraft: Bool
        var isPinned = false
        var showsRegistration = false
        @Environment(\.tvRowFocused) private var focused

        var body: some View {
            let f = contact.flight
            HStack(spacing: 28) {
                AircraftBlip(profile: contact.profile, screenTrack: f.track - heading, isFocused: isFocusedAircraft, isPinned: isPinned, scale: 1.3)
                    .opacity(f.isOnGround ? 0.5 : 1)
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
                    Text(subtitle(f))
                        .font(.mono(20))
                        .foregroundStyle(focused ? .white.opacity(0.8) : Palette.caption)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text("\(RadarFormat.wholeNumber(Int(contact.distanceMiles.rounded()))) mi")
                        .font(.mono(30, .bold))
                    Text(f.isOnGround ? "Ground" : "\(RadarFormat.wholeNumber(f.altitudeFeet)) ft")
                        .font(.mono(20))
                        .foregroundStyle(focused ? .white.opacity(0.8) : Palette.caption)
                }
            }
        }

        private func subtitle(_ f: Flight) -> String {
            var parts = [f.operatorInfo.compact, f.typeName ?? f.typeCode]
            if showsRegistration, let reg = f.registration, reg != f.displayIdentifier { parts.insert(reg, at: 0) }
            return parts.compactMap { $0 }.joined(separator: " · ")
        }
    }
}
#endif
