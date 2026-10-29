//
//  AirframeFactsView.swift
//  WhatTheFlight
//
//  The airframe's maker and exact variant and who it's registered to, under its type on a
//  flight's details (iPhone, iPad, Apple TV). Loads quietly: nothing shows until the
//  answer arrives, and nothing is asked with Aircraft details off.
//

#if os(iOS) || os(tvOS)
import SwiftUI

struct AirframeFactsView: View {
    let registration: String?
    let hex: String?
    var scale: CGFloat = 1
    /// Sheets follow Dynamic Type; the TV draws at a fixed 10-foot size.
    var scales = true

    @State private var facts: AirframeFacts?

    var body: some View {
        VStack(spacing: 2 * scale) {
            if let facts {
                ForEach([facts.title, facts.ageLine(), facts.ownerLine].compactMap { $0 }, id: \.self) { line in
                    if scales {
                        Text(line).monoScaled(11, .medium)
                    } else {
                        Text(line).font(.mono(11 * scale, .medium))
                    }
                }
                .foregroundStyle(Palette.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .transition(.opacity)
            }
        }
        .animation(.smooth, value: facts)
        .task(id: registration ?? hex) {
            facts = await AircraftFactsProvider.shared.facts(registration: registration, hex: hex)
        }
    }
}
#endif
