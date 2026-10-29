//
//  FlightSearchSheet.swift
//  WhatTheFlight
//
//  Every aircraft the radar can see, searchable by flight, airline, type, registration or
//  airport, plus any aircraft in the world by tail number, flight number or callsign.
//  Tapping one sends it to the centre of the radar; pinning it, from its details, follows it
//  wherever it goes (on the radar edge and the map). Rows carry no pin button: a pinned
//  aircraft that isn't flying, which has no details, is unpinned with a swipe. Favourites come
//  first, live when they're flying nearby, otherwise a way to find out where they are; swipe
//  any row to add or remove one.
//

#if os(iOS)
import SwiftUI

struct FlightSearchSheet: View {
    let model: RadarModel
    let heading: Double

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if DEBUG
    /// `-wtf.debugAircraftSearch DL121` opens with a search typed in.
    @State private var query = UserDefaults.standard.string(forKey: "wtf.debugAircraftSearch") ?? ""
    #else
    @State private var query = ""
    #endif
    @State private var worldwide: [RadarContact] = []
    @State private var worldwideState = FlightSearchState.idle

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            // Favourites, then pins, are listed once, in their own sections.
            let favorites = model.favorites.filter(matches).map { FavoriteEntry(favorite: $0, state: model.state(of: $0)) }
            let favoriteIDs = Set(favorites.compactMap(\.liveID))
            let pinnedIDs = model.pinnedIDs
            let listed = pinnedIDs.union(favoriteIDs)
            let inRange = model.contacts.filter { !listed.contains($0.id) && $0.flight.matches(search: query) }
            let outside = model.outsideContacts.filter { !listed.contains($0.id) && $0.flight.matches(search: query) }
            let pins = model.pins.filter { pin in matches(pin) && !favoriteIDs.contains(pin.flightID) }
            let known = Set((inRange + outside).map(\.id)).union(listed)
            let remote = worldwide.filter { !known.contains($0.id) }
            List {
                if !favorites.isEmpty {
                    Section {
                        ForEach(favorites) { favoriteRow($0.favorite, state: $0.state) }
                    } header: {
                        Text("Favorites · \(favorites.count)")
                    } footer: {
                        if trimmedQuery.isEmpty {
                            Text("Favorites show in yellow on the radar, the map and in your logbook. Swipe any aircraft to add or remove one.")
                        }
                    }
                }
                if !pins.isEmpty {
                    Section {
                        ForEach(pins) { pinRow($0) }
                    } header: {
                        Text("Pinned · \(pins.count)")
                    } footer: {
                        if trimmedQuery.isEmpty {
                            Text("Pinned aircraft stay on the radar edge and the map wherever they are. Unpin one from its details, or swipe one that isn't flying.")
                        }
                    }
                }
                if !inRange.isEmpty {
                    Section("In range · \(inRange.count)") {
                        ForEach(inRange) { row($0) }
                    }
                }
                if !outside.isEmpty {
                    Section("Just outside · \(outside.count)") {
                        ForEach(outside) { row($0) }
                    }
                }
                worldwideSection(remote, hasLocal: !(inRange.isEmpty && outside.isEmpty && pins.isEmpty && favorites.isEmpty))
            }
            .scrollContentBackground(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Flight, tail number, airline, airport…")
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .navigationTitle("Aircraft")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }.monoScaled(15, .semibold)
                }
            }
            .task(id: trimmedQuery) { await searchWorldwide() }
        }
    }

    // MARK: Worldwide

    @ViewBuilder
    private func worldwideSection(_ remote: [RadarContact], hasLocal: Bool) -> some View {
        if trimmedQuery.filter({ !$0.isWhitespace }).count >= 3 {
            Section {
                ForEach(remote) { row($0, isRemote: true) }
                switch worldwideState {
                case .searching where remote.isEmpty:
                    Label("Searching Flightradar24…", systemImage: "magnifyingglass")
                        .foregroundStyle(Palette.caption)
                case .done where remote.isEmpty && !hasLocal:
                    ContentUnavailableView.search(text: trimmedQuery)
                        .listRowBackground(Color.clear)
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Palette.caption)
                default:
                    EmptyView()
                }
            } header: {
                Text(remote.isEmpty ? "Worldwide" : "Worldwide · \(remote.count)")
            } footer: {
                Text("Tail numbers, flight numbers (DL570) and callsigns (DAL570) anywhere in the world.")
            }
        } else if !hasLocal, !trimmedQuery.isEmpty {
            Text("Keep typing to search worldwide by tail or flight number.")
                .monoScaled(13)
                .foregroundStyle(Palette.caption)
                .listRowBackground(Color.clear)
        }
    }

    private func searchWorldwide() async {
        worldwide = []
        worldwideState = .idle
        guard trimmedQuery.filter({ !$0.isWhitespace }).count >= 3 else { return }
        // Wait for a pause in typing: every search is three Flightradar24 requests.
        try? await Task.sleep(for: .milliseconds(600))
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

    // MARK: Rows

    private func matches(_ pin: PinnedAircraft) -> Bool {
        if case .visible(let contact) = model.state(of: pin), contact.flight.matches(search: query) { return true }
        return [pin.label, pin.registration, pin.callsign].contains { $0?.lowercased().contains(trimmedQuery.lowercased()) == true }
            || trimmedQuery.isEmpty
    }

    /// A favourite and where it is now.
    private struct FavoriteEntry: Identifiable {
        let favorite: FavoriteAircraft
        let state: RadarModel.PinState
        var id: String { favorite.id }
        /// On the radar or the map, so it isn't listed again below.
        var liveID: String? {
            if case .visible(let contact) = state { return contact.id }
            return nil
        }
    }

    private func matches(_ favorite: FavoriteAircraft) -> Bool {
        guard !trimmedQuery.isEmpty else { return true }
        if case .visible(let contact) = model.state(of: favorite), contact.flight.matches(search: query) { return true }
        let q = trimmedQuery.lowercased()
        return [favorite.title, favorite.label, favorite.registration, favorite.callsign, favorite.typeName, favorite.operatorName]
            .contains { $0?.lowercased().contains(q) == true }
    }

    @ViewBuilder
    private func favoriteRow(_ favorite: FavoriteAircraft, state: RadarModel.PinState) -> some View {
        switch state {
        case .visible(let contact):
            row(contact)
        case .onGround(let flight):
            unseenFavoriteRow(favorite, status: flight.destinationIATA.map { "On the ground · \($0)" } ?? "On the ground")
        case .unseen:
            unseenFavoriteRow(favorite, status: "Not nearby")
        }
    }

    /// A favourite that isn't on the radar or the map: where it is is one tap away.
    @ViewBuilder
    private func unseenFavoriteRow(_ favorite: FavoriteAircraft, status: String) -> some View {
        let content = HStack(spacing: 14) {
            AircraftGlyph(silhouette: favorite.silhouette, size: 28, spinsRotor: false)
                .foregroundStyle(Palette.favorite.opacity(0.6))
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(favorite.title)
                        .monoScaled(17, .bold)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.favorite)
                        .accessibilityLabel("Favorite")
                }
                Text([favorite.typeName ?? favorite.typeCode, favorite.operatorName].compactMap { $0 }.joined(separator: " · "))
                    .monoScaled(11)
                    .foregroundStyle(Palette.caption)
                    .lineLimit(1)
                Text(favorite.canLocate ? "\(status) · Where is it now?" : status)
                    .monoScaled(11, .semibold)
                    .foregroundStyle(favorite.canLocate ? Palette.route : Palette.caption)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
        }
        .padding(.vertical, 4)
        Group {
            if favorite.canLocate {
                NavigationLink {
                    WhereaboutsView(title: favorite.title, registration: favorite.registration, callsign: favorite.callsign,
                                    observer: model.observer)
                } label: { content }
            } else {
                content
            }
        }
        .listRowBackground(Palette.paperShade.opacity(0.25))
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                withAnimation(.snappy) { model.unfavorite(favorite) }
            } label: {
                Label("Unfavorite", systemImage: "heart.slash")
            }
        }
    }

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

    /// A pin that isn't flying: it reappears on the radar once it is.
    private func unseenRow(_ pin: PinnedAircraft, status: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "airplane")
                .font(.system(size: 20))
                .foregroundStyle(Palette.faint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(pin.label)
                    .monoScaled(17, .bold)
                    .foregroundStyle(Palette.ink)
                Text([pin.registration == pin.label ? nil : pin.registration, status].compactMap { $0 }.joined(separator: " · "))
                    .monoScaled(11)
                    .foregroundStyle(Palette.caption)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
        }
        .padding(.vertical, 4)
        .listRowBackground(Palette.paperShade.opacity(0.25))
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                withAnimation(.snappy) { model.unpin(pin) }
            } label: {
                Label("Unpin", systemImage: "pin.slash")
            }
        }
        .accessibilityAction(named: "Unpin") { withAnimation(.snappy) { model.unpin(pin) } }
    }

    private func row(_ contact: RadarContact, isRemote: Bool = false) -> some View {
        let f = contact.flight
        let isFocused = model.focus.focusedID == contact.id
        let isFavorite = model.isFavorite(f)
        return HStack(spacing: 10) {
            Button {
                open(contact, isRemote: isRemote)
            } label: {
                HStack(spacing: 14) {
                    AircraftGlyph(silhouette: contact.profile.silhouette, size: 28, spinsRotor: false)
                        .rotationEffect(.degrees(f.track - heading))
                        .foregroundStyle(isFavorite ? Palette.favorite : isFocused ? Palette.signal : f.isOnGround ? Palette.faint : Palette.blip(for: contact.profile))
                        .frame(width: 30)

                    VStack(alignment: .leading, spacing: 3) {
                        // At accessibility sizes the route goes under the flight number.
                        (dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(spacing: 6))) {
                            Text(f.displayIdentifier)
                                .monoScaled(17, .bold)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            if f.hasRoute {
                                Text("\(f.originIATA ?? "") → \(f.destinationIATA ?? "")")
                                    .monoScaled(12, .semibold)
                                    .foregroundStyle(Palette.route)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            if isFavorite {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Palette.favorite)
                                    .accessibilityLabel("Favorite")
                            }
                            if let top = f.notable.first {
                                Image(systemName: top.tag.symbol)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Palette.color(for: top.tag))
                                    .accessibilityLabel(top.badge.capitalized)
                            }
                        }
                        Text(subtitle(for: f, isRemote: isRemote))
                            .monoScaled(11)
                            .foregroundStyle(Palette.caption)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(RadarFormat.wholeDistance(contact.distanceMiles))")
                            .monoScaled(15, .bold)
                            .foregroundStyle(Palette.value)
                            .lineLimit(1)
                        Text(f.isOnGround ? "Ground" : "\(RadarFormat.altitudeText(contact.altitudeFeet))")
                            .monoScaled(11)
                            .foregroundStyle(Palette.caption)
                            .lineLimit(1)
                    }
                    .fixedSize()
                }
                // One row of columns: past this they no longer fit side by side.
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .tint(.primary)
        }
        .padding(.vertical, 4)
        .listRowBackground(isFocused ? Palette.signal.opacity(0.08) : Palette.paperShade.opacity(0.25))
        .swipeActions(edge: .trailing) {
            Button {
                withAnimation(.snappy) { model.toggleFavorite(f) }
            } label: {
                Label(isFavorite ? "Unfavorite" : "Favorite", systemImage: isFavorite ? "heart.slash" : "heart.fill")
            }
            .tint(isFavorite ? Palette.caption : Palette.favorite)
        }
    }

    private func subtitle(for f: Flight, isRemote: Bool) -> String {
        var parts = [f.operatorInfo.compact, f.typeName ?? f.typeCode]
        // Far-away results are easier to tell apart by their tail number.
        if isRemote, let reg = f.registration, reg != f.displayIdentifier { parts.insert(reg, at: 0) }
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    /// In-range and nearby aircraft go to the centre; anything from the worldwide search is
    /// pinned first so the radar keeps following it.
    private func open(_ contact: RadarContact, isRemote: Bool) {
        if isRemote {
            if !model.track(contact.flight) {
                model.post(notice: "\(contact.flight.displayIdentifier) is pinned — it shows up once it's in the air", symbol: "pin.fill")
            }
        } else {
            withAnimation(.snappy) { model.focus(on: contact.id) }
        }
        dismiss()
    }
}
#endif
