//
//  TVLogbookView.swift
//  WhatTheFlight
//
//  The logbook on the big screen: the same five tabs as iPhone and iPad (Overview,
//  Sightings, Stats, Badges, Photos) in the TV's top tab bar. ▲ always reaches the tabs.
//  Everything is clickable: a sighting opens that aircraft's page (◀ ▶ then step through the
//  list it came from), a badge its own page, a regular its whole history. The tab pages
//  live in `TVLogbookTabs.swift`; the pages they open are below.
//

#if os(tvOS)
import SwiftUI
import MapKit

/// What a tab can open over the logbook.
struct TVLogbookActions {
    var open: (TVSightingBrowse) -> Void
    var badge: (Achievement) -> Void
    var airframe: (String) -> Void
    var showTab: (LogbookTab) -> Void
    var clear: () -> Void
}

struct TVLogbookView: View {
    let logbook: Logbook
    let showTopography: Bool
    var showPhotos = true
    var isLive: (String) -> Bool = { _ in false }
    let onPick: (String) -> Void

    @State private var tab = LogbookTab.initial
    @State private var confirmClear = false
    @State private var shownBadge: Achievement?
    @State private var shownBrowse: TVSightingBrowse?
    @State private var shownAirframe: String?

    var body: some View {
        let actions = TVLogbookActions(
            open: { shownBrowse = $0 },
            badge: { shownBadge = $0 },
            airframe: { shownAirframe = $0 },
            showTab: { tab = $0 },
            clear: { confirmClear = true })
        let ctx = TVLogbookContext(logbook: logbook, showPhotos: showPhotos, isLive: isLive, actions: actions)
        TabView(selection: $tab) {
            Tab(LogbookTab.overview.title, systemImage: LogbookTab.overview.symbol, value: LogbookTab.overview) {
                page { TVLogbookOverview(ctx: ctx) }
            }
            Tab(LogbookTab.sightings.title, systemImage: LogbookTab.sightings.symbol, value: LogbookTab.sightings) {
                page { TVLogbookSightings(ctx: ctx) }
            }
            Tab(LogbookTab.stats.title, systemImage: LogbookTab.stats.symbol, value: LogbookTab.stats) {
                page { TVLogbookStats(ctx: ctx) }
            }
            Tab(LogbookTab.badges.title, systemImage: LogbookTab.badges.symbol, value: LogbookTab.badges) {
                page { TVLogbookBadges(ctx: ctx) }
            }
            Tab(LogbookTab.photos.title, systemImage: LogbookTab.photos.symbol, value: LogbookTab.photos) {
                page { TVLogbookPhotos(ctx: ctx) }
            }
        }
        #if DEBUG
        .task {
            // `-wtf.debugBadge <id>` opens a badge's page, `-wtf.debugSighting <id>` a sighting's
            // (paging through the records if it's one of them), `-wtf.debugAirframe <reg>` an
            // airframe's log — for screenshots.
            let defaults = UserDefaults.standard
            try? await Task.sleep(for: .seconds(1))
            let digest = logbook.digest
            if let airframe = defaults.string(forKey: "wtf.debugAirframe") {
                shownAirframe = airframe
            } else if let id = defaults.string(forKey: "wtf.debugBadge") {
                shownBadge = digest.achievements.first { $0.id == id }
            } else if let id = defaults.string(forKey: "wtf.debugSighting"),
                      let sighting = logbook.sightings.first(where: { $0.id == id }) {
                let records = digest.records
                if let i = records.firstIndex(where: { $0.sighting.id == id }) {
                    shownBrowse = TVSightingBrowse(records.map { .init(sighting: $0.sighting, label: "\($0.title) · \($0.value)") }, start: i)
                } else {
                    shownBrowse = TVSightingBrowse(logbook.recent, showing: sighting)
                }
            }
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
                    shownBrowse = TVSightingBrowse(badge.examples, showing: sighting)
                }
            }
        }
        .fullScreenCover(isPresented: Binding(get: { shownAirframe != nil }, set: { if !$0 { shownAirframe = nil } })) {
            if let airframe = shownAirframe {
                TVAirframeHistoryView(airframe: airframe, logbook: logbook, showTopography: showTopography,
                                      showPhotos: showPhotos, isLive: isLive) { id in
                    shownAirframe = nil
                    onPick(id)
                }
            }
        }
        .fullScreenCover(item: $shownBrowse) { browse in
            TVSightingDetailView(browse: browse, logbook: logbook, showTopography: showTopography,
                                 showPhotos: showPhotos, isLive: isLive) { id in
                shownBrowse = nil
                onPick(id)
            }
        }
    }

    /// A tab's page over the paper and contours.
    private func page<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack {
            LogbookBackdrop(showTopography: showTopography)
                .ignoresSafeArea()
            content()
        }
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

struct TVSightingRow: View {
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
            AircraftGlyph(silhouette: s.silhouette, size: 52, spinsRotor: false)
                .foregroundStyle(focused ? .white : (isLive ? Palette.signal : s.tint))
                .frame(width: 56)
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
            LogbookBackdrop(showTopography: showTopography)
                .ignoresSafeArea()
            HStack(alignment: .top, spacing: 80) {
                VStack(alignment: .leading, spacing: 24) {
                    AchievementBadge(achievement: a, scale: 4.2, showsTitle: false)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    HStack(spacing: 20) {
                        Text(a.isMaxed ? (a.hasLevels ? "EVERY LEVEL" : "UNLOCKED") : (a.isUnlocked ? "LEVEL \(a.level)" : "LOCKED"))
                            .font(.mono(20, .heavy))
                            .tracking(4)
                            .foregroundStyle(a.isUnlocked ? Palette.notable : Palette.caption)
                        if a.hasLevels {
                            TierDots(earned: a.level, total: a.tiers.count, scale: 2.4)
                        }
                        Spacer()
                        Text(a.group.title.uppercased())
                            .font(.mono(18, .bold))
                            .tracking(3)
                            .foregroundStyle(Palette.caption)
                    }
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
                    TVSectionHeader(title: a.examples.isEmpty ? "No aircraft yet" : "Aircraft that count")
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
                                if a.examples.count >= Achievement.exampleLimit {
                                    Text("Showing the latest \(a.examples.count)")
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

/// What the sighting page pages through with ◀ ▶: the list it was opened from (every
/// sighting, the three records, or a badge's aircraft) and where to start.
struct TVSightingBrowse: Identifiable {
    struct Item {
        let sighting: Sighting
        /// "Closest pass" when opened from the records.
        var label: String? = nil
    }

    let id = UUID()
    let items: [Item]
    let start: Int

    init(_ items: [Item], start: Int) {
        self.items = items
        self.start = min(max(0, start), max(0, items.count - 1))
    }

    init(_ sightings: [Sighting], showing sighting: Sighting) {
        self.init(sightings.map { Item(sighting: $0) }, start: sightings.firstIndex { $0.id == sighting.id } ?? 0)
    }
}

/// One logbook entry as a full aircraft page: photo, route, a map of where it passed you
/// and the numbers at its closest. ◀ ▶ step through the list it was opened from; click
/// switches the map between nearby and the full route; ▼ reaches the buttons ("Logbook N"
/// lists every time you've seen this airframe; "Where Is It Now?" finds it anywhere).
struct TVSightingDetailView: View {
    let browse: TVSightingBrowse
    let logbook: Logbook
    let showTopography: Bool
    var showPhotos = true
    var isLive: (String) -> Bool = { _ in false }
    let onTrack: (String) -> Void

    @State private var items: [TVSightingBrowse.Item]
    @State private var index: Int
    @State private var entering: Edge = .trailing
    @State private var showsRoute = false
    @State private var locating: Sighting?
    @State private var showsLog = false
    @FocusState private var focus: Focus?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.radarObserver) private var observer

    enum Focus: Hashable { case page, track, locate, history, close }

    init(browse: TVSightingBrowse, logbook: Logbook, showTopography: Bool, showPhotos: Bool = true,
         isLive: @escaping (String) -> Bool = { _ in false }, onTrack: @escaping (String) -> Void) {
        self.browse = browse
        self.logbook = logbook
        self.showTopography = showTopography
        self.showPhotos = showPhotos
        self.isLive = isLive
        self.onTrack = onTrack
        _items = State(initialValue: browse.items)
        _index = State(initialValue: browse.start)
    }

    private var item: TVSightingBrowse.Item { items[index] }

    var body: some View {
        let s = item.sighting
        ZStack {
            LogbookBackdrop(showTopography: showTopography)
                .ignoresSafeArea()
            VStack(spacing: 28) {
                Button(action: toggleMap) {
                    page(item)
                        .id(s.id)
                        .transition(.push(from: entering))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .buttonStyle(TVQuietButtonStyle())
                .focused($focus, equals: .page)
                .onMoveCommand { direction in
                    switch direction {
                    case .left: step(-1)
                    case .right: step(1)
                    case .down: focus = isLive(s.id) ? .track : (s.canLocate ? .locate : .close)
                    default: break
                    }
                }

                HStack(spacing: 24) {
                    if isLive(s.id) {
                        Button("Show on Radar") { onTrack(s.id) }
                            .buttonStyle(TVPillButtonStyle(prominent: true))
                            .focused($focus, equals: .track)
                    } else if s.canLocate {
                        Button("Where Is It Now?") { locating = s }
                            .buttonStyle(TVPillButtonStyle(prominent: true))
                            .focused($focus, equals: .locate)
                    }
                    if let airframe = s.airframe {
                        Button { showsLog = true } label: {
                            TVLogbookCountLabel(count: logbook.summary(airframe: airframe).count)
                        }
                        .buttonStyle(TVPillButtonStyle(prominent: false))
                        .focused($focus, equals: .history)
                    }
                    Button("Close") { dismiss() }
                        .buttonStyle(TVPillButtonStyle(prominent: false))
                        .focused($focus, equals: .close)
                    Spacer()
                    hints(for: s)
                }
                .focusSection()
            }
            .padding(.horizontal, 100)
            .padding(.top, 60)
            .padding(.bottom, 40)
        }
        .defaultFocus($focus, .page)
        .animation(.smooth(duration: 0.35), value: index)
        #if DEBUG
        .task {
            // `-wtf.debugLocate YES` opens "Where Is It Now?" for the first page (screenshots).
            guard UserDefaults.standard.bool(forKey: "wtf.debugLocate") else { return }
            try? await Task.sleep(for: .seconds(1))
            locating = item.sighting
        }
        #endif
        .fullScreenCover(isPresented: $showsLog) {
            if let airframe = item.sighting.airframe {
                TVAirframeHistoryView(airframe: airframe, logbook: logbook, showTopography: showTopography,
                                      showPhotos: showPhotos, isLive: isLive, onTrack: onTrack)
            }
        }
        .fullScreenCover(item: $locating) { s in
            TVWhereaboutsView(title: s.registration ?? s.displayIdentifier, registration: s.registration, callsign: s.callsign,
                              seenFlightID: s.id, observer: observer ?? s.observerCoordinate, showTopography: showTopography)
        }
    }

    private func step(_ delta: Int) {
        let next = index + delta
        guard items.indices.contains(next) else { return }
        entering = delta > 0 ? .trailing : .leading
        index = next
    }

    private func toggleMap() {
        guard SightingMap.canShowRoute(item.sighting) else { return }
        withAnimation(.smooth) { showsRoute.toggle() }
    }

    // MARK: Page

    private func page(_ item: TVSightingBrowse.Item) -> some View {
        let s = item.sighting
        return HStack(alignment: .top, spacing: 70) {
            VStack(alignment: .leading, spacing: 16) {
                if let label = item.label {
                    Text(label.uppercased())
                        .font(.mono(22, .heavy))
                        .tracking(3)
                        .foregroundStyle(Palette.signal)
                } else if let tag = s.tags.first {
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
                if s.routeText != nil {
                    RouteLine(flight: s.routeFlight)
                        .scaleEffect(1.8, anchor: .leading)
                        .frame(height: 100, alignment: .leading)
                }
                if let type = s.typeName ?? s.typeCode {
                    Text(type)
                        .font(.mono(28, .medium))
                        .foregroundStyle(Palette.caption)
                }
                TVSightingPhoto(sighting: s, enabled: showPhotos, height: 380, credit: true)
            }
            .frame(width: 700, alignment: .leading)

            VStack(alignment: .leading, spacing: 22) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: 3), spacing: 20) {
                    fact("Seen", s.firstSeen.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                    fact("In range for", s.inRangeText)
                    fact("Closest pass", s.closestText)
                    fact("Altitude then", "\(RadarFormat.wholeNumber(s.altitudeAtClosestFeet)) ft")
                    fact("Speed then", "\(RadarFormat.wholeNumber(s.speedKnots)) kts")
                    fact("Heading", s.trackAtClosest.map { "\(Int($0.rounded()) % 360)° \(GeoMath.cardinal($0))" } ?? "—")
                    fact("Registration", s.registration ?? "—")
                    fact("Callsign", s.callsign ?? "—")
                    fact("Type", s.typeCode ?? "—")
                    fact("ICAO hex", s.hex?.uppercased() ?? "—")
                    fact("Watching from", s.placeName ?? "—")
                    fact("Logged on", s.devicesText ?? "—")
                }
                if SightingMap.canShowNearby(s) || SightingMap.canShowRoute(s) {
                    SightingMap(sighting: s, showsRoute: showsRoute || !SightingMap.canShowNearby(s), height: 300)
                } else {
                    Text("No map for this one: it was logged before positions were saved.")
                        .font(.mono(20))
                        .foregroundStyle(Palette.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
        .padding(20)
        .background(Palette.paperShade.opacity(0.35), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// "◀ ▶ 3 of 120 · ● Full route", in key caps like the radar's footer.
    private func hints(for s: Sighting) -> some View {
        HStack(spacing: 34) {
            if items.count > 1 {
                hint(["arrowtriangle.left.fill", "arrowtriangle.right.fill"], "\(index + 1) of \(RadarFormat.wholeNumber(items.count))")
            }
            if SightingMap.canShowRoute(s), SightingMap.canShowNearby(s) {
                hint(["circle.circle"], showsRoute ? "Nearby map" : "Full route")
            }
        }
        .font(.mono(20, .semibold))
        .foregroundStyle(Palette.caption)
        .accessibilityHidden(true)
    }

    private func hint(_ symbols: [String], _ title: String) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(symbols, id: \.self) { Image(systemName: $0) }
            }
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Palette.value)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Palette.paperShade.opacity(0.6), in: Capsule())
            .overlay(Capsule().stroke(Palette.caption.opacity(0.35), lineWidth: 1.5))
            Text(title)
                .contentTransition(.numericText())
        }
    }
}

/// "📖 Logbook  4" for a pill button: the airframe's all-time sighting count.
struct TVLogbookCountLabel: View {
    let count: Int

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "book.closed.fill")
            Text("Logbook")
            Text(RadarFormat.wholeNumber(count))
                .font(.mono(26, .heavy))
                .monospacedDigit()
                .padding(.horizontal, 14)
                .padding(.vertical, 2)
                .background(Palette.route.opacity(0.25), in: Capsule())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Logbook, seen \(count) \(count == 1 ? "time" : "times")")
    }
}

/// Every time you've seen one airframe: photo and the all-time numbers on the left, each
/// visit (when, which flight, how close and high) on the right. Click one for its page,
/// then ◀ ▶ through the rest.
struct TVAirframeHistoryView: View {
    let airframe: String
    let logbook: Logbook
    let showTopography: Bool
    var showPhotos = true
    var isLive: (String) -> Bool = { _ in false }
    let onTrack: (String) -> Void

    @State private var browse: TVSightingBrowse?

    var body: some View {
        let summary = logbook.summary(airframe: airframe)
        ZStack {
            LogbookBackdrop(showTopography: showTopography)
                .ignoresSafeArea()
            HStack(alignment: .top, spacing: 70) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Logbook").radarCaptionTV()
                    Text(airframe)
                        .font(.mono(80, .heavy))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    if let latest = summary.latest {
                        Text([latest.operatorName, latest.typeName ?? latest.typeCode].compactMap { $0 }.joined(separator: " · "))
                            .font(.mono(24, .medium))
                            .foregroundStyle(Palette.caption)
                            .lineLimit(1)
                        TVSightingPhoto(sighting: latest, enabled: showPhotos, height: 300, credit: true)
                            .layoutPriority(-1)
                    }
                    if let rank = logbook.digest.regularRank(airframe: airframe) {
                        Label(rank == 1 ? "YOUR #1 REGULAR" : "YOUR #\(rank) REGULAR", systemImage: "arrow.triangle.2.circlepath")
                            .font(.mono(20, .heavy))
                            .tracking(2)
                            .labelStyle(TVLabelStyle())
                            .foregroundStyle(Palette.notable)
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 20), GridItem(.flexible(), spacing: 20), GridItem(.flexible(), spacing: 20)], spacing: 20) {
                        LogbookStatTile(title: "Times seen", value: RadarFormat.wholeNumber(summary.count), scale: 1.6)
                        LogbookStatTile(title: "Closest", value: summary.closest?.closestPreciseText ?? "—", scale: 1.6)
                        LogbookStatTile(title: "Flights", value: RadarFormat.wholeNumber(summary.flights), scale: 1.6)
                        LogbookStatTile(title: "First seen", value: summary.first.map { TVAirframeHistoryView.when($0.firstSeen) } ?? "—", scale: 1.6)
                        LogbookStatTile(title: "Last seen", value: summary.latest.map { TVAirframeHistoryView.when($0.lastSeen) } ?? "—", scale: 1.6)
                        LogbookStatTile(title: "Usually", value: summary.usualHour().map(LogbookFormat.hourRange) ?? "—", scale: 1.6)
                    }
                }
                .frame(width: 640, alignment: .leading)

                VStack(alignment: .leading, spacing: 16) {
                    TVSectionHeader(title: "Every sighting · \(RadarFormat.wholeNumber(summary.count))")
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(summary.history) { s in
                                Button {
                                    browse = TVSightingBrowse(summary.history, showing: s)
                                } label: {
                                    TVVisitRow(sighting: s, isLive: isLive(s.id))
                                }
                                .buttonStyle(TVRowButtonStyle())
                            }
                        }
                        .padding(.vertical, 20)
                        .padding(.horizontal, 10)
                    }
                    .scrollClipDisabled()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .focusSection()
            }
            .padding(.horizontal, 100)
            .padding(.vertical, 70)
        }
        .fullScreenCover(item: $browse) { browse in
            TVSightingDetailView(browse: browse, logbook: logbook, showTopography: showTopography,
                                 showPhotos: showPhotos, isLive: isLive, onTrack: onTrack)
        }
    }

    /// "Today", "Yesterday", "Oct 2, 2026".
    static func when(_ date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

/// One visit in an airframe's log: when, the flight and route, and the numbers at its closest.
private struct TVVisitRow: View {
    let sighting: Sighting
    let isLive: Bool
    @Environment(\.tvRowFocused) private var focused

    var body: some View {
        let s = sighting
        HStack(spacing: 30) {
            VStack(alignment: .leading, spacing: 6) {
                Text(TVAirframeHistoryView.when(s.firstSeen))
                    .font(.mono(26, .bold))
                Text(s.firstSeen.formatted(date: .omitted, time: .shortened))
                    .font(.mono(20))
                    .foregroundStyle(focused ? .white.opacity(0.8) : Palette.caption)
            }
            .frame(width: 200, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 16) {
                    Text(s.displayIdentifier)
                        .font(.mono(30, .heavy))
                    if let route = s.routeText {
                        Text(route)
                            .font(.mono(22, .semibold))
                            .foregroundStyle(focused ? .white.opacity(0.9) : Palette.route)
                    }
                    if isLive {
                        Text("ON RADAR")
                            .font(.mono(16, .heavy))
                            .tracking(2)
                            .foregroundStyle(focused ? .white : Palette.signal)
                    }
                }
                .lineLimit(1)
                HStack(spacing: 18) {
                    Text("\(RadarFormat.wholeNumber(s.altitudeAtClosestFeet)) ft · \(RadarFormat.wholeNumber(s.speedKnots)) kts")
                    Label(s.inRangeText.lowercased(), systemImage: "clock")
                        .labelStyle(TVLabelStyle())
                        .accessibilityLabel("\(s.inRangeText) in range")
                }
                .font(.mono(20))
                .foregroundStyle(focused ? .white.opacity(0.8) : Palette.caption)
                .lineLimit(1)
            }
            .layoutPriority(1)
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 6) {
                Text(s.closestText).font(.mono(30, .bold))
                Text("closest")
                    .font(.mono(18))
                    .foregroundStyle(focused ? .white.opacity(0.8) : Palette.caption)
            }
            .fixedSize()
        }
    }
}

/// Your own Sky View photo of it (taken on an iPhone, synced through iCloud), else the
/// aircraft's Planespotters photo (with credit), else a quiet placeholder.
struct TVSightingPhoto: View {
    let sighting: Sighting
    var enabled = true
    var height: CGFloat
    var credit = false

    @State private var photo: AircraftPhoto?
    @State private var own: UIImage?

    var body: some View {
        let latest = sighting.spotPhotos.last
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Palette.paperShade.opacity(0.35)
                if let own {
                    Image(uiImage: own)
                        .resizable()
                        .scaledToFill()
                } else if let photo {
                    ProviderPhoto(photo: photo) {
                        ProgressView()
                    }
                } else {
                    AircraftGlyph(silhouette: sighting.silhouette, size: height * 0.5, spinsRotor: false)
                        .foregroundStyle(Palette.faint)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            if credit {
                Group {
                    if own != nil, let latest {
                        Text("Your photo · \(latest.takenAt.formatted(date: .abbreviated, time: .shortened))")
                    } else {
                        Text(photo.map { "Photo © \($0.photographer ?? "Unknown") · Planespotters.net" } ?? " ")
                    }
                }
                .font(.mono(18))
                .foregroundStyle(Palette.caption)
                .lineLimit(1)
            }
        }
        .task(id: "\(sighting.id) \(latest?.id ?? "")") {
            photo = nil
            own = nil
            if let latest {
                own = await SpotPhotoImages.load(latest.id, store: .standard, maxPixels: 1600)
                if own != nil { return }
            }
            guard enabled else { return }
            photo = await AircraftPhotoProvider.shared.photo(registration: sighting.registration, hex: sighting.hex)
        }
    }
}

/// Where a logged aircraft passed you: its track through the closest point, or the whole
/// route from origin to destination through that point.
struct SightingMap: View {
    let sighting: Sighting
    var showsRoute = false
    var height: CGFloat = 300

    @State private var camera: MapCameraPosition = .automatic

    static func canShowNearby(_ s: Sighting) -> Bool { s.closestCoordinate != nil }

    static func canShowRoute(_ s: Sighting) -> Bool {
        s.origin?.coordinate != nil && s.destination?.coordinate != nil
    }

    private var routeShown: Bool { showsRoute && Self.canShowRoute(sighting) }

    /// Four minutes either side of the closest point, along the track it was flying.
    private var pass: [CLLocationCoordinate2D] {
        guard let p = sighting.closestCoordinate, let track = sighting.trackAtClosest else { return [] }
        let speed = Double(sighting.speedKnots)
        // `extrapolate` only runs forwards, so the approach is walked along the reciprocal.
        return stride(from: -240.0, through: 240, by: 60).map {
            $0 < 0
                ? GeoMath.extrapolate(p, trackDegrees: track + 180, speedKnots: speed, seconds: -$0)
                : GeoMath.extrapolate(p, trackDegrees: track, speedKnots: speed, seconds: $0)
        }
    }

    var body: some View {
        let s = sighting
        Map(position: $camera, interactionModes: []) {
            if routeShown, let from = s.origin?.coordinate, let to = s.destination?.coordinate {
                MapPolyline(coordinates: [from] + (s.closestCoordinate.map { [$0] } ?? []) + [to], contourStyle: .geodesic)
                    .stroke(Palette.route, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                Annotation(s.origin?.name ?? "", coordinate: from, anchor: .bottom) {
                    AirportPin(code: s.originIATA ?? "", filled: true)
                }
                Annotation(s.destination?.name ?? "", coordinate: to, anchor: .bottom) {
                    AirportPin(code: s.destinationIATA ?? "", filled: false)
                }
            } else if pass.count >= 2 {
                MapPolyline(coordinates: pass)
                    .stroke(Palette.route.opacity(0.9), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [8, 6]))
                if let you = s.observerCoordinate, let p = s.closestCoordinate {
                    MapPolyline(coordinates: [you, p])
                        .stroke(Palette.signal.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
                }
            }

            if let you = s.observerCoordinate {
                Annotation("You", coordinate: you, anchor: .center) {
                    Circle()
                        .fill(Palette.ink)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .shadow(radius: 2)
                }
            }

            if let p = s.closestCoordinate {
                Annotation(s.displayIdentifier, coordinate: p, anchor: .center) {
                    AircraftGlyph(silhouette: s.silhouette, size: 40, spinsRotor: false)
                        .rotationEffect(.degrees(s.trackAtClosest ?? 90))
                        .foregroundStyle(Palette.signal)
                    .shadow(color: .black.opacity(0.3), radius: 2)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .frame(height: height)
        .allowsHitTesting(false)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onChange(of: sighting.id, initial: true) { _, _ in frame() }
        .onChange(of: showsRoute) { _, _ in withAnimation(.smooth) { frame() } }
    }

    private func frame() {
        let s = sighting
        if routeShown, let from = s.origin?.coordinate, let to = s.destination?.coordinate {
            camera = .region(DetailMap.region(fitting: [from, to] + (s.closestCoordinate.map { [$0] } ?? []), padding: 1.35, minimumSpan: 0.5))
        } else {
            let points = pass + (s.observerCoordinate.map { [$0] } ?? []) + (s.closestCoordinate.map { [$0] } ?? [])
            guard !points.isEmpty else { return }
            camera = .region(DetailMap.region(fitting: points, padding: 1.5, minimumSpan: 0.05))
        }
    }
}

extension Sighting {
    /// Enough of a `Flight` to draw the route header.
    var routeFlight: Flight {
        Flight(id: id, hex: hex, latitude: closestLatitude ?? 0, longitude: closestLongitude ?? 0,
               track: trackAtClosest ?? 0, altitudeFeet: altitudeAtClosestFeet, groundSpeedKnots: speedKnots,
               verticalRateFPM: 0, squawk: nil, typeCode: typeCode, registration: registration,
               originIATA: originIATA, destinationIATA: destinationIATA, flightNumber: nil,
               callsign: callsign, airlineICAO: nil, isOnGround: false, positionTime: firstSeen)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
#endif
