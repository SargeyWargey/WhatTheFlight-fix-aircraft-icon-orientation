//
//  SkyWatchLiveActivity.swift
//  WhatTheFlightWidgets
//
//  Sky Watch on the Lock Screen and in the Dynamic Island: the next aircraft heading your
//  way, a live countdown to its closest pass, and a Stop button. Apple Watch shows it in the
//  Smart Stack using the compact `.small` layout.
//

import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

struct SkyWatchLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SkyWatchAttributes.self) { context in
            SkyWatchActivityView(context: context)
                .activityBackgroundTint(Palette.paper.opacity(0.92))
                .activitySystemActionForegroundColor(Palette.ink)
                .widgetURL(url(context.state))
        } dynamicIsland: { context in
            let f = context.state.flight
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(f?.identifier ?? "Watching", systemImage: f?.isHelicopter == true ? "fan.fill" : "airplane")
                            .font(.mono(16, .heavy))
                            .foregroundStyle(Palette.signal)
                        if let route = f?.route {
                            Text(route).font(.mono(12, .bold)).foregroundStyle(Palette.route)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let f {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(RadarFormat.distanceText(f.distanceMiles))").font(.mono(16, .heavy))
                            Text("\(GeoMath.cardinal(f.bearing)) · \(RadarFormat.altitudeText(f.altitudeFeet))")
                                .font(.mono(11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        PassCountdown(state: context.state)
                            .font(.mono(13, .semibold))
                        Spacer()
                        Button(intent: StopSkyWatchIntent()) {
                            Label("Stop", systemImage: "stop.fill").font(.mono(12, .bold))
                        }
                        .tint(Palette.signal)
                    }
                }
            } compactLeading: {
                Image(systemName: f?.isHelicopter == true ? "fan.fill" : "airplane")
                    .foregroundStyle(Palette.signal)
            } compactTrailing: {
                Text(f.map { "\(RadarFormat.distanceText($0.distanceMiles))" } ?? "\(context.state.inRangeCount)")
                    .font(.mono(13, .bold))
            } minimal: {
                Image(systemName: "airplane").foregroundStyle(Palette.signal)
            }
            .widgetURL(url(context.state))
        }
        .supplementalActivityFamilies([.small])
    }

    private func url(_ state: SkyWatchAttributes.ContentState) -> URL {
        state.flight.map { AppRouter.url(for: .flight($0.id)) } ?? AppRouter.url(for: .radar)
    }
}

/// "Overhead in 1:42" (counting down live), "Passing now", or "Moving away".
private struct PassCountdown: View {
    let state: SkyWatchAttributes.ContentState

    var body: some View {
        if let passAt = state.passAt, passAt > Date() {
            HStack(spacing: 4) {
                Image(systemName: "scope")
                Text("Closest pass in")
                Text(timerInterval: Date()...passAt, countsDown: true)
                    .monospacedDigit()
                    .frame(maxWidth: 56, alignment: .leading)
            }
        } else if state.flight != nil {
            Label(state.passAt == nil ? "Moving away" : "Passing now", systemImage: "scope")
        } else {
            Label("Clear skies — still watching", systemImage: "sun.haze")
        }
    }
}

/// The Lock Screen banner, or the compact layout on Apple Watch.
private struct SkyWatchActivityView: View {
    let context: ActivityViewContext<SkyWatchAttributes>
    @Environment(\.activityFamily) private var family

    var body: some View {
        if family == .small {
            SkyWatchSmallView(context: context)
        } else {
            SkyWatchLockScreenView(context: context)
        }
    }
}

/// Apple Watch Smart Stack: which aircraft, where to look, and the countdown.
private struct SkyWatchSmallView: View {
    let context: ActivityViewContext<SkyWatchAttributes>

    var body: some View {
        let state = context.state
        VStack(alignment: .leading, spacing: 3) {
            if let f = state.flight {
                HStack(spacing: 5) {
                    Image(systemName: "location.north.fill")
                        .rotationEffect(.degrees(f.bearing))
                        .foregroundStyle(Palette.signal)
                    Text(f.identifier)
                        .font(.mono(16, .heavy))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 2)
                    Text("\(RadarFormat.distanceText(f.distanceMiles)) \(GeoMath.cardinal(f.bearing))")
                        .font(.mono(12, .bold))
                        .foregroundStyle(Palette.value)
                }
                Text([f.route, "\(RadarFormat.altitudeText(f.altitudeFeet))"].compactMap { $0 }.joined(separator: " · "))
                    .font(.mono(11, .semibold))
                    .foregroundStyle(Palette.route)
                    .lineLimit(1)
            } else {
                Label("Sky Watch", systemImage: "dot.radiowaves.left.and.right")
                    .font(.mono(14, .heavy))
                    .foregroundStyle(Palette.signal)
            }
            HStack {
                PassCountdown(state: state)
                    .font(.mono(11, .semibold))
                    .foregroundStyle(Palette.caption)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text("\(state.inRangeCount) in range")
                    .font(.mono(10))
                    .foregroundStyle(Palette.caption)
            }
        }
        .padding(10)
    }
}

private struct SkyWatchLockScreenView: View {
    let context: ActivityViewContext<SkyWatchAttributes>

    var body: some View {
        let state = context.state
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(Palette.signal)
                Text("Sky Watch · \(context.attributes.placeName)")
                    .font(.mono(11, .bold))
                    .foregroundStyle(Palette.caption)
                    .lineLimit(1)
                Spacer()
                Text("\(state.inRangeCount) in \(RadarFormat.radius(Double(context.attributes.radiusMiles)))")
                    .font(.mono(11, .semibold))
                    .foregroundStyle(Palette.caption)
            }
            if let f = state.flight {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(f.operatorName)
                            .font(.mono(10, .semibold))
                            .textCase(.uppercase)
                            .foregroundStyle(Palette.caption)
                            .lineLimit(1)
                        HStack(spacing: 8) {
                            Text(f.identifier).font(.mono(26, .heavy)).foregroundStyle(Palette.ink)
                            if let route = f.route {
                                Text(route).font(.mono(15, .bold)).foregroundStyle(Palette.route)
                            }
                        }
                        if let badge = f.notableBadge, let tag = f.notableTag {
                            Text(badge).font(.mono(10, .heavy)).foregroundStyle(Palette.color(for: tag))
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(RadarFormat.distanceText(f.distanceMiles)) \(GeoMath.cardinal(f.bearing))")
                            .font(.mono(17, .heavy))
                            .foregroundStyle(Palette.value)
                        Text("\(RadarFormat.altitudeText(f.altitudeFeet))")
                            .font(.mono(12))
                            .foregroundStyle(Palette.caption)
                    }
                }
            }
            HStack {
                PassCountdown(state: state)
                    .font(.mono(12, .semibold))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Button(intent: StopSkyWatchIntent()) {
                    Label("Stop", systemImage: "stop.fill").font(.mono(12, .bold))
                }
                .tint(Palette.signal)
            }
        }
        .padding(16)
    }
}
