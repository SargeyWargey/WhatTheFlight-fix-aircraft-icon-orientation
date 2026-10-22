//
//  FlightSearchSheet.swift
//  WhatTheFlight
//
//  Every aircraft the radar can see, searchable by flight, airline, type, registration or
//  airport. Tapping one sends it to the centre of the radar.
//

#if os(iOS)
import SwiftUI

struct FlightSearchSheet: View {
    let model: RadarModel
    let heading: Double
    var openLogbook: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private func matches(_ contact: RadarContact) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        let f = contact.flight
        let haystack: [String?] = [
            f.flightNumber, f.callsign, f.registration, f.typeCode, f.typeName,
            f.operatorInfo.title, f.airline?.iata, f.airlineICAO, f.airline?.radioCallsign,
            f.notable.first?.badge,
            f.originIATA, f.destinationIATA, f.origin?.city, f.destination?.city, f.squawk,
        ]
        return haystack.contains { $0?.lowercased().contains(q) == true }
    }

    var body: some View {
        NavigationStack {
            let inRange = model.contacts.filter(matches)
            let outside = model.outsideContacts.filter(matches)
            List {
                if inRange.isEmpty && outside.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .listRowBackground(Color.clear)
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
            }
            .scrollContentBackground(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Flight, airline, type, airport…")
            .navigationTitle("Aircraft")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let openLogbook {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Logbook", systemImage: "book.closed", action: openLogbook)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.font(.mono(15, .semibold))
                }
            }
        }
    }

    private func row(_ contact: RadarContact) -> some View {
        let f = contact.flight
        let isFocused = model.focus.focusedID == contact.id
        return Button {
            withAnimation(.snappy) { model.focus(on: contact.id) }
            dismiss()
        } label: {
            HStack(spacing: 14) {
                AircraftGlyph(silhouette: f.silhouette, size: 28, spinsRotor: false)
                    .rotationEffect(.degrees(f.track - heading))
                    .foregroundStyle(isFocused ? Palette.signal : Palette.blip(for: f))
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(f.displayIdentifier)
                            .font(.mono(17, .bold))
                            .foregroundStyle(Palette.ink)
                        if f.hasRoute {
                            Text("\(f.originIATA ?? "") → \(f.destinationIATA ?? "")")
                                .font(.mono(12, .semibold))
                                .foregroundStyle(Palette.route)
                        }
                        if let top = f.notable.first {
                            Image(systemName: top.tag.symbol)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Palette.color(for: top.tag))
                                .accessibilityLabel(top.badge.capitalized)
                        }
                    }
                    Text([f.operatorInfo.compact, f.typeName ?? f.typeCode].compactMap { $0 }.joined(separator: " · "))
                        .font(.mono(11))
                        .foregroundStyle(Palette.caption)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(RadarFormat.miles(contact.distanceMiles)) mi")
                        .font(.mono(15, .bold))
                        .foregroundStyle(Palette.value)
                    Text("\(RadarFormat.wholeNumber(f.altitudeFeet)) ft")
                        .font(.mono(11))
                        .foregroundStyle(Palette.caption)
                }
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(isFocused ? Palette.signal.opacity(0.08) : Palette.paperShade.opacity(0.25))
    }
}
#endif
