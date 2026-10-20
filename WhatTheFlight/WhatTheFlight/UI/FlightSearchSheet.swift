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
                Group {
                    if f.kind == .helicopter {
                        Image("helicopter-bottom-view").resizable().renderingMode(.template).scaledToFit()
                            .frame(width: 22, height: 22)
                            .rotationEffect(.degrees(f.track - heading))
                    } else {
                        Image(systemName: "airplane")
                            .font(.system(size: 19, weight: .semibold))
                            .rotationEffect(.degrees(f.track - heading - 90))
                    }
                }
                .foregroundStyle(isFocused ? Palette.signal : Palette.blip)
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

// MARK: - Welcome

struct WelcomeSheet: View {
    let onStart: () -> Void
    let onDemo: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            Image(systemName: "airplane")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .rotationEffect(.degrees(-45))
                .padding(.bottom, 14)
            Text("WhatTheFlight")
                .font(.mono(32, .heavy))
                .foregroundStyle(Palette.ink)
            Text("Point your phone at the sky.\nEvery aircraft around you, where it really is.")
                .font(.mono(13))
                .foregroundStyle(Palette.caption)
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 18) {
                tip("hand.tap", "Tap an aircraft on the edge", "to bring it to the centre")
                tip("arrow.right", "Swipe right", "to snap back to the nearest")
                tip("arrow.left", "Swipe left", "to step to the next one out")
                tip("lock", "Hold the flight number", "to pin it, even outside your radius")
                tip("arrow.down", "Swipe down", "to search everything in the sky")
                tip("location.north.line", "Turn around", "the edge rotates with your compass")
                tip("camera.viewfinder", "Lift your phone to the sky", "to see every aircraft labelled")
            }
            .padding(.vertical, 28)
            .padding(.horizontal, 6)

            Spacer(minLength: 12)

            Button(action: onStart) {
                Text("Start Watching").frame(maxWidth: .infinity)
            }
            .buttonStyle(RadarButtonStyle(prominent: true))
            Button("Try Demo Traffic", action: onDemo)
                .font(.mono(13, .semibold))
                .foregroundStyle(Palette.ink)
                .padding(.top, 12)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 20)
        .background(Palette.paper.ignoresSafeArea())
        .interactiveDismissDisabled()
    }

    private func tip(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.signal)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.mono(14, .bold)).foregroundStyle(Palette.value)
                Text(detail).font(.mono(12)).foregroundStyle(Palette.caption)
            }
        }
    }
}
#endif
