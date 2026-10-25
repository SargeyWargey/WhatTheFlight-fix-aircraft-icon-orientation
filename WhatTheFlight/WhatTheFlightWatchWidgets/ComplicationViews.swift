//
//  ComplicationViews.swift
//  WhatTheFlightWatchWidgets
//
//  What the Watch complications draw. Each view takes its widget family rather than reading
//  the environment, so the Watch app's DEBUG gallery (`-wtf.debugScreen complications`) can
//  lay them all out on one screen; the widgets pass `\.widgetFamily` in. This file is also
//  a member of the Watch app target, for that gallery.
//

import SwiftUI
import WidgetKit
import CoreLocation

/// What a watch face remembers a complication by, so these never change.
enum WatchComplicationKind: String, CaseIterable, Sendable {
    /// The first complication, once called "Overhead": faces that show it keep it.
    case nearest = "WatchOverhead"
    case radar = "WatchRadar"
    case nextOverhead = "WatchNextOverhead"
    case identify = "WatchIdentify"

    /// The kinds that rise in the Smart Stack ahead of a close pass.
    static let passAware: [WatchComplicationKind] = [.nearest, .nextOverhead]
}

/// One timeline entry for the traffic complications (all but Identify).
struct SkyEntry: TimelineEntry {
    let date: Date
    let moment: SkyMoment?
    /// The app has never said where to watch from.
    var needsSetup = false
    /// Past the projection horizon: positions would be guesses.
    var isStale = false
    var relevance: TimelineEntryRelevance?

    var snapshot: RadarSnapshot? { isStale ? nil : moment?.snapshot }
    var nearest: SnapshotFlight? { snapshot?.flights.first }
    var inRangeCount: Int { snapshot?.inRangeCount ?? 0 }
    /// Only while it's still ahead: an offline entry can be showing an old snapshot.
    var nextPass: SkyPass? { isStale ? nil : moment?.nextPass.flatMap { $0.date > date ? $0 : nil } }
    var passing: SkyPass? { isStale ? nil : moment?.passing }

    /// When the nearest passes closest, if it's still approaching.
    var nearestPassAt: Date? {
        guard let f = nearest, let seconds = f.closestPassSeconds, let snapshot else { return nil }
        let date = snapshot.date.addingTimeInterval(seconds)
        return date > self.date ? date : nil
    }

    var status: String {
        if needsSetup { return "Open the app" }
        if isStale { return "Open to refresh" }
        if let radius = moment?.snapshot.radiusMiles { return "Clear within \(Int(radius)) mi" }
        return "Clear skies"
    }

    var statusSymbol: String {
        needsSetup ? "location.slash" : isStale ? "arrow.clockwise" : "sun.haze"
    }
}

// MARK: - Nearest Aircraft

/// The nearest aircraft: on a north-up ring at its bearing, nose along its track, with the
/// miles in the middle; the card adds who it is and when it passes closest.
struct NearestComplicationView: View {
    let entry: SkyEntry
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryCorner: cornerContent.widgetLabel { cornerLabel }
        case .accessoryInline: inline
        default: rectangular
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let f = entry.nearest {
                ComplicationDial(flight: f) {
                    VStack(spacing: -2) {
                        Text(RadarFormat.miles(f.distanceMiles))
                            .font(.mono(16, .heavy))
                            .minimumScaleFactor(0.6)
                        Text("MI")
                            .font(.mono(7, .bold))
                            .foregroundStyle(Palette.caption)
                    }
                    .lineLimit(1)
                }
            } else {
                StatusSymbol(entry: entry)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    var cornerContent: some View {
        Group {
            if let f = entry.nearest {
                ComplicationDial(flight: f, glyphShare: 0.34) { YouDot(size: 3) }
            } else {
                StatusSymbol(entry: entry)
            }
        }
        .accessibilityLabel(spoken)
    }

    var cornerLabel: Text {
        guard let f = entry.nearest else { return Text(entry.status) }
        return Text("\(f.identifier) · \(RadarFormat.miles(f.distanceMiles)) mi \(GeoMath.cardinal(f.bearing))")
    }

    private var inline: some View {
        Group {
            if let f = entry.nearest {
                Text("\(Image(systemName: f.isHelicopter ? "fan.fill" : "airplane")) \(f.identifier) \(RadarFormat.miles(f.distanceMiles)) mi \(GeoMath.cardinal(f.bearing))")
            } else {
                Text("\(Image(systemName: "airplane")) \(entry.status)")
            }
        }
        .accessibilityLabel(spoken)
    }

    private var rectangular: some View {
        GeometryReader { geo in
            HStack(spacing: 7) {
                // The little radar only where the text still has room beside it.
                if geo.size.width >= 168 {
                    ComplicationScope(snapshot: entry.snapshot, highlight: entry.nearest?.id)
                        .frame(width: min(geo.size.height, 58))
                }
                if let f = entry.nearest {
                    VStack(alignment: .leading, spacing: 1) {
                        FlightTitle(flight: f, size: 15)
                        Text("\(RadarFormat.miles(f.distanceMiles)) mi \(GeoMath.cardinal(f.bearing)) · \(RadarFormat.wholeNumber(f.altitudeFeet)) ft")
                            .font(.mono(11, .semibold))
                            .foregroundStyle(Palette.value)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        detail(f)
                            .font(.mono(10, .semibold))
                            .foregroundStyle(Palette.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    StatusCard(title: "Nearest aircraft", entry: entry)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    /// "Overhead", "◎ 1 mi in 0:48" (closest pass, ticking), "+5 more in range" or the operator.
    @ViewBuilder
    private func detail(_ f: SnapshotFlight) -> some View {
        if f.distanceMiles < 0.75 {
            Text("\(Image(systemName: "dot.radiowaves.up.forward")) OVERHEAD").foregroundStyle(Palette.signal)
        } else if let passAt = entry.nearestPassAt {
            // The countdown goes last in a Text of its own: a timer measures wider than its
            // digits and would push anything after it off the card.
            HStack(spacing: 3) {
                Text("\(Image(systemName: "scope")) \(RadarFormat.miles(f.closestPassMiles ?? f.distanceMiles)) mi in")
                    .fixedSize()
                countdownText(to: passAt, from: entry.date)
                    .monospacedDigit()
            }
        } else if entry.inRangeCount > 1 {
            Text("+\(entry.inRangeCount - 1) more in range")
        } else {
            Text(f.operatorName)
        }
    }

    private var spoken: String {
        guard let f = entry.nearest else { return entry.status }
        return "Nearest aircraft \(f.identifier), \(RadarFormat.miles(f.distanceMiles)) miles \(GeoMath.cardinal(f.bearing)), \(RadarFormat.wholeNumber(f.altitudeFeet)) feet"
    }
}

// MARK: - Sky Radar

/// Every aircraft around you on a little north-up radar, the nearest picked out.
struct SkyRadarComplicationView: View {
    let entry: SkyEntry
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryCorner: cornerContent.widgetLabel { cornerLabel }
        case .accessoryInline: inline
        default: rectangular
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if entry.snapshot == nil {
                StatusSymbol(entry: entry)
            } else {
                ComplicationScope(snapshot: entry.snapshot, highlight: entry.nearest?.id)
                    .padding(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    var cornerContent: some View {
        Group {
            if entry.snapshot == nil {
                StatusSymbol(entry: entry)
            } else {
                ComplicationScope(snapshot: entry.snapshot, highlight: entry.nearest?.id, blipShare: 0.2)
            }
        }
        .accessibilityLabel(spoken)
    }

    var cornerLabel: Text {
        entry.snapshot == nil ? Text(entry.status) : Text("\(entry.inRangeCount) in range")
    }

    private var inline: some View {
        Group {
            if entry.nearest != nil, let radius = entry.snapshot?.radiusMiles {
                Text("\(Image(systemName: "airplane")) \(entry.inRangeCount) aircraft within \(Int(radius)) mi")
            } else {
                Text("\(Image(systemName: "airplane")) \(entry.status)")
            }
        }
        .accessibilityLabel(spoken)
    }

    private var rectangular: some View {
        GeometryReader { geo in
            // Two aircraft fit on a 40 mm card, three on the bigger ones and in the Smart Stack.
            let rows = geo.size.height >= 52 ? 3 : 2
            HStack(spacing: 7) {
                ComplicationScope(snapshot: entry.snapshot, highlight: entry.nearest?.id)
                    .frame(width: min(geo.size.height, 58))
                if entry.snapshot == nil || entry.nearest == nil {
                    StatusCard(title: "Sky radar", entry: entry)
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(entry.inRangeCount)")
                                .font(.mono(13, .heavy))
                                .foregroundStyle(Palette.signal)
                                .widgetAccentable()
                            Text("IN RANGE")
                                .font(.mono(9, .heavy))
                                .tracking(0.6)
                                .foregroundStyle(Palette.caption)
                            Spacer(minLength: 2)
                            if geo.size.width >= 160, let radius = entry.snapshot?.radiusMiles {
                                Text("\(Int(radius)) MI")
                                    .font(.mono(9, .semibold))
                                    .foregroundStyle(Palette.faint)
                            }
                        }
                        ForEach(Array((entry.snapshot?.flights ?? []).prefix(rows))) { f in
                            HStack(spacing: 4) {
                                Text(f.identifier)
                                    .font(.mono(11, .bold))
                                    .foregroundStyle(f.id == entry.nearest?.id ? Palette.ink : Palette.value)
                                    .lineLimit(1)
                                Spacer(minLength: 2)
                                Text("\(RadarFormat.miles(f.distanceMiles)) \(GeoMath.cardinal(f.bearing))")
                                    .font(.mono(10, .semibold))
                                    .foregroundStyle(Palette.caption)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        guard entry.snapshot != nil else { return entry.status }
        guard let f = entry.nearest else { return entry.status }
        return "\(entry.inRangeCount) aircraft in range. Nearest \(f.identifier), \(RadarFormat.miles(f.distanceMiles)) miles \(GeoMath.cardinal(f.bearing))"
    }
}

// MARK: - Next Overhead

/// A countdown to the next aircraft passing within the overhead alert's distance: a ring
/// that drains over the last five minutes and a timer that ticks on its own, then
/// "overhead now" for a minute as it goes over.
struct NextOverheadComplicationView: View {
    let entry: SkyEntry
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryCorner: cornerContent.widgetLabel { cornerLabel }
        case .accessoryInline: inline
        default: rectangular
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let p = entry.passing {
                Circle()
                    .inset(by: 2.5)
                    .stroke(Palette.signal, lineWidth: 4)
                    .widgetAccentable()
                VStack(spacing: 1) {
                    ComplicationBlip(flight: p.flight, size: 15)
                        .foregroundStyle(Palette.signal)
                        .widgetAccentable()
                    Text("NOW").font(.mono(10, .heavy))
                }
            } else if let p = entry.nextPass {
                PassRing(pass: p)
                VStack(spacing: 1) {
                    ComplicationBlip(flight: p.flight, size: 13)
                        .foregroundStyle(Palette.signal)
                        .widgetAccentable()
                    countdownText(to: p.date, from: entry.date)
                        .font(.mono(11, .bold))
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.7)
                }
                .padding(.horizontal, 7)
            } else {
                Circle()
                    .inset(by: 2.5)
                    .stroke(Color.white.opacity(0.18), lineWidth: 4)
                if entry.snapshot == nil {
                    StatusSymbol(entry: entry)
                } else {
                    VStack(spacing: 1) {
                        Image(systemName: "airplane").font(.system(size: 11, weight: .semibold))
                        Text("--:--").font(.mono(10, .bold))
                    }
                    .foregroundStyle(Palette.caption)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    var cornerContent: some View {
        Group {
            if let p = entry.passing ?? entry.nextPass {
                ComplicationBlip(flight: p.flight, size: 22)
                    .foregroundStyle(Palette.signal)
                    .widgetAccentable()
            } else {
                Image(systemName: entry.snapshot == nil ? entry.statusSymbol : "airplane")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Palette.caption)
            }
        }
        .accessibilityLabel(spoken)
    }

    var cornerLabel: Text {
        if let p = entry.passing { return Text("\(p.flight.identifier) overhead now") }
        if let p = entry.nextPass { return Text("\(p.flight.identifier) in \(countdownText(to: p.date, from: entry.date))") }
        return Text(quiet)
    }

    /// Nothing to count down to: setup, refresh, a clear sky, or traffic that won't come close.
    private var quiet: String {
        entry.snapshot == nil || entry.inRangeCount == 0 ? entry.status : "No close passes"
    }

    private var inline: some View {
        Group {
            if let p = entry.passing {
                Text("\(Image(systemName: "airplane")) \(p.flight.identifier) overhead now")
            } else if let p = entry.nextPass {
                Text("\(Image(systemName: "airplane")) \(p.flight.identifier) in \(countdownText(to: p.date, from: entry.date))")
            } else {
                Text("\(Image(systemName: "airplane")) \(quiet)")
            }
        }
        .accessibilityLabel(spoken)
    }

    private var rectangular: some View {
        GeometryReader { geo in
            let roomy = geo.size.height >= 54
            VStack(alignment: .leading, spacing: roomy ? 2 : 1) {
                if let p = entry.passing {
                    header("OVERHEAD NOW", accent: true) {
                        Text("\(RadarFormat.miles(p.flight.distanceMiles)) mi \(GeoMath.cardinal(p.flight.bearing))")
                            .font(.mono(13, .heavy))
                            .foregroundStyle(Palette.signal)
                            .widgetAccentable()
                    }
                    FlightTitle(flight: p.flight, size: 14, showsGlyph: true)
                    Text("Look up · \(RadarFormat.wholeNumber(p.flight.altitudeFeet)) ft")
                        .font(.mono(10, .semibold))
                        .foregroundStyle(Palette.caption)
                } else if let p = entry.nextPass {
                    header("NEXT OVERHEAD", accent: false) {
                        countdownText(to: p.date, from: entry.date)
                            .font(.mono(15, .heavy))
                            .monospacedDigit()
                            .foregroundStyle(Palette.signal)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 58, alignment: .trailing)
                            .widgetAccentable()
                    }
                    FlightTitle(flight: p.flight, size: 14, showsGlyph: true)
                    if roomy {
                        Text("\(p.miles < 0.5 ? "Right overhead" : "Within \(RadarFormat.miles(p.miles)) mi") · \(RadarFormat.wholeNumber(p.flight.altitudeFeet)) ft")
                            .font(.mono(10, .semibold))
                            .foregroundStyle(Palette.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    ProgressView(timerInterval: p.date.addingTimeInterval(-SkyPass.ringWindow)...p.date, countsDown: true) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .progressViewStyle(.linear)
                    .tint(Palette.signal)
                    .widgetAccentable()
                } else {
                    header("NEXT OVERHEAD", accent: false) { EmptyView() }
                    Text(entry.snapshot == nil || entry.inRangeCount == 0 ? entry.status : "Nothing passing close")
                        .font(.mono(13, .heavy))
                        .foregroundStyle(Palette.ink)
                        .widgetAccentable()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if entry.inRangeCount > 0 {
                        Text("\(entry.inRangeCount) in range")
                            .font(.mono(10, .semibold))
                            .foregroundStyle(Palette.caption)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private func header<Trailing: View>(_ title: String, accent: Bool, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(title)
                .font(.mono(9, .heavy))
                .tracking(0.6)
                .foregroundStyle(accent ? Palette.signal : Palette.caption)
                .widgetAccentable(accent)
                .lineLimit(1)
            Spacer(minLength: 2)
            trailing()
        }
    }

    private var spoken: String {
        if let p = entry.passing {
            return "\(p.flight.identifier) overhead now, \(RadarFormat.miles(p.flight.distanceMiles)) miles \(GeoMath.cardinal(p.flight.bearing))"
        }
        if let p = entry.nextPass {
            let seconds = max(0, p.date.timeIntervalSince(entry.date))
            return "\(p.flight.identifier) passes overhead in \(RadarFormat.countdown(seconds))"
        }
        return quiet
    }
}

// MARK: - Identify

/// One tap from the face to Identify: a hand pointing up at an aircraft.
struct IdentifyComplicationView: View {
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryCorner: cornerContent.widgetLabel { cornerLabel }
        case .accessoryInline:
            Text("\(Image(systemName: "hand.point.up.left.fill")) Identify a plane")
        default:
            ZStack {
                AccessoryWidgetBackground()
                PointingArt()
                    .padding(6)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Identify a plane")
        }
    }

    var cornerContent: some View {
        PointingArt()
            .accessibilityLabel("Identify a plane")
    }

    var cornerLabel: Text { Text("Identify") }
}

/// A hand pointing at an aircraft up and to its left.
struct PointingArt: View {
    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                Image(systemName: "hand.point.up.left.fill")
                    .font(.system(size: side * 0.56, weight: .semibold))
                    .offset(x: side * 0.14, y: side * 0.16)
                AircraftGlyph(silhouette: .airliner, size: side * 0.48, spinsRotor: false)
                    .rotationEffect(.degrees(-60))
                    .foregroundStyle(Palette.signal)
                    .offset(x: -side * 0.24, y: -side * 0.26)
                    .widgetAccentable()
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

// MARK: - Pieces

/// The complications' little radar, north up: a ring at the radar's radius and a dashed one
/// at half, a red north tick, you in the middle, and each aircraft where it is with its nose
/// along its track. `highlight` (usually the nearest) is drawn larger, in the accent.
struct ComplicationScope: View {
    let snapshot: RadarSnapshot?
    var highlight: String?
    /// Silhouette size as a share of the scope; under about 7 pt they become dots.
    var blipShare: CGFloat = 0.17

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let blip = side * blipShare
            let radius = side / 2 - blip * 0.62
            let line = max(0.8, side * 0.02)
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.32), lineWidth: line)
                    .frame(width: radius * 2, height: radius * 2)
                Circle()
                    .stroke(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: line, dash: [line * 1.5, line * 2.5]))
                    .frame(width: radius, height: radius)
                NorthTick(side: side, line: line)
                    .offset(y: -radius)
                YouDot(size: line * 3)
                ForEach(others) { f in
                    ComplicationBlip(flight: f, size: blip)
                        .foregroundStyle(f.blipColor)
                        .offset(position(of: f, radius: radius))
                }
                if let f = highlighted {
                    ComplicationBlip(flight: f, size: blip * 1.4)
                        .foregroundStyle(Palette.signal)
                        .offset(position(of: f, radius: radius))
                        .widgetAccentable()
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private var flights: [SnapshotFlight] { snapshot?.flights ?? [] }
    private var highlighted: SnapshotFlight? { flights.first { $0.id == highlight } }
    /// Farthest first, so nearer aircraft draw on top.
    private var others: [SnapshotFlight] { flights.filter { $0.id != highlight }.reversed() }

    private func position(of f: SnapshotFlight, radius: CGFloat) -> CGSize {
        let share = min(1, f.distanceMiles / max(0.1, snapshot?.radiusMiles ?? 1))
        return compassOffset(f.bearing, CGFloat(share) * radius)
    }
}

/// A ring with north at the top and one aircraft on it at its compass bearing, nose along
/// its track, with `centre` inside.
struct ComplicationDial<Centre: View>: View {
    let flight: SnapshotFlight
    var glyphShare: CGFloat
    let centre: Centre

    init(flight: SnapshotFlight, glyphShare: CGFloat = 0.26, @ViewBuilder centre: () -> Centre) {
        self.flight = flight
        self.glyphShare = glyphShare
        self.centre = centre()
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let glyph = side * glyphShare
            let radius = side / 2 - glyph * 0.55
            let line = max(1, side * 0.03)
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.25), lineWidth: line)
                    .frame(width: radius * 2, height: radius * 2)
                NorthTick(side: side, line: line)
                    .offset(y: -radius)
                centre
                    .frame(width: max(1, (radius - glyph * 0.5) * 1.9))
                ComplicationBlip(flight: flight, size: glyph)
                    .foregroundStyle(Palette.signal)
                    .offset(compassOffset(flight.bearing, radius))
                    .widgetAccentable()
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// The ring that drains over the last five minutes before a pass, on its own between entries.
struct PassRing: View {
    let pass: SkyPass

    var body: some View {
        ProgressView(timerInterval: pass.date.addingTimeInterval(-SkyPass.ringWindow)...pass.date, countsDown: true) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .progressViewStyle(.circular)
        .tint(Palette.signal)
        .widgetAccentable()
    }
}

/// An aircraft at complication size: its silhouette with the nose along its track, or a dot
/// when that's too small to read (or an older snapshot doesn't say).
struct ComplicationBlip: View {
    let flight: SnapshotFlight
    let size: CGFloat

    var body: some View {
        if let track = flight.track, size >= 7 {
            AircraftGlyph(silhouette: flight.silhouette ?? (flight.isHelicopter ? .helicopter : .airliner),
                          size: size, spinsRotor: false)
                .rotationEffect(.degrees(track))
        } else {
            Circle()
                .frame(width: max(3, size * 0.45), height: max(3, size * 0.45))
        }
    }
}

/// The red north marker on a ring.
struct NorthTick: View {
    let side: CGFloat
    let line: CGFloat

    var body: some View {
        Capsule()
            .fill(Palette.signal)
            .frame(width: line * 1.8, height: side * 0.1)
            .widgetAccentable()
    }
}

struct YouDot: View {
    let size: CGFloat

    var body: some View {
        Circle().fill(Color.white).frame(width: size, height: size)
    }
}

/// Identifier, any notable mark and the route (or type), shrinking the route first.
struct FlightTitle: View {
    let flight: SnapshotFlight
    let size: CGFloat
    var showsGlyph = false

    var body: some View {
        HStack(spacing: 4) {
            if showsGlyph {
                ComplicationBlip(flight: flight, size: size * 0.9)
                    .foregroundStyle(flight.blipColor)
            }
            Text(flight.identifier)
                .font(.mono(size, .heavy))
                .foregroundStyle(Palette.ink)
                .widgetAccentable()
                .lineLimit(1)
                .layoutPriority(1)
            if let tag = flight.notableTag {
                Image(systemName: tag.symbol)
                    .font(.system(size: size * 0.65, weight: .bold))
                    .foregroundStyle(Palette.color(for: tag))
            }
            if let line = flight.route ?? flight.typeName {
                Text(line)
                    .font(.mono(size * 0.68, .bold))
                    .foregroundStyle(flight.route == nil ? Palette.caption : Palette.route)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
    }
}

/// The card when there's no aircraft to show: setup, refresh or a clear sky.
struct StatusCard: View {
    let title: String
    let entry: SkyEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.mono(9, .heavy))
                .tracking(0.6)
                .foregroundStyle(Palette.caption)
            Label(entry.status, systemImage: entry.statusSymbol)
                .font(.mono(12, .bold))
                .foregroundStyle(Palette.ink)
                .widgetAccentable()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StatusSymbol: View {
    let entry: SkyEntry

    var body: some View {
        Image(systemName: entry.statusSymbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(entry.needsSetup || entry.isStale ? Palette.value : Palette.caption)
    }
}

/// A countdown that ticks on its own between timeline entries. Clamped, so an entry showing
/// an older snapshot never builds a backwards range.
func countdownText(to target: Date, from date: Date) -> Text {
    Text(timerInterval: min(date, target)...target, countsDown: true)
}

/// Where a bearing and distance from the centre land, north up.
func compassOffset(_ bearing: Double, _ distance: CGFloat) -> CGSize {
    CGSize(width: CGFloat(sin(bearing.radians)) * distance, height: -CGFloat(cos(bearing.radians)) * distance)
}

extension SnapshotFlight {
    var blipColor: Color { notableTag.map(Palette.color(for:)) ?? Palette.blip }
}

// MARK: - Samples

/// Made-up traffic around Atlanta for placeholders, previews and the DEBUG gallery: a
/// nearest aircraft, a 737 about to pass almost overhead, a helicopter and a C-17.
enum ComplicationSamples {
    static let observer = CLLocationCoordinate2D(latitude: 33.749, longitude: -84.388)

    static func flights(at date: Date) -> [Flight] {
        func flight(_ id: String, _ number: String?, _ callsign: String, _ airline: String?, _ type: String,
                    _ route: (String, String)?, miles: Double, bearing: Double, track: Double, knots: Int,
                    feet: Int) -> Flight {
            let p = GeoMath.destination(from: observer, bearingDegrees: bearing, distanceMiles: miles)
            return Flight(id: id, hex: nil, latitude: p.latitude, longitude: p.longitude, track: track,
                          altitudeFeet: feet, groundSpeedKnots: knots, verticalRateFPM: 0, squawk: nil,
                          typeCode: type, registration: nil, originIATA: route?.0, destinationIATA: route?.1,
                          flightNumber: number, callsign: callsign, airlineICAO: airline, isOnGround: false,
                          positionTime: date)
        }
        return [
            flight("s1", "DL570", "DAL570", "DAL", "B752", ("SFO", "ATL"), miles: 4, bearing: 40, track: 259, knots: 230, feet: 9_500),
            flight("s2", "WN2533", "SWA2533", "SWA", "B737", ("BNA", "ATL"), miles: 7, bearing: 300, track: 125, knots: 300, feet: 11_800),
            flight("s3", nil, "N911LF", nil, "EC35", nil, miles: 5, bearing: 235, track: 20, knots: 110, feet: 1_200),
            flight("s4", "AA1385", "AAL1385", "AAL", "A321", ("CLT", "DFW"), miles: 9, bearing: 200, track: 250, knots: 420, feet: 34_000),
            flight("s5", "EK211", "UAE211", "UAE", "A388", ("DXB", "IAH"), miles: 12, bearing: 130, track: 260, knots: 480, feet: 39_000),
            flight("s6", nil, "RCH402", nil, "C17", nil, miles: 14, bearing: 345, track: 160, knots: 400, feet: 24_000),
        ]
    }

    static func moments(start: Date = Date()) -> [SkyMoment] {
        NearbyTraffic.timeline(flights(at: start), observer: observer, radiusMiles: 15, overheadMiles: 1.5,
                               placeName: "Atlanta", start: start, count: 6, step: 60)
    }

    static var entry: SkyEntry {
        let moment = moments().first
        return SkyEntry(date: moment?.date ?? Date(), moment: moment)
    }

    static var passingEntry: SkyEntry {
        let moment = moments().first { $0.passing != nil } ?? moments().first
        return SkyEntry(date: moment?.date ?? Date(), moment: moment)
    }

    static var clearEntry: SkyEntry {
        SkyEntry(date: Date(), moment: SkyMoment(snapshot: RadarSnapshot(placeName: "Here", radiusMiles: 10, contacts: [])))
    }

    static var setupEntry: SkyEntry { SkyEntry(date: Date(), moment: nil, needsSetup: true) }
}
