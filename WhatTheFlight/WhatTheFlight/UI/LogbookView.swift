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

    /// "iPhone, Apple TV".
    var devicesText: String? {
        loggedOn.isEmpty ? nil : loggedOn.map(\.title).joined(separator: ", ")
    }

    /// Icon colour at rest: military olive, otherwise the standard blip.
    var tint: Color {
        Palette.blip(isMilitary: tags.contains(.military))
    }

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

    /// "Atlanta, GA" or "Atlanta, GA + 2 more": where you watched from that day.
    static func places(in items: [Sighting]) -> String? {
        var seen = Set<String>()
        let places = items.reversed().compactMap(\.placeName).filter { seen.insert($0).inserted }
        guard let first = places.first else { return nil }
        return places.count == 1 ? first : "\(first) + \(places.count - 1) more"
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
    /// The badge whose page is open. NavigationLinks inside one grid row would all fire
    /// together, so the grid sets this instead.
    @State private var openBadge: String?

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

                let photos = logbook.allPhotos
                if !photos.isEmpty {
                    Section {
                        NavigationLink {
                            SpotPhotoGallery(logbook: logbook)
                        } label: {
                            HStack(spacing: 10) {
                                ForEach(photos.prefix(3)) { photo in
                                    SpotPhotoThumbnail(photo: photo, store: logbook.photoStore, size: 44)
                                }
                                Text("Your photos")
                                    .font(.mono(14, .bold))
                                    .foregroundStyle(Palette.ink)
                                Spacer()
                                Text(RadarFormat.wholeNumber(photos.count))
                                    .font(.mono(14, .heavy))
                                    .foregroundStyle(Palette.route)
                            }
                        }
                    }
                }

                let recap = DailyRecap(logbook.sightings)
                if !recap.notable.isEmpty || !recap.newTypes.isEmpty || !recap.newAirlines.isEmpty {
                    TodayHighlights(recap: recap, logbook: logbook, onTrack: onTrack, isLive: isLive)
                }

                Section("Records") {
                    if let s = stats.closest { record("Closest pass", s.closestText, s) }
                    if let s = stats.highest { record("Highest", "\(RadarFormat.wholeNumber(s.altitudeAtClosestFeet)) ft", s) }
                    if let s = stats.fastest { record("Fastest", "\(RadarFormat.wholeNumber(s.speedKnots)) kts", s) }
                }

                Section("Badges · \(achievements.filter(\.isUnlocked).count) of \(achievements.count)") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 16) {
                        ForEach(achievements) { achievement in
                            Button { openBadge = achievement.id } label: {
                                AchievementBadge(achievement: achievement)
                            }
                            .buttonStyle(.borderless)
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
                Section {
                    ForEach(group.items) { row($0) }
                        .onDelete { offsets in
                            logbook.delete(Set(offsets.map { group.items[$0].id }))
                        }
                } header: {
                    HStack {
                        Text("\(LogbookGrouping.title(for: group.day)) · \(group.items.count)")
                        Spacer()
                        if let places = LogbookGrouping.places(in: group.items) {
                            Label(places, systemImage: "mappin.and.ellipse")
                                .labelStyle(.titleAndIcon)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.paper.ignoresSafeArea())
        .searchable(text: $query, prompt: "Flight, airline, type, airport…")
        .navigationTitle("Logbook")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openBadge) { id in
            AchievementPager(achievements: achievements, selection: id, logbook: logbook, onTrack: onTrack, isLive: isLive)
        }
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
        #if DEBUG
        // `-wtf.debugBadge <id>` opens a badge's page (screenshots).
        .task {
            if let id = UserDefaults.standard.string(forKey: "wtf.debugBadge") { openBadge = id }
        }
        #endif
        .confirmationDialog("Clear the whole logbook?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear Logbook", role: .destructive) { logbook.clear() }
        } message: {
            Text("Every sighting and badge will be removed, on all your devices if the logbook syncs with iCloud.")
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

/// The day so far: notable aircraft, types and airlines new to the logbook.
struct TodayHighlights: View {
    let recap: DailyRecap
    let logbook: Logbook
    var onTrack: ((String) -> Void)?
    var isLive: (String) -> Bool = { _ in false }

    var body: some View {
        Section {
            HStack(spacing: 8) {
                chip("\(recap.total)", "spotted")
                if !recap.notable.isEmpty { chip("\(recap.notable.count)", "notable") }
                if !recap.newTypes.isEmpty { chip("\(recap.newTypes.count)", recap.newTypes.count == 1 ? "new type" : "new types") }
                if let closest = recap.closest { chip(closest.closestText, "closest") }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))

            ForEach(recap.notable) { s in
                link(s, reason: s.tags.first.map(Self.reason))
            }
            let newTypes = recap.newTypes.filter { s in !recap.notable.contains { $0.id == s.id } }
            ForEach(newTypes.prefix(Self.newTypeLimit)) { s in
                link(s, reason: "First \(s.typeName ?? s.typeCode ?? "of its type") in your logbook")
            }
            if newTypes.count > Self.newTypeLimit {
                Text("+ \(newTypes.count - Self.newTypeLimit) more new types today")
                    .font(.mono(11))
                    .foregroundStyle(Palette.caption)
                    .listRowBackground(Palette.paperShade.opacity(0.25))
            }
            if !recap.newAirlines.isEmpty {
                Label("New airline\(recap.newAirlines.count == 1 ? "" : "s"): \(recap.newAirlines.joined(separator: ", "))", systemImage: "globe.americas.fill")
                    .font(.mono(12))
                    .foregroundStyle(Palette.value)
                    .listRowBackground(Palette.paperShade.opacity(0.25))
            }
        } header: {
            Text("Today's highlights")
        }
    }

    private static let newTypeLimit = 3

    private func chip(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.mono(16, .bold)).foregroundStyle(Palette.ink)
            Text(label).font(.mono(9, .semibold)).textCase(.uppercase).foregroundStyle(Palette.caption)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Palette.paperShade.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func link(_ s: Sighting, reason: String?) -> some View {
        NavigationLink {
            SightingDetailView(sighting: s, logbook: logbook, onTrack: onTrack, isLive: isLive(s.id))
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                SightingRowLabel(sighting: s, isLive: isLive(s.id))
                if let reason {
                    Text(reason)
                        .font(.mono(10, .semibold))
                        .foregroundStyle(s.tags.first.map(Palette.color(for:)) ?? Palette.route)
                        .padding(.leading, 42)
                }
            }
        }
        .listRowBackground(Palette.paperShade.opacity(0.25))
    }

    private static func reason(_ tag: NotableTag) -> String {
        switch tag {
        case .hijack, .emergency, .radioFailure: return "Emergency squawk"
        case .medical: return "Air ambulance"
        case .military: return "Military"
        case .government: return "Government"
        case .rare: return "Rare aircraft"
        }
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
            AircraftGlyph(silhouette: s.silhouette, size: 28, spinsRotor: false)
                .foregroundStyle(isLive ? Palette.signal : s.tint)
                .frame(width: 30)
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
                    if !s.spotPhotos.isEmpty {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Palette.signal)
                            .accessibilityLabel("Photographed")
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
                HStack(spacing: 4) {
                    ForEach(s.loggedOn, id: \.self) { device in
                        Image(systemName: device.symbol)
                            .font(.system(size: 9, weight: .semibold))
                    }
                    Text(showsDate ? s.firstSeen.formatted(.dateTime.month(.abbreviated).day().hour().minute()) : s.firstSeen.formatted(date: .omitted, time: .shortened))
                        .font(.mono(10))
                }
                .foregroundStyle(Palette.caption)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(s.devicesText.map { "Logged on \($0)" } ?? "")
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

/// Badge pages: swipe left and right through every badge; Back returns to the logbook.
struct AchievementPager: View {
    let achievements: [Achievement]
    @State var selection: String
    let logbook: Logbook
    var onTrack: ((String) -> Void)?
    var isLive: (String) -> Bool = { _ in false }

    var body: some View {
        TabView(selection: $selection) {
            ForEach(achievements) { achievement in
                AchievementDetailView(achievement: achievement, logbook: logbook, onTrack: onTrack, isLive: isLive)
                    .tag(achievement.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Palette.paper.ignoresSafeArea())
        .navigationTitle(achievements.first { $0.id == selection }?.title ?? "Badge")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(achievements.first { $0.id == selection }?.title ?? "Badge")
                        .font(.mono(15, .bold))
                    if let index = achievements.firstIndex(where: { $0.id == selection }) {
                        Text("\(index + 1) of \(achievements.count)")
                            .font(.mono(10))
                            .foregroundStyle(Palette.caption)
                    }
                }
            }
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
        // The live copy, so photos added or deleted show straight away.
        let s = logbook.sighting(id: sighting.id) ?? sighting
        List {
            Section {
                VStack(spacing: 6) {
                    AircraftGlyph(silhouette: s.silhouette, size: 56, spinsRotor: false)
                        .foregroundStyle(s.tint)
                        .padding(.bottom, 4)
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

            if !s.spotPhotos.isEmpty {
                Section("Your photos · \(s.spotPhotos.count)") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(s.spotPhotos) { photo in
                                NavigationLink {
                                    SpotPhotoView(photo: photo, store: logbook.photoStore,
                                                  onDelete: { logbook.removePhoto(id: photo.id) })
                                } label: {
                                    SpotPhotoThumbnail(photo: photo, store: logbook.photoStore, size: 96)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
            }

            Section("Sighting") {
                LabeledContent("First seen", value: s.firstSeen.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Last seen", value: s.lastSeen.formatted(date: .omitted, time: .shortened))
                LabeledContent("Closest pass", value: s.closestText)
                LabeledContent("Altitude then", value: "\(RadarFormat.wholeNumber(s.altitudeAtClosestFeet)) ft")
                LabeledContent("Speed then", value: "\(RadarFormat.wholeNumber(s.speedKnots)) kts")
                if let place = s.placeName { LabeledContent("Watching from", value: place) }
                if let devices = s.devicesText { LabeledContent("Logged on", value: devices) }
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
/// Every Sky View photo in the logbook, newest first.
struct SpotPhotoGallery: View {
    let logbook: Logbook

    var body: some View {
        let photos = logbook.allPhotos
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                ForEach(photos) { photo in
                    NavigationLink {
                        SpotPhotoView(photo: photo, store: logbook.photoStore, onDelete: { logbook.removePhoto(id: photo.id) })
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            SpotPhotoThumbnail(photo: photo, store: logbook.photoStore, size: 104)
                            Text(photo.displayIdentifier)
                                .font(.mono(11, .bold))
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            Text(photo.takenAt.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.mono(10))
                                .foregroundStyle(Palette.caption)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .overlay {
            if photos.isEmpty {
                ContentUnavailableView("No photos yet", systemImage: "camera",
                                       description: Text("Take one in Sky View and it lands here, with a boarding pass to share."))
            }
        }
        .background(Palette.paper.ignoresSafeArea())
        .navigationTitle("Your Photos")
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.monospaced)
    }
}
#endif
