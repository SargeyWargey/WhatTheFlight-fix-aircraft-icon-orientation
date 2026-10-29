//
//  FlightFollowLiveActivity.swift
//  WhatTheFlightWidgets
//
//  "Follow on Lock Screen": one flight's progress on the Lock Screen and in the Dynamic
//  Island, ORIGIN → DEST with a progress bar and an arrival countdown that run on timers, so
//  they keep moving between the app's updates.
//

import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

struct FlightFollowLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FlightFollowAttributes.self) { context in
            FlightFollowActivityView(context: context)
                .activityBackgroundTint(Palette.paper.opacity(0.92))
                .activitySystemActionForegroundColor(Palette.ink)
                .widgetURL(AppRouter.url(for: .flight(context.attributes.flightID)))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(context.attributes.identifier, systemImage: "airplane")
                            .font(.mono(16, .heavy))
                            .foregroundStyle(Palette.signal)
                        Text(context.attributes.operatorName)
                            .font(.mono(11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        ArrivalCountdown(state: context.state)
                            .font(.mono(16, .heavy))
                        Text(RadarFormat.altitudeText(context.state.altitudeFeet))
                            .font(.mono(11))
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        RouteBar(attributes: context.attributes, state: context.state)
                        HStack {
                            Text(context.state.phase ?? "")
                                .font(.mono(11, .semibold))
                                .lineLimit(1)
                            Spacer()
                            Button(intent: StopFollowingIntent()) {
                                Label("Stop", systemImage: "stop.fill").font(.mono(11, .bold))
                            }
                            .tint(Palette.signal)
                        }
                    }
                }
            } compactLeading: {
                HStack(spacing: 3) {
                    Image(systemName: "airplane").foregroundStyle(Palette.signal)
                    Text(context.attributes.destinationIATA ?? context.attributes.identifier)
                        .font(.mono(12, .heavy))
                }
            } compactTrailing: {
                ArrivalCountdown(state: context.state, short: true)
                    .font(.mono(12, .heavy))
                    .frame(maxWidth: 56)
            } minimal: {
                Image(systemName: context.state.hasLanded ? "airplane.arrival" : "airplane")
                    .foregroundStyle(Palette.signal)
            }
            .widgetURL(AppRouter.url(for: .flight(context.attributes.flightID)))
        }
    }
}

struct FlightFollowActivityView: View {
    let context: ActivityViewContext<FlightFollowAttributes>

    var body: some View {
        let a = context.attributes, s = context.state
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(a.operatorName.uppercased())
                        .font(.mono(9, .bold))
                        .tracking(1)
                        .foregroundStyle(Palette.caption)
                    Text(a.identifier)
                        .font(.mono(22, .heavy))
                        .foregroundStyle(Palette.ink)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(s.hasLanded ? "LANDED" : "ARRIVES IN")
                        .font(.mono(9, .bold))
                        .tracking(1)
                        .foregroundStyle(Palette.caption)
                    ArrivalCountdown(state: s)
                        .font(.mono(22, .heavy))
                        .foregroundStyle(Palette.signal)
                }
            }
            RouteBar(attributes: a, state: s)
            HStack {
                Text([s.phase, a.typeName].compactMap { $0 }.joined(separator: " · "))
                    .lineLimit(1)
                Spacer()
                Text("\(RadarFormat.altitudeText(s.altitudeFeet)) · \(RadarFormat.speedText(s.speedKnots))")
            }
            .font(.mono(11, .semibold))
            .foregroundStyle(Palette.value)
        }
        .padding(14)
    }
}

/// ORIGIN ——✈—— DEST, the bar running on a timer from take-off to landing.
private struct RouteBar: View {
    let attributes: FlightFollowAttributes
    let state: FlightFollowAttributes.ContentState

    var body: some View {
        HStack(spacing: 8) {
            endpoint(attributes.originIATA, attributes.originCity, alignment: .leading)
            Group {
                if let from = state.departedAt, let to = state.arrivesAt, from < to, !state.hasLanded {
                    ProgressView(timerInterval: from...to, countsDown: false) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                } else {
                    ProgressView(value: state.hasLanded ? 1 : 0.5)
                }
            }
            .progressViewStyle(.linear)
            .tint(Palette.signal)
            endpoint(attributes.destinationIATA, attributes.destinationCity, alignment: .trailing)
        }
    }

    private func endpoint(_ code: String?, _ city: String?, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(code ?? "—").font(.mono(16, .heavy)).foregroundStyle(Palette.route)
            if let city {
                Text(city).font(.mono(8)).foregroundStyle(Palette.caption).lineLimit(1).frame(maxWidth: 70, alignment: alignment == .leading ? .leading : .trailing)
            }
        }
    }
}

/// "1:23:05" counting down to landing, "Landed", or the miles to go when there's no time.
private struct ArrivalCountdown: View {
    let state: FlightFollowAttributes.ContentState
    var short = false

    var body: some View {
        if state.hasLanded {
            Text("Landed")
        } else if let arrives = state.arrivesAt, arrives > Date() {
            Text(timerInterval: Date()...arrives, countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        } else if let miles = state.remainingMiles {
            Text(short ? RadarFormat.distance(miles) : RadarFormat.wholeDistance(miles))
        } else {
            Text("—")
        }
    }
}
