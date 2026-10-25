//
//  FlightSearchSheet.swift
//  WhatTheFlight
//
//  Every aircraft the radar can see, searchable by flight, airline, type, registration or
//  airport, plus any aircraft in the world by tail number, flight number or callsign.
//  Tapping one sends it to the centre of the radar; the pin button follows it wherever it
//  goes (on the radar edge and the map, with a pin on its icon).
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
            // Pinned aircraft are listed once, in their own section.
            let pinnedIDs = model.pinnedIDs
            let inRange = model.contacts.filter { !pinnedIDs.contains($0.id) && $0.flight.matches(search: query) }
            let outside = model.outsideContacts.filter { !pinnedIDs.contains($0.id) && $0.flight.matches(search: query) }
            let pins = model.pins.filter(matches)
            let known = Set((inRange + outside).map(\.id)).union(pinnedIDs)
            let remote = worldwide.filter { !known.contains($0.id) }
            List {
                if !pins.isEmpty {
                    Section {
                        ForEach(pins) { pinRow($0) }
                    } header: {
                        Text("Pinned · \(pins.count)")
                    } footer: {
                        if trimmedQuery.isEmpty {
                            Text("Pinned aircraft stay on the radar edge and the map wherever they are.")
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
                worldwideSection(remote, hasLocal: !(inRange.isEmpty && outside.isEmpty && pins.isEmpty))
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
            pinButton(isPinned: true) { withAnimation(.snappy) { model.unpin(pin) } }
        }
        .padding(.vertical, 4)
        .listRowBackground(Palette.paperShade.opacity(0.25))
    }

    private func row(_ contact: RadarContact, isRemote: Bool = false) -> some View {
        let f = contact.flight
        let isFocused = model.focus.focusedID == contact.id
        let isPinned = model.isPinned(contact.id)
        return HStack(spacing: 10) {
            Button {
                open(contact, isRemote: isRemote)
            } label: {
                HStack(spacing: 14) {
                    AircraftGlyph(silhouette: contact.profile.silhouette, size: 28, spinsRotor: false)
                        .rotationEffect(.degrees(f.track - heading))
                        .foregroundStyle(isFocused ? Palette.signal : f.isOnGround ? Palette.faint : Palette.blip(for: contact.profile))
                        .frame(width: 30)
                        .overlay(alignment: .bottomLeading) {
                            if isPinned { PinMarker(scale: 0.9).offset(x: -4, y: 4) }
                        }

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
                        Text("\(RadarFormat.wholeNumber(Int(contact.distanceMiles.rounded()))) mi")
                            .monoScaled(15, .bold)
                            .foregroundStyle(Palette.value)
                            .lineLimit(1)
                        Text(f.isOnGround ? "Ground" : "\(RadarFormat.wholeNumber(contact.altitudeFeet)) ft")
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

            pinButton(isPinned: isPinned) {
                withAnimation(.snappy) {
                    if isPinned { model.unpin(contact.id) } else { model.pin(f) }
                }
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(isFocused ? Palette.signal.opacity(0.08) : Palette.paperShade.opacity(0.25))
    }

    private func subtitle(for f: Flight, isRemote: Bool) -> String {
        var parts = [f.operatorInfo.compact, f.typeName ?? f.typeCode]
        // Far-away results are easier to tell apart by their tail number.
        if isRemote, let reg = f.registration, reg != f.displayIdentifier { parts.insert(reg, at: 0) }
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    private func pinButton(isPinned: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isPinned ? Palette.ink : Palette.caption)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(isPinned ? "Unpin" : "Pin")
        .accessibilityHint(isPinned ? "Stops following this aircraft" : "Follows this aircraft on the radar wherever it goes")
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
