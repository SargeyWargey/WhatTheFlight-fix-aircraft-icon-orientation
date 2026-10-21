//
//  WatchNotification.swift
//  WhatTheFlightWatch
//
//  The long-look for overhead / notable alerts the iPhone posts during Sky Watch: a small
//  compass dial pointing where to look, the flight, and a live countdown to its closest pass.
//  "Find in the Sky" (the iPhone's category action) opens Point & Find here.
//

import SwiftUI
import UserNotifications
import WatchKit

final class TrafficNotificationController: WKUserNotificationHostingController<TrafficNotificationView> {
    private var title = ""
    private var message = ""
    private var flight: SnapshotFlight?
    private var postedAt = Date()

    override var body: TrafficNotificationView {
        TrafficNotificationView(title: title, message: message, flight: flight, postedAt: postedAt)
    }

    override func didReceive(_ notification: UNNotification) {
        let content = notification.request.content
        title = content.title
        message = content.body
        postedAt = notification.date
        flight = TrafficNotification.flight(from: content.userInfo)
    }
}

struct TrafficNotificationView: View {
    let title: String
    let message: String
    let flight: SnapshotFlight?
    let postedAt: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let f = flight {
                HStack(alignment: .center, spacing: 10) {
                    BearingDial(bearing: f.bearing, isHelicopter: f.isHelicopter)
                        .frame(width: 54, height: 54)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(f.identifier)
                            .font(.mono(18, .heavy))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        if let route = f.route {
                            Text(route).font(.mono(12, .bold)).foregroundStyle(Palette.route)
                        }
                        Text("\(RadarFormat.miles(f.distanceMiles)) mi \(GeoMath.cardinal(f.bearing))")
                            .font(.mono(11, .semibold))
                            .foregroundStyle(Palette.value)
                    }
                }
                if let badge = f.notableBadge, let tag = f.notableTag {
                    Text(badge).font(.mono(10, .heavy)).foregroundStyle(Palette.color(for: tag))
                }
                Text([f.typeName, "\(RadarFormat.wholeNumber(f.altitudeFeet)) ft"].compactMap { $0 }.joined(separator: " · "))
                    .font(.mono(10))
                    .foregroundStyle(Palette.caption)
                if let seconds = f.closestPassSeconds {
                    let passAt = postedAt.addingTimeInterval(seconds)
                    if passAt > Date() {
                        HStack(spacing: 4) {
                            Image(systemName: "scope")
                            Text("Closest in")
                            Text(timerInterval: Date()...passAt, countsDown: true).monospacedDigit()
                        }
                        .font(.mono(11, .semibold))
                        .foregroundStyle(Palette.signal)
                    }
                }
            } else {
                Text(title).font(.mono(14, .heavy)).foregroundStyle(Palette.ink)
                Text(message).font(.mono(11)).foregroundStyle(Palette.value)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// North-up compass dial with an aircraft on the rim at its bearing.
struct BearingDial: View {
    let bearing: Double
    var isHelicopter = false

    var body: some View {
        GeometryReader { geo in
            let r = min(geo.size.width, geo.size.height) / 2
            ZStack {
                Circle().stroke(Palette.ink.opacity(0.35), lineWidth: 1)
                Circle().fill(Palette.ink.opacity(0.08))
                Text("N")
                    .font(.mono(8, .bold))
                    .foregroundStyle(Palette.signal)
                    .position(x: r, y: 6)
                Image(systemName: "location.north.fill")
                    .font(.system(size: r * 0.5, weight: .bold))
                    .foregroundStyle(Palette.signal)
                    .rotationEffect(.degrees(bearing))
                    .position(x: r, y: r)
                Image(systemName: isHelicopter ? "fan.fill" : "airplane")
                    .font(.system(size: r * 0.32, weight: .semibold))
                    .foregroundStyle(Palette.blip)
                    .position(x: r + sin(bearing.radians) * r * 0.78, y: r - cos(bearing.radians) * r * 0.78)
            }
        }
        .accessibilityLabel("Look \(GeoMath.cardinal(bearing))")
    }
}
