//
//  LogbookView.swift
//  WhatTheFlight
//
//  Every aircraft you've had inside your radius: stats, records, badges and the full
//  history, grouped by day.
//

#if os(iOS) || os(tvOS)
import SwiftUI

/// A badge: its symbol inside a progress ring, greyed out until unlocked.
struct AchievementBadge: View {
    let achievement: Achievement
    var scale: CGFloat = 1
    var showsTitle = true

    var body: some View {
        VStack(spacing: 6 * scale) {
            ZStack {
                Circle()
                    .stroke(Palette.ink.opacity(0.12), lineWidth: 4 * scale)
                Circle()
                    .trim(from: 0, to: achievement.fraction)
                    .stroke(achievement.isUnlocked ? Palette.notable : Palette.route, style: StrokeStyle(lineWidth: 4 * scale, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: achievement.symbol)
                    .font(.system(size: 20 * scale, weight: .semibold))
                    .foregroundStyle(achievement.isUnlocked ? Palette.notable : Palette.faint)
            }
            .frame(width: 54 * scale, height: 54 * scale)
            if showsTitle {
                titleAndProgress
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(achievement.title), \(achievement.isUnlocked ? "unlocked" : "\(achievement.progress) of \(achievement.target)"). \(achievement.detail)")
    }

    @ViewBuilder
    private var titleAndProgress: some View {
            Text(achievement.title)
                .font(.mono(10 * scale, .bold))
                .foregroundStyle(achievement.isUnlocked ? Palette.value : Palette.caption)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            if !achievement.isUnlocked && achievement.target > 1 {
                Text("\(min(achievement.progress, achievement.target))/\(achievement.target)")
                    .font(.mono(9 * scale))
                    .foregroundStyle(Palette.faint)
            }
    }
}

/// "12 of 25" with a bar, plus who unlocked it and when.
struct AchievementProgress: View {
    let achievement: Achievement
    var scale: CGFloat = 1

    var body: some View {
        let a = achievement
        VStack(alignment: .leading, spacing: 8 * scale) {
            HStack {
                Text("Progress").font(.mono(11 * scale, .semibold)).textCase(.uppercase).foregroundStyle(Palette.caption)
                Spacer()
                Text("\(min(a.progress, a.target)) of \(a.target)")
                    .font(.mono(13 * scale, .bold))
                    .foregroundStyle(a.isUnlocked ? Palette.notable : Palette.ink)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.ink.opacity(0.12))
                    Capsule().fill(a.isUnlocked ? Palette.notable : Palette.route)
                        .frame(width: max(6 * scale, geo.size.width * a.fraction))
                }
            }
            .frame(height: 8 * scale)
            if let by = a.unlockedBy {
                Text("Unlocked \(by.firstSeen.formatted(date: .abbreviated, time: .shortened)) by \(by.displayIdentifier)\(by.typeName.map { " · \($0)" } ?? "")")
                    .font(.mono(12 * scale))
                    .foregroundStyle(Palette.value)
            } else if a.target > a.progress {
                Text("\(a.target - a.progress) to go")
                    .font(.mono(12 * scale))
                    .foregroundStyle(Palette.caption)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct LogbookStatTile: View {
    let title: String
    let value: String
    var scale: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 4 * scale) {
            Text(title)
                .font(.mono(10 * scale, .semibold))
                .tracking(1.4 * scale)
                .textCase(.uppercase)
                .foregroundStyle(Palette.caption)
            Text(value)
                .font(.mono(22 * scale, .bold))
                .foregroundStyle(Palette.ink)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12 * scale)
        .background(Palette.paperShade.opacity(0.35), in: RoundedRectangle(cornerRadius: 14 * scale, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

extension Sighting {
    var routeText: String? {
        guard let from = originIATA, let to = destinationIATA else { return nil }
        return "\(from) → \(to)"
    }

    var summaryLine: String {
        [operatorName, typeName ?? typeCode].compactMap { $0 }.joined(separator: " · ")
    }

    var closestText: String { "\(RadarFormat.miles(closestMiles)) mi" }

    /// "6 min", "Under a min".
    var inRangeText: String {
        let minutes = Int((lastSeen.timeIntervalSince(firstSeen) / 60).rounded())
        return minutes < 1 ? "Under a min" : "\(minutes) min"
    }
}

enum LogbookGrouping {
    /// Sightings newest first, grouped by calendar day.
    static func byDay(_ sightings: [Sighting], calendar: Calendar = .current) -> [(day: Date, items: [Sighting])] {
        let groups = Dictionary(grouping: sightings) { calendar.startOfDay(for: $0.firstSeen) }
        return groups.keys.sorted(by: >).map { day in
            (day, groups[day]!.sorted { $0.firstSeen > $1.firstSeen })
        }
    }

    static func title(for day: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}
#endif

#if os(iOS)
struct LogbookView: View {
    let logbook: Logbook
    /// Sends a sighting that's still on the radar to the centre.
    var onTrack: ((String) -> Void)?
    var isLive: (String) -> Bool = { _ in false }

    @State private var query = ""
    @State private var confirmClear = false

    private var filtered: [Sighting] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let all = logbook.recent
        guard !q.isEmpty else { return all }
        return all.filter { s in
            [s.displayIdentifier, s.callsign, s.registration, s.typeCode, s.typeName, s.operatorName, s.originIATA, s.destinationIATA]
                .contains { $0?.lowercased().contains(q) == true }
        }
    }

    var body: some View {
        let stats = LogbookStats(logbook.sightings)
        let achievements = Achievement.all(for: logbook.sightings)
        List {
            if logbook.isEmpty {
                ContentUnavailableView("No sightings yet", systemImage: "book.closed",
                                       description: Text("Every aircraft that comes inside your radius is logged here automatically."))
                    .listRowBackground(Color.clear)
            } else if query.isEmpty {
                Section {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        LogbookStatTile(title: "Spotted", value: RadarFormat.wholeNumber(stats.total))
                        LogbookStatTile(title: "Today", value: RadarFormat.wholeNumber(stats.today))
                        LogbookStatTile(title: "Airframes", value: RadarFormat.wholeNumber(stats.uniqueAirframes))
                        LogbookStatTile(title: "Types", value: RadarFormat.wholeNumber(stats.uniqueTypes))
                        LogbookStatTile(title: "Airlines", value: RadarFormat.wholeNumber(stats.uniqueAirlines))
                        LogbookStatTile(title: "Notable", value: RadarFormat.wholeNumber(stats.notable))
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    .listRowBackground(Color.clear)
                }

                Section("Records") {
                    if let s = stats.closest { record("Closest pass", s.closestText, s) }
                    if let s = stats.highest { record("Highest", "\(RadarFormat.wholeNumber(s.altitudeAtClosestFeet)) ft", s) }
                    if let s = stats.fastest { record("Fastest", "\(RadarFormat.wholeNumber(s.speedKnots)) kts", s) }
                }

                Section("Badges · \(achievements.filter(\.isUnlocked).count) of \(achievements.count)") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 16) {
                        ForEach(achievements) { achievement in
                            NavigationLink {
                                AchievementDetailView(achievement: achievement, logbook: logbook, onTrack: onTrack, isLive: isLive)
                            } label: {
                                AchievementBadge(achievement: achievement)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                }

                if !stats.topAirlines.isEmpty {
                    Section("Most seen") {
                        ForEach(stats.topAirlines, id: \.name) { item in
                            LabeledContent(item.name, value: "\(item.count)")
                        }
                        ForEach(stats.topTypes.prefix(3), id: \.name) { item in
                            LabeledContent(item.name, value: "\(item.count)")
                                .foregroundStyle(Palette.caption)
                        }
                    }
                }
            }

            ForEach(LogbookGrouping.byDay(filtered), id: \.day) { group in
                Section("\(LogbookGrouping.title(for: group.day)) · \(group.items.count)") {
                    ForEach(group.items) { row($0) }
                        .onDelete { offsets in
                            logbook.delete(Set(offsets.map { group.items[$0].id }))
                        }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.paper.ignoresSafeArea())
        .searchable(text: $query, prompt: "Flight, airline, type, airport…")
        .navigationTitle("Logbook")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Clear Logbook", systemImage: "trash", role: .destructive) { confirmClear = true }
                        .disabled(logbook.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("Clear the whole logbook?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear Logbook", role: .destructive) { logbook.clear() }
        } message: {
            Text("Every sighting and badge on this device will be removed.")
        }
        .fontDesign(.monospaced)
    }

    private func record(_ title: String, _ value: String, _ sighting: Sighting) -> some View {
        NavigationLink {
            SightingDetailView(sighting: sighting, logbook: logbook, onTrack: onTrack, isLive: isLive(sighting.id))
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).radarCaption()
                    Text("\(sighting.displayIdentifier) · \(sighting.typeName ?? sighting.typeCode ?? "Aircraft")")
                        .font(.mono(13, .semibold))
                        .foregroundStyle(Palette.value)
                }
                Spacer()
                Text(value)
                    .font(.mono(15, .bold))
                    .foregroundStyle(Palette.ink)
            }
        }
    }

    private func row(_ s: Sighting) -> some View {
        NavigationLink {
            SightingDetailView(sighting: s, logbook: logbook, onTrack: onTrack, isLive: isLive(s.id))
        } label: {
            SightingRowLabel(sighting: s, isLive: isLive(s.id))
        }
        .listRowBackground(Palette.paperShade.opacity(0.25))
    }
}

/// One sighting in a list: icon, flight, route, operator and type, closest pass and time.
struct SightingRowLabel: View {
    let sighting: Sighting
    var isLive = false
    /// Show the date rather than the time (lists that span days).
    var showsDate = false

    var body: some View {
        let s = sighting
        HStack(spacing: 12) {
            Image(systemName: s.kind == .helicopter ? "fan.fill" : "airplane")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isLive ? Palette.signal : Palette.blip)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(s.displayIdentifier)
                        .font(.mono(15, .bold))
                        .foregroundStyle(Palette.ink)
                    if let route = s.routeText {
                        Text(route)
                            .font(.mono(11, .semibold))
                            .foregroundStyle(Palette.route)
                    }
                    if let tag = s.tags.first {
                        Image(systemName: tag.symbol)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Palette.color(for: tag))
                    }
                }
                Text(s.summaryLine)
                    .font(.mono(11))
                    .foregroundStyle(Palette.caption)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 3) {
                Text(s.closestText)
                    .font(.mono(13, .bold))
                    .foregroundStyle(Palette.value)
                Text(showsDate ? s.firstSeen.formatted(.dateTime.month(.abbreviated).day().hour().minute()) : s.firstSeen.formatted(date: .omitted, time: .shortened))
                    .font(.mono(10))
                    .foregroundStyle(Palette.caption)
            }
        }
    }
}

/// "Logbook  4" — the airframe's all-time sighting count, as a capsule on its pages.
struct LogbookCountLabel: View {
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 12, weight: .bold))
            Text("Logbook")
                .font(.mono(12, .bold))
            Text(RadarFormat.wholeNumber(count))
                .font(.mono(13, .heavy))
                .monospacedDigit()
                .foregroundStyle(count > 0 ? Color.white : Palette.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(count > 0 ? Palette.route : Palette.ink.opacity(0.1), in: Capsule())
            if count > 0 {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
            }
        }
        .foregroundStyle(count > 0 ? Palette.route : Palette.caption)
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
        .background(Palette.route.opacity(count > 0 ? 0.1 : 0.04), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Logbook, seen \(count) \(count == 1 ? "time" : "times")")
    }
}

/// Every time this airframe came by, newest first, reached from the "Logbook" button on
/// an aircraft's page: the all-time numbers, then each visit and when it was.
struct AirframeHistoryView: View {
    let airframe: String
    let logbook: Logbook
    var onTrack: ((String) -> Void)?
    var isLive: (String) -> Bool = { _ in false }

    var body: some View {
        let summary = logbook.summary(airframe: airframe)
        List {
            if let latest = summary.latest {
                Section {
                    VStack(spacing: 6) {
                        Text(latest.operatorName).radarCaption()
                        Text(airframe)
                            .font(.mono(36, .heavy))
                            .foregroundStyle(Palette.ink)
                        if let type = latest.typeName ?? latest.typeCode {
                            Text(type).font(.mono(13)).foregroundStyle(Palette.caption)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        LogbookStatTile(title: "Times seen", value: RadarFormat.wholeNumber(summary.count))
                        LogbookStatTile(title: "Closest ever", value: summary.closest?.closestText ?? "—")
                        LogbookStatTile(title: "First seen", value: summary.first?.firstSeen.formatted(date: .abbreviated, time: .omitted) ?? "—")
                        LogbookStatTile(title: "Last seen", value: summary.latest.map { AirframeHistoryView.when($0.lastSeen) } ?? "—")
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    .listRowBackground(Color.clear)
                }
            }
            Section("Every sighting · \(summary.count)") {
                ForEach(summary.history) { s in
                    NavigationLink {
                        SightingDetailView(sighting: s, logbook: logbook, onTrack: onTrack, isLive: isLive(s.id))
                    } label: {
                        VisitRow(sighting: s, isLive: isLive(s.id))
                    }
                    .listRowBackground(Palette.paperShade.opacity(0.25))
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.paper.ignoresSafeArea())
        .navigationTitle(airframe)
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.monospaced)
    }

    /// "Today", "Yesterday", or "Oct 2, 2026".
    static func when(_ date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    /// One visit: when, which flight and route, and how close and high it came.
    private struct VisitRow: View {
        let sighting: Sighting
        let isLive: Bool

        var body: some View {
            let s = sighting
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(AirframeHistoryView.when(s.firstSeen)) · \(s.firstSeen.formatted(date: .omitted, time: .shortened))")
                        .font(.mono(12, .bold))
                        .foregroundStyle(isLive ? Palette.signal : Palette.value)
                    Spacer()
                    if isLive {
                        Text("ON RADAR").font(.mono(9, .heavy)).tracking(1.5).foregroundStyle(Palette.signal)
                    }
                }
                HStack(spacing: 6) {
                    Text(s.displayIdentifier)
                        .font(.mono(15, .heavy))
                        .foregroundStyle(Palette.ink)
                    if let route = s.routeText {
                        Text(route)
                            .font(.mono(12, .semibold))
                            .foregroundStyle(Palette.route)
                    }
                }
                HStack(spacing: 8) {
                    Text("\(s.closestText) closest · \(RadarFormat.wholeNumber(s.altitudeAtClosestFeet)) ft · \(RadarFormat.wholeNumber(s.speedKnots)) kts")
                    Label(s.inRangeText.lowercased(), systemImage: "clock")
                        .labelStyle(.titleAndIcon)
                        .accessibilityLabel("\(s.inRangeText) in range")
                }
                .font(.mono(11))
                .foregroundStyle(Palette.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            .padding(.vertical, 2)
        }
    }
}

struct AchievementDetailView: View {
    let achievement: Achievement
    let logbook: Logbook
    var onTrack: ((String) -> Void)?
    var isLive: (String) -> Bool = { _ in false }

    var body: some View {
        let a = achievement
        List {
            Section {
                VStack(spacing: 10) {
                    AchievementBadge(achievement: a, scale: 2.2, showsTitle: false)
                        .padding(.vertical, 8)
                    Text(a.isUnlocked ? "UNLOCKED" : "LOCKED")
                        .font(.mono(11, .heavy))
                        .tracking(3)
                        .foregroundStyle(a.isUnlocked ? Palette.notable : Palette.caption)
                    Text(a.title)
                        .font(.mono(26, .heavy))
                        .foregroundStyle(Palette.ink)
                    Text(a.detail)
                        .font(.mono(14, .semibold))
                        .foregroundStyle(Palette.value)
                        .multilineTextAlignment(.center)
                    Text(a.about)
                        .font(.mono(12))
                        .foregroundStyle(Palette.caption)
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            Section {
                AchievementProgress(achievement: a)
                    .padding(.vertical, 6)
            }
            Section(a.examples.isEmpty ? "No aircraft yet" : "Aircraft that count · \(a.progress)") {
                if a.examples.isEmpty {
                    Text("Keep the radar running — anything that qualifies shows up here.")
                        .font(.mono(12))
                        .foregroundStyle(Palette.caption)
                }
                ForEach(a.examples) { s in
                    NavigationLink {
                        SightingDetailView(sighting: s, logbook: logbook, onTrack: onTrack, isLive: isLive(s.id))
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(s.displayIdentifier).font(.mono(15, .bold)).foregroundStyle(Palette.ink)
                                if let route = s.routeText {
                                    Text(route).font(.mono(11, .semibold)).foregroundStyle(Palette.route)
                                }
                            }
                            Text("\(s.summaryLine) · \(s.firstSeen.formatted(date: .abbreviated, time: .shortened))")
                                .font(.mono(11))
                                .foregroundStyle(Palette.caption)
                                .lineLimit(1)
                        }
                    }
                }
                if a.progress > a.examples.count {
                    Text("Showing the latest \(a.examples.count) of \(a.progress)")
                        .font(.mono(11))
                        .foregroundStyle(Palette.caption)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.paper.ignoresSafeArea())
        .navigationTitle(a.title)
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.monospaced)
    }
}

struct SightingDetailView: View {
    let sighting: Sighting
    let logbook: Logbook
    var onTrack: ((String) -> Void)?
    var isLive = false

    @Environment(\.radarObserver) private var observer

    var body: some View {
        let s = sighting
        List {
            Section {
                VStack(spacing: 6) {
                    if let tag = s.tags.first {
                        Label(tag.rawValue.capitalized, systemImage: tag.symbol)
                            .font(.mono(11, .heavy))
                            .foregroundStyle(Palette.color(for: tag))
                    }
                    Text(s.operatorName).radarCaption()
                    Text(s.displayIdentifier)
                        .font(.mono(40, .heavy))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    if let route = s.routeText {
                        Text(route)
                            .font(.mono(20, .bold))
                            .foregroundStyle(Palette.route)
                    }
                    if let type = s.typeName ?? s.typeCode {
                        Text(type).font(.mono(13)).foregroundStyle(Palette.caption)
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section("Sighting") {
                LabeledContent("First seen", value: s.firstSeen.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Last seen", value: s.lastSeen.formatted(date: .omitted, time: .shortened))
                LabeledContent("Closest pass", value: s.closestText)
                LabeledContent("Altitude then", value: "\(RadarFormat.wholeNumber(s.altitudeAtClosestFeet)) ft")
                LabeledContent("Speed then", value: "\(RadarFormat.wholeNumber(s.speedKnots)) kts")
                if let place = s.placeName { LabeledContent("Watching from", value: place) }
            }

            Section("Aircraft") {
                LabeledContent("Registration", value: s.registration ?? "—")
                LabeledContent("Callsign", value: s.callsign ?? "—")
                LabeledContent("Type", value: s.typeCode ?? "—")
                LabeledContent("ICAO hex", value: s.hex ?? "—")
            }

            if let airframe = s.airframe {
                let count = logbook.summary(airframe: airframe).count
                Section {
                    NavigationLink {
                        AirframeHistoryView(airframe: airframe, logbook: logbook, onTrack: onTrack, isLive: { _ in false })
                    } label: {
                        LabeledContent {
                            Text(RadarFormat.wholeNumber(count))
                                .font(.mono(15, .heavy))
                                .foregroundStyle(Palette.route)
                        } label: {
                            Label("Logbook", systemImage: "book.closed.fill")
                        }
                    }
                } footer: {
                    Text("Every time you've seen \(airframe).")
                }
            }

            if isLive, let onTrack {
                Section {
                    Button("Show on Radar", systemImage: "scope") { onTrack(s.id) }
                }
            } else if s.canLocate {
                Section {
                    NavigationLink {
                        WhereaboutsView(title: s.registration ?? s.displayIdentifier, registration: s.registration,
                                        callsign: s.callsign, seenFlightID: s.id, observer: observer ?? s.observerCoordinate)
                    } label: {
                        Label("Where Is It Now?", systemImage: "location.magnifyingglass")
                    }
                } footer: {
                    Text("Finds this aircraft anywhere in the world, even far outside your radius.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.paper.ignoresSafeArea())
        .navigationTitle(s.displayIdentifier)
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.monospaced)
    }
}
#endif
