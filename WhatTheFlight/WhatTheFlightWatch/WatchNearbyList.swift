//
//  WatchNearbyList.swift
//  WhatTheFlightWatch
//
//  Everything in range, nearest first: the readable fallback when the radar is too busy.
//

import SwiftUI

struct WatchNearbyList: View {
    let model: RadarModel
    let settings: RadarSettings
    let location: WatchLocationService
    let watchSettings: WatchSettings
    let open: (WatchRootView.Screen) -> Void
    /// Set when the list is the page below the radar; when pushed, the back button does this.
    var close: (() -> Void)? = nil

    private var heading: Double {
        watchSettings.northUp ? 0 : (location.heading ?? 0)
    }

    var body: some View {
        List {
            if model.contacts.isEmpty {
                Text("Nothing within \(Int(settings.radiusMiles)) mi right now.")
                    .font(.mono(11))
                    .foregroundStyle(Palette.caption)
            }
            ForEach(model.contacts) { contact in
                Button {
                    model.focus(on: contact.id)
                    open(.detail(contact.id))
                } label: {
                    row(contact)
                }
            }
            if !model.outsideContacts.isEmpty {
                Text("+\(model.outsideContacts.count) just outside your \(Int(settings.radiusMiles)) mi radius")
                    .font(.mono(9))
                    .foregroundStyle(Palette.faint)
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Nearby")
        .toolbar {
            if let close {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: close) { Image(systemName: "xmark") }
                        .accessibilityLabel("Back to radar")
                }
            }
        }
    }

    private func row(_ contact: RadarContact) -> some View {
        let f = contact.flight
        let tag = f.notable.first?.tag
        return HStack(spacing: 8) {
            Image(systemName: f.kind == .helicopter ? "fan.fill" : "airplane")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tag.map(Palette.color(for:)) ?? (f.kind == .helicopter ? Palette.heliBlip : Palette.blip))
                .rotationEffect(.degrees(f.kind == .helicopter ? 0 : f.track - heading - 90))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(f.displayIdentifier).font(.mono(14, .heavy)).foregroundStyle(Palette.ink)
                    if contact.id == model.focus.focusedID {
                        Circle().fill(Palette.signal).frame(width: 5, height: 5)
                    }
                }
                Text(subtitle(f))
                    .font(.mono(9))
                    .foregroundStyle(Palette.caption)
                    .lineLimit(1)
            }
            Spacer(minLength: 2)
            VStack(alignment: .trailing, spacing: 1) {
                HStack(spacing: 2) {
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Palette.signal)
                        .rotationEffect(.degrees(contact.bearing - heading))
                    Text("\(RadarFormat.miles(contact.distanceMiles))").font(.mono(13, .bold)).foregroundStyle(Palette.value)
                }
                Text("\(RadarFormat.wholeNumber(f.altitudeFeet / 100 * 100))′")
                    .font(.mono(9))
                    .foregroundStyle(Palette.caption)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(f.displayIdentifier), \(RadarFormat.miles(contact.distanceMiles)) miles \(GeoMath.cardinal(contact.bearing)), \(RadarFormat.wholeNumber(f.altitudeFeet)) feet")
    }

    private func subtitle(_ f: Flight) -> String {
        if f.hasRoute { return "\(f.originIATA ?? "") → \(f.destinationIATA ?? "")" }
        return f.typeName ?? f.typeCode ?? f.operatorInfo.compact
    }
}
