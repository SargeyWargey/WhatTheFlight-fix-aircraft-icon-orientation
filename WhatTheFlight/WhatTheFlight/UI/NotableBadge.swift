//
//  NotableBadge.swift
//  WhatTheFlight
//
//  "EMERGENCY 7700", "MILITARY", "RARE · A380" — the capsule that marks notable traffic.
//

#if os(iOS) || os(tvOS) || os(watchOS)
import SwiftUI

struct NotableBadge: View {
    let info: NotableInfo
    var scale: CGFloat = 1

    @State private var flash = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var color: Color { Palette.color(for: info.tag) }

    var body: some View {
        HStack(spacing: 5 * scale) {
            Image(systemName: info.tag.symbol)
                .font(.system(size: 10 * scale, weight: .heavy))
            Text(info.badge)
                .font(.mono(11 * scale, .heavy))
                .tracking(1.2 * scale)
                .lineLimit(1)
        }
        .foregroundStyle(info.tag.isEmergency ? Color.white : color)
        .padding(.horizontal, 10 * scale)
        .padding(.vertical, 4 * scale)
        .background {
            Capsule()
                .fill(info.tag.isEmergency ? color.opacity(flash ? 0.65 : 1) : color.opacity(0.14))
        }
        .overlay(Capsule().stroke(color.opacity(info.tag.isEmergency ? 0 : 0.45), lineWidth: 1))
        .onAppear {
            guard info.tag.isEmergency, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.6).repeatForever()) { flash = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(info.badge.capitalized)
    }
}

/// Every badge for a flight, wrapping onto a second line if needed.
struct NotableBadgeRow: View {
    let flight: Flight
    var scale: CGFloat = 1

    var body: some View {
        let infos = flight.notable
        if !infos.isEmpty {
            HStack(spacing: 6 * scale) {
                ForEach(infos, id: \.tag) { NotableBadge(info: $0, scale: scale) }
            }
        }
    }
}
#endif
