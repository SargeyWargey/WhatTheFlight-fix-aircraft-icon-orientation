//
//  TVLogbookView.swift
//  WhatTheFlight
//
//  The logbook on the big screen: stats, records and badges up top, then every sighting by
//  day. Everything is clickable: a record or a sighting opens that sighting, a badge opens
//  its own page with the aircraft that earned it. Focus starts at the top, on the records.
//

#if os(tvOS)
import SwiftUI

struct TVLogbookView: View {
    let logbook: Logbook
    let showTopography: Bool
    var isLive: (String) -> Bool = { _ in false }
    let onPick: (String) -> Void

    @State private var confirmClear = false
    @State private var shownBadge: Achievement?
    @State private var shownSighting: Sighting?
    @FocusState private var focus: FocusTarget?

    enum FocusTarget: Hashable {
        case record(String)
        case badge(String)
    }

    var body: some View {
        let stats = LogbookStats(logbook.sightings)
        let achievements = Achievement.all(for: logbook.sightings)
        ZStack {
            RadarBackdrop(showTopography: showTopography, showSweep: false, isActive: true)
                .ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    Text("Logbook")
                        .font(.mono(56, .heavy))
                        .foregroundStyle(Palette.ink)

                    if logbook.isEmpty {
                        Text("Every aircraft that comes inside your radius is logged here automatically.")
                            .font(.mono(28))
                            .foregroundStyle(Palette.caption)
                    } else {
                        HStack(spacing: 20) {
                            LogbookStatTile(title: "Spotted", value: RadarFormat.wholeNumber(stats.total), scale: 2)
                            LogbookStatTile(title: "Today", value: RadarFormat.wholeNumber(stats.today), scale: 2)
                            LogbookStatTile(title: "Airframes", value: RadarFormat.wholeNumber(stats.uniqueAirframes), scale: 2)
                            LogbookStatTile(title: "Types", value: RadarFormat.wholeNumber(stats.uniqueTypes), scale: 2)
                            LogbookStatTile(title: "Airlines", value: RadarFormat.wholeNumber(stats.uniqueAirlines), scale: 2)
                        }

                        TVSectionHeader(title: "Records")
                        HStack(spacing: 24) {
                            if let s = stats.closest { record("Closest pass", s.closestText, s) }
                            if let s = stats.highest { record("Highest", "\(RadarFormat.wholeNumber(s.altitudeAtClosestFeet)) ft", s) }
                            if let s = stats.fastest { record("Fastest", "\(RadarFormat.wholeNumber(s.speedKnots)) kts", s) }
                        }
                        .focusSection()

                        TVSectionHeader(title: "Badges · \(achievements.filter(\.isUnlocked).count) of \(achievements.count) · click one for details")
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 24), count: 7), spacing: 28) {
                            ForEach(achievements) { achievement in
                                Button {
                                    shownBadge = achievement
                                } label: {
                                    AchievementBadge(achievement: achievement, scale: 1.8)
                                        .frame(maxWidth: .infinity, minHeight: 200)
                                }
                                .buttonStyle(TVCardButtonStyle())
                                .focused($focus, equals: .badge(achievement.id))
                            }
                        }
                        .focusSection()

                        ForEach(LogbookGrouping.byDay(logbook.recent), id: \.day) { group in
                            TVSectionHeader(title: "\(LogbookGrouping.title(for: group.day)) · \(group.items.count)")
                            ForEach(group.items) { row($0) }
                        }

                        TVSectionHeader(title: "Start over")
                        TVValueRow(title: "Clear Logbook", subtitle: "Remove every sighting and badge on this Apple TV", value: "", symbol: "trash") {
                            confirmClear = true
                        }
                    }
                }
                .padding(.horizontal, 120)
                .padding(.vertical, 60)
            }
            .defaultScrollAnchor(.top)
        }
        // Start at the top (the records) rather than letting focus fall to the first sighting.
        .defaultFocus($focus, stats.closest != nil ? .record("Closest pass") : achievements.first.map { .badge($0.id) })
        #if DEBUG
        .task {
            // `-wtf.debugBadge <id>` opens a badge's page (screenshots).
            guard let id = UserDefaults.standard.string(forKey: "wtf.debugBadge") else { return }
            try? await Task.sleep(for: .seconds(1))
            shownBadge = Achievement.all(for: logbook.sightings).first { $0.id == id }
        }
        #endif
        .confirmationDialog("Clear the whole logbook?", isPresented: $confirmClear) {
            Button("Clear Logbook", role: .destructive) { logbook.clear() }
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(item: $shownBadge) { badge in
            TVAchievementDetailView(achievement: badge, showTopography: showTopography, isLive: isLive) { sighting in
                shownBadge = nil
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(450))
                    shownSighting = sighting
                }
            }
        }
        .fullScreenCover(item: $shownSighting) { sighting in
            TVSightingDetailView(sighting: sighting, logbook: logbook, showTopography: showTopography,
                                 isLive: isLive(sighting.id)) {
                shownSighting = nil
                onPick(sighting.id)
            }
        }
    }

    private func record(_ title: String, _ value: String, _ s: Sighting) -> some View {
        Button {
            shownSighting = s
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).radarCaptionTV()
                Text(value)
                    .font(.mono(40, .bold))
                    .foregroundStyle(Palette.ink)
                Text("\(s.displayIdentifier) · \(s.typeName ?? s.typeCode ?? "Aircraft")")
                    .font(.mono(20))
                    .foregroundStyle(Palette.caption)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(26)
        }
        .buttonStyle(TVCardButtonStyle())
        .focused($focus, equals: .record(title))
    }

    private func row(_ s: Sighting) -> some View {
        Button {
            shownSighting = s
        } label: {
            TVSightingRow(sighting: s, isLive: isLive(s.id))
        }
        .buttonStyle(TVRowButtonStyle())
    }
}

/// A card that keeps its own colours and lifts with an ink outline when focused, so badge
/// rings and record values stay readable.
struct TVCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration)
    }

    private struct Styled: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Palette.paperShade.opacity(isFocused ? 0.75 : 0.35))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Palette.ink, lineWidth: isFocused ? 4 : 0)
                )
                .scaleEffect(configuration.isPressed ? 0.97 : (isFocused ? 1.06 : 1))
                .shadow(color: .black.opacity(isFocused ? 0.3 : 0), radius: 22, y: 12)
                .animation(.snappy(duration: 0.18), value: isFocused)
        }
    }
}

private struct TVSightingRow: View {
    let sighting: Sighting
    let isLive: Bool
    /// Narrow column (badge page): no "ON RADAR" label, shorter text.
    var compact = false
    @Environment(\.tvRowFocused) private var focused

    /// Time for today's sightings, the date otherwise.
    private var when: String {
        Calendar.current.isDateInToday(sighting.firstSeen)
            ? sighting.firstSeen.formatted(date: .omitted, time: .shortened)
            : sighting.firstSeen.formatted(.dateTime.month(.abbreviated).day())
    }

    var body: some View {
        let s = sighting
        HStack(spacing: 28) {
            Image(systemName: s.kind == .helicopter ? "fan.fill" : "airplane")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(focused ? .white : (isLive ? Palette.signal : Palette.blip))
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 16) {
                    Text(s.displayIdentifier)
                        .font(.mono(30, .bold))
                        .lineLimit(1)
                        .fixedSize()
                    if let route = s.routeText {
                        Text(route)
                            .font(.mono(22, .semibold))
                            .foregroundStyle(focused ? .white.opacity(0.9) : Palette.route)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    if let tag = s.tags.first {
                        Image(systemName: tag.symbol)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(focused ? .white : Palette.color(for: tag))
                    }
                    if isLive && !compact {
                        Text("ON RADAR")
                            .font(.mono(16, .heavy))
                            .tracking(2)
                            .foregroundStyle(focused ? .white : Palette.signal)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                Text(s.summaryLine)
                    .font(.mono(20))
                    .foregroundStyle(focused ? .white.opacity(0.8) : Palette.caption)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(s.closestText).font(.mono(28, .bold))
                Text(when)
                    .font(.mono(20))
                    .foregroundStyle(focused ? .white.opacity(0.8) : Palette.caption)
            }
            .lineLimit(1)
            .fixedSize()
        }
    }
}

// MARK: - Badge

struct TVAchievementDetailView: View {
    let achievement: Achievement
    let showTopography: Bool
    var isLive: (String) -> Bool = { _ in false }
    let onPick: (Sighting) -> Void

    var body: some View {
        let a = achievement
        ZStack {
            RadarBackdrop(showTopography: showTopography, showSweep: false, isActive: true)
                .ignoresSafeArea()
            HStack(alignment: .top, spacing: 80) {
                VStack(alignment: .leading, spacing: 24) {
                    AchievementBadge(achievement: a, scale: 4.2, showsTitle: false)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    Text(a.isUnlocked ? "UNLOCKED" : "LOCKED")
                        .font(.mono(20, .heavy))
                        .tracking(4)
                        .foregroundStyle(a.isUnlocked ? Palette.notable : Palette.caption)
                    Text(a.title)
                        .font(.mono(60, .heavy))
                        .foregroundStyle(Palette.ink)
                    Text(a.detail)
                        .font(.mono(28, .semibold))
                        .foregroundStyle(Palette.value)
                    Text(a.about)
                        .font(.mono(24))
                        .foregroundStyle(Palette.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    AchievementProgress(achievement: a, scale: 2)
                        .padding(.top, 10)
                }
                .frame(width: 700)

                VStack(alignment: .leading, spacing: 18) {
                    TVSectionHeader(title: a.examples.isEmpty ? "No aircraft yet" : "Aircraft that count · \(a.progress)")
                    if a.examples.isEmpty {
                        Text("Keep the radar running — anything that qualifies shows up here.")
                            .font(.mono(24))
                            .foregroundStyle(Palette.caption)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 16) {
                                ForEach(a.examples) { s in
                                    Button { onPick(s) } label: {
                                        TVSightingRow(sighting: s, isLive: isLive(s.id), compact: true)
                                    }
                                    .buttonStyle(TVRowButtonStyle())
                                }
                                if a.progress > a.examples.count {
                                    Text("Showing the latest \(a.examples.count) of \(a.progress)")
                                        .font(.mono(20))
                                        .foregroundStyle(Palette.caption)
                                        .padding(.leading, 6)
                                }
                            }
                            .padding(.vertical, 20)
                            .padding(.horizontal, 10)
                        }
                        .scrollClipDisabled()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .focusSection()
            }
            .padding(.horizontal, 100)
            .padding(.vertical, 70)
        }
    }
}

// MARK: - Sighting

struct TVSightingDetailView: View {
    let sighting: Sighting
    let logbook: Logbook
    let showTopography: Bool
    let isLive: Bool
    let onTrack: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let s = sighting
        let others = logbook.recent.filter { $0.airframe != nil && $0.airframe == s.airframe && $0.id != s.id }
        ZStack {
            RadarBackdrop(showTopography: showTopography, showSweep: false, isActive: true)
                .ignoresSafeArea()
            HStack(alignment: .top, spacing: 80) {
                VStack(alignment: .leading, spacing: 18) {
                    if let tag = s.tags.first {
                        Label(tag.rawValue.uppercased(), systemImage: tag.symbol)
                            .font(.mono(22, .heavy))
                            .foregroundStyle(Palette.color(for: tag))
                            .labelStyle(TVLabelStyle())
                    }
                    Text(s.operatorName).radarCaptionTV()
                    Text(s.displayIdentifier)
                        .font(.mono(96, .heavy))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    if let route = s.routeText {
                        Text(route)
                            .font(.mono(44, .bold))
                            .foregroundStyle(Palette.route)
                    }
                    if let type = s.typeName ?? s.typeCode {
                        Text(type)
                            .font(.mono(28, .medium))
                            .foregroundStyle(Palette.caption)
                    }
                    HStack(spacing: 24) {
                        if isLive {
                            Button("Show on Radar", action: onTrack)
                                .buttonStyle(TVPillButtonStyle(prominent: true))
                        }
                        Button("Close") { dismiss() }
                            .buttonStyle(TVPillButtonStyle(prominent: false))
                    }
                    .padding(.top, 20)
                }
                .frame(width: 700, alignment: .leading)

                VStack(alignment: .leading, spacing: 20) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: 3), spacing: 20) {
                        fact("First seen", s.firstSeen.formatted(date: .abbreviated, time: .shortened))
                        fact("Last seen", s.lastSeen.formatted(date: .omitted, time: .shortened))
                        fact("Closest pass", s.closestText)
                        fact("Altitude then", "\(RadarFormat.wholeNumber(s.altitudeAtClosestFeet)) ft")
                        fact("Speed then", "\(RadarFormat.wholeNumber(s.speedKnots)) kts")
                        fact("Registration", s.registration ?? "—")
                        fact("Callsign", s.callsign ?? "—")
                        fact("Type", s.typeCode ?? "—")
                        fact("ICAO hex", s.hex ?? "—")
                    }
                    if !others.isEmpty {
                        TVSectionHeader(title: "This airframe, other times · \(others.count)")
                        ForEach(others.prefix(6)) { o in
                            Text("\(o.firstSeen.formatted(date: .abbreviated, time: .shortened))   \([o.displayIdentifier, o.routeText].compactMap { $0 }.joined(separator: " "))")
                                .font(.mono(22))
                                .foregroundStyle(Palette.value)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 100)
            .padding(.vertical, 70)
        }
    }

    private func fact(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).radarCaptionTV()
            Text(value)
                .font(.mono(26, .semibold))
                .foregroundStyle(Palette.value)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(Palette.paperShade.opacity(0.35), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
#endif
