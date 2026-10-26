//
//  LogbookSightingsTab.swift
//  WhatTheFlight
//
//  The logbook's history on iPhone and iPad. Instead of every sighting ever in one list,
//  this week shows a row per day and anything older a row per month; a day opens its own
//  page (highlights, a by-hour chart, every sighting). Quick filters (notable, photographed,
//  helicopters, military, new types) and search show matching sightings by day.
//

#if os(iOS)
import SwiftUI

struct LogbookSightingsTab: View {
    let ctx: LogbookContext

    @State private var query = ""
    @State private var filter: LogbookFilter?

    var body: some View {
        let digest = ctx.logbook.digest
        List {
            if ctx.logbook.isEmpty {
                ContentUnavailableView("No sightings yet", systemImage: "list.bullet.rectangle",
                                       description: Text("Every aircraft that comes inside your radius is logged here automatically."))
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    filterChips
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))

                if query.trimmingCharacters(in: .whitespaces).isEmpty && filter == nil {
                    browse(digest)
                } else {
                    results(digest)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(LogbookBackdrop())
        .searchable(text: $query, prompt: "Flight, airline, type, airport…")
    }

    // MARK: Browse

    @ViewBuilder
    private func browse(_ digest: LogbookDigest) -> some View {
        let week = digest.thisWeek()
        if !week.isEmpty {
            Section {
                ForEach(week) { day in
                    NavigationLink(value: LogbookRoute.day(day.day)) {
                        LogbookDayRow(title: LogbookGrouping.shortTitle(for: day.day),
                                      subtitle: day.day.formatted(.dateTime.month(.abbreviated).day()),
                                      count: day.count, notable: day.notable, newTypes: day.newTypes, photos: day.photos,
                                      place: day.placeSummary)
                    }
                    .listRowBackground(Palette.paperShade.opacity(0.25))
                }
            } header: {
                sectionHeader("This week", count: week.reduce(0) { $0 + $1.count })
            }
        }
        let months = digest.earlierMonths()
        if !months.isEmpty {
            Section {
                ForEach(months) { month in
                    NavigationLink(value: LogbookRoute.month(month.month)) {
                        LogbookDayRow(title: month.month.formatted(.dateTime.month(.wide)),
                                      subtitle: LogbookGrouping.monthSpan(month),
                                      count: month.count, notable: month.notable, newTypes: month.newTypes, photos: month.photos,
                                      place: nil)
                    }
                    .listRowBackground(Palette.paperShade.opacity(0.25))
                }
            } header: {
                sectionHeader("Earlier", count: months.reduce(0) { $0 + $1.count })
            }
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(RadarFormat.wholeNumber(count)) aircraft")
        }
    }

    // MARK: Search and filters

    @ViewBuilder
    private func results(_ digest: LogbookDigest) -> some View {
        let matches = Self.search(ctx.logbook.recent, query: query, filter: filter, digest: digest)
        if matches.isEmpty {
            ContentUnavailableView.search(text: query.isEmpty ? (filter?.title ?? "") : query)
                .listRowBackground(Color.clear)
        } else {
            LogbookSightingSections(sightings: matches, ctx: ctx)
        }
    }

    static func search(_ sightings: [Sighting], query: String, filter: LogbookFilter?, digest: LogbookDigest) -> [Sighting] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return sightings.filter { s in
            if let filter, !filter.matches(s, firstOfType: digest.firstOfType) { return false }
            guard !q.isEmpty else { return true }
            return [s.displayIdentifier, s.callsign, s.registration, s.typeCode, s.typeName, s.operatorName,
                    s.originIATA, s.destinationIATA, s.placeName]
                .contains { $0?.lowercased().contains(q) == true }
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", selected: filter == nil) { filter = nil }
                ForEach(LogbookFilter.quick, id: \.self) { f in
                    chip(f.title, selected: filter == f) { filter = filter == f ? nil : f }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .monoScaled(12, .bold)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(selected ? Color.white : Palette.value)
                .background(selected ? Palette.ink : Palette.paperShade.opacity(0.45), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Sightings in sections by day, newest first, swipe to delete.
struct LogbookSightingSections: View {
    let sightings: [Sighting]
    let ctx: LogbookContext
    /// One day's list: "Every sighting · 142" rather than the day's name again.
    var singleDay = false

    var body: some View {
        ForEach(LogbookGrouping.byDay(sightings), id: \.day) { group in
            Section {
                ForEach(group.items) { s in
                    NavigationLink(value: LogbookRoute.sighting(s.id)) {
                        SightingRowLabel(sighting: s, isLive: ctx.isLive(s.id))
                    }
                    .listRowBackground(Palette.paperShade.opacity(0.25))
                }
                .onDelete { offsets in
                    ctx.logbook.delete(Set(offsets.map { group.items[$0].id }))
                }
            } header: {
                HStack {
                    Text("\(singleDay ? "Every sighting" : LogbookGrouping.title(for: group.day)) · \(group.items.count)")
                    Spacer()
                    if !singleDay, let places = LogbookGrouping.places(in: group.items) {
                        Label(places, systemImage: "mappin.and.ellipse")
                            .labelStyle(.titleAndIcon)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

/// A day or a month: its name, what stood out, and how many aircraft.
struct LogbookDayRow: View {
    let title: String
    let subtitle: String
    let count: Int
    var notable = 0
    var newTypes = 0
    var photos = 0
    var place: String?

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title).monoScaled(15, .bold).foregroundStyle(Palette.ink)
                    Text(subtitle).monoScaled(11).foregroundStyle(Palette.caption)
                }
                .lineLimit(1)
                if notable + newTypes + photos > 0 || place != nil {
                    LogbookDayTags(notable: notable, newTypes: newTypes, photos: photos, place: place)
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 1) {
                Text(RadarFormat.wholeNumber(count)).monoScaled(18, .heavy).foregroundStyle(Palette.value)
                Text("aircraft").monoScaled(9, .semibold).textCase(.uppercase).foregroundStyle(Palette.caption)
            }
            .fixedSize()
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - A day

/// One day: how many, the highlights, a by-hour chart and every sighting.
struct LogbookDayView: View {
    let date: Date
    let ctx: LogbookContext

    var body: some View {
        let digest = ctx.logbook.digest
        let day = digest.day(date)
        let recap = DailyRecap(ctx.logbook.sightings, day: date)
        let calendar = Calendar.current
        let isToday = calendar.isDateInToday(date)
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text([LogbookGrouping.title(for: date), day?.placeSummary].compactMap { $0 }.joined(separator: " · "))
                        .radarCaption(scales: true)
                    Text("\(RadarFormat.wholeNumber(day?.count ?? 0)) aircraft")
                        .monoScaled(32, .heavy)
                        .foregroundStyle(Palette.ink)
                    let devices = Set((day?.sightings ?? []).flatMap(\.loggedOn)).sorted()
                    if !devices.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(devices, id: \.self) { Image(systemName: $0.symbol) }
                            Text("Logged on \(ListFormatter.localizedString(byJoining: devices.map(\.title)))")
                        }
                        .monoScaled(11)
                        .foregroundStyle(Palette.caption)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    LogbookChip(value: "\(recap.notable.count)", label: "Notable")
                    LogbookChip(value: "\(recap.newTypes.count)", label: recap.newTypes.count == 1 ? "New type" : "New types")
                    LogbookChip(value: recap.closest?.closestPreciseText ?? "—", label: "Closest")
                    LogbookChip(value: "\(day?.photos ?? 0)", label: day?.photos == 1 ? "Photo" : "Photos")
                }
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
            }

            let highlights = LogbookTodayCard.highlights(recap)
            if !highlights.isEmpty || !recap.newAirlines.isEmpty {
                Section("Highlights") {
                    ForEach(highlights, id: \.sighting.id) { item in
                        NavigationLink(value: LogbookRoute.sighting(item.sighting.id)) {
                            VStack(alignment: .leading, spacing: 4) {
                                SightingRowLabel(sighting: item.sighting, isLive: ctx.isLive(item.sighting.id))
                                Text(item.reason)
                                    .monoScaled(10, .semibold)
                                    .foregroundStyle(item.color)
                                    .padding(.leading, 42)
                            }
                        }
                        .listRowBackground(Palette.paperShade.opacity(0.25))
                    }
                    if !recap.newAirlines.isEmpty {
                        Label("New airline\(recap.newAirlines.count == 1 ? "" : "s"): \(recap.newAirlines.joined(separator: ", "))", systemImage: "globe.americas.fill")
                            .monoScaled(12)
                            .foregroundStyle(Palette.value)
                            .listRowBackground(Palette.paperShade.opacity(0.25))
                    }
                }
            }

            if let day {
                let hourly = Self.hourly(day.sightings, calendar: calendar)
                Section {
                    LogbookHourlyChart(counts: hourly, highlight: isToday ? calendar.component(.hour, from: Date()) : nil)
                        .padding(.vertical, 6)
                        .listRowBackground(Palette.paperShade.opacity(0.25))
                } header: {
                    HStack {
                        Text("By hour")
                        Spacer()
                        if let max = hourly.max(), max > 0, let hour = hourly.firstIndex(of: max) {
                            Text("Busiest \(LogbookFormat.hour(hour)) · \(max)")
                        }
                    }
                }
            }

            LogbookSightingSections(sightings: day?.sightings ?? [], ctx: ctx, singleDay: true)
        }
        .scrollContentBackground(.hidden)
        .background(LogbookBackdrop())
        .navigationTitle(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.monospaced)
    }

    static func hourly(_ sightings: [Sighting], calendar: Calendar = .current) -> [Int] {
        var counts = Array(repeating: 0, count: 24)
        for s in sightings { counts[calendar.component(.hour, from: s.firstSeen)] += 1 }
        return counts
    }
}

// MARK: - A month

/// One month: its total, a bar per day, and a row per day.
struct LogbookMonthView: View {
    let date: Date
    let ctx: LogbookContext

    var body: some View {
        let month = ctx.logbook.digest.month(date)
        List {
            if let month {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(LogbookGrouping.monthSpan(month)).radarCaption(scales: true)
                        Text("\(RadarFormat.wholeNumber(month.count)) aircraft")
                            .monoScaled(32, .heavy)
                            .foregroundStyle(Palette.ink)
                        LogbookDayTags(notable: month.notable, newTypes: month.newTypes, photos: month.photos,
                                       place: month.places.count > 1 ? "\(month.places.count) places" : month.places.first)
                    }
                    .listRowBackground(Color.clear)
                }
                Section("Aircraft per day") {
                    LogbookActivityChart(points: Self.points(month))
                        .padding(.vertical, 6)
                        .listRowBackground(Palette.paperShade.opacity(0.25))
                }
                Section("Days") {
                    ForEach(month.days) { day in
                        NavigationLink(value: LogbookRoute.day(day.day)) {
                            LogbookDayRow(title: LogbookGrouping.title(for: day.day), subtitle: "",
                                          count: day.count, notable: day.notable, newTypes: day.newTypes, photos: day.photos,
                                          place: day.placeSummary)
                        }
                        .listRowBackground(Palette.paperShade.opacity(0.25))
                    }
                }
            } else {
                ContentUnavailableView("Nothing logged that month", systemImage: "calendar")
                    .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .background(LogbookBackdrop())
        .navigationTitle(LogbookGrouping.monthTitle(date))
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.monospaced)
    }

    /// Every day of the month up to today, empty ones included.
    static func points(_ month: LogbookMonth, calendar: Calendar = .current) -> [(day: Date, count: Int)] {
        guard let interval = calendar.dateInterval(of: .month, for: month.month) else { return [] }
        let byDay = Dictionary(month.days.map { ($0.day, $0.count) }, uniquingKeysWith: +)
        let end = min(interval.end, Date())
        var points: [(day: Date, count: Int)] = []
        var day = interval.start
        while day < end {
            points.append((day, byDay[day] ?? 0))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return points
    }
}

// MARK: - A subset

/// Every sighting of an airline, type, route, airport, country or place (or a quick filter),
/// with when they tend to come by.
struct LogbookFilteredView: View {
    let filter: LogbookFilter
    let ctx: LogbookContext

    var body: some View {
        let digest = ctx.logbook.digest
        let matches = digest.sightings(matching: filter, in: ctx.logbook.recent)
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Self.caption(filter)).radarCaption(scales: true)
                    Text(filter.title)
                        .monoScaled(26, .heavy)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                    if case .country(let code) = filter {
                        Text(RegistrationCountry.flag(forCode: code)).font(.system(size: 30))
                    }
                    if let last = matches.first, let first = matches.last {
                        Text("\(RadarFormat.wholeNumber(matches.count)) sighting\(matches.count == 1 ? "" : "s") · first \(first.firstSeen.formatted(date: .abbreviated, time: .omitted)) · last \(LogbookGrouping.shortTitle(for: last.firstSeen))")
                            .monoScaled(12)
                            .foregroundStyle(Palette.value)
                    }
                }
                .listRowBackground(Color.clear)
            }
            if matches.count > 2 {
                Section("When they come by") {
                    LogbookHourlyChart(counts: LogbookDayView.hourly(matches))
                        .padding(.vertical, 6)
                        .listRowBackground(Palette.paperShade.opacity(0.25))
                }
            }
            LogbookSightingSections(sightings: matches, ctx: ctx)
        }
        .scrollContentBackground(.hidden)
        .background(LogbookBackdrop())
        .navigationTitle(filter.title)
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.monospaced)
    }

    static func caption(_ filter: LogbookFilter) -> String {
        switch filter {
        case .airframe: return "Aircraft"
        case .airline: return "Airline"
        case .type: return "Aircraft type"
        case .route: return "Route"
        case .airport: return "Airport"
        case .country: return "Registered in"
        case .place: return "Watched from"
        default: return "Sightings"
        }
    }
}

// MARK: - Rows and pages

/// One sighting in a list: icon, flight, route, operator and type, closest pass and time.
struct SightingRowLabel: View {
    let sighting: Sighting
    var isLive = false
    /// Show the date rather than the time (lists that span days).
    var showsDate = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.favoriteAircraft) private var favorites

    var body: some View {
        let s = sighting
        let isFavorite = favorites.contains(s)
        HStack(spacing: 12) {
            AircraftGlyph(silhouette: s.silhouette, size: 28, spinsRotor: false)
                .foregroundStyle(isFavorite ? Palette.favorite : isLive ? Palette.signal : s.tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                // At accessibility sizes the route goes under the flight number.
                (dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(spacing: 6))) {
                    Text(s.displayIdentifier)
                        .monoScaled(15, .bold)
                        .foregroundStyle(isFavorite ? Palette.favoriteText : Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Palette.favorite)
                            .accessibilityLabel("Favorite")
                    }
                    if let route = s.routeText {
                        Text(route)
                            .monoScaled(11, .semibold)
                            .foregroundStyle(Palette.route)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
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
                    .monoScaled(11)
                    .foregroundStyle(Palette.caption)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 3) {
                Text(s.closestText)
                    .monoScaled(13, .bold)
                    .foregroundStyle(Palette.value)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if isLive {
                        Text("ON RADAR").monoScaled(9, .heavy).foregroundStyle(Palette.signal)
                    } else {
                        ForEach(s.loggedOn, id: \.self) { device in
                            Image(systemName: device.symbol)
                                .font(.system(size: 9, weight: .semibold))
                        }
                        Text(showsDate ? s.firstSeen.formatted(.dateTime.month(.abbreviated).day().hour().minute()) : s.firstSeen.formatted(date: .omitted, time: .shortened))
                            .monoScaled(10)
                    }
                }
                .foregroundStyle(Palette.caption)
                .lineLimit(1)
            }
            .fixedSize()
        }
        // One row of columns: past this they no longer fit side by side.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .accessibilityElement(children: .combine)
        .accessibilityValue(s.devicesText.map { "Logged on \($0)" } ?? "")
    }
}

struct SightingDetailView: View {
    let sighting: Sighting
    let logbook: Logbook
    var onTrack: ((String) -> Void)?
    var isLive = false

    @Environment(\.radarObserver) private var observer
    @Environment(\.showsAircraftPhotos) private var showsPhotos
    @Environment(\.favoriteAircraft) private var favorites
    @Environment(\.toggleFavorite) private var toggleFavorite

    var body: some View {
        // The live copy, so photos added or deleted show straight away.
        let s = logbook.sighting(id: sighting.id) ?? sighting
        let isFavorite = favorites.contains(s)
        List {
            Section {
                VStack(spacing: 6) {
                    AircraftGlyph(silhouette: s.silhouette, size: 56, spinsRotor: false)
                        .foregroundStyle(isFavorite ? Palette.favorite : s.tint)
                        .padding(.bottom, 4)
                    if let tag = s.tags.first {
                        Label(tag.rawValue.capitalized, systemImage: tag.symbol)
                            .monoScaled(11, .heavy)
                            .foregroundStyle(Palette.color(for: tag))
                    }
                    if isFavorite {
                        FavoriteTag()
                    }
                    Text(s.operatorName).radarCaption(scales: true)
                    Text(s.displayIdentifier)
                        .monoScaled(40, .heavy)
                        .foregroundStyle(isFavorite ? Palette.favoriteText : Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    if let route = s.routeText {
                        Text(route)
                            .monoScaled(20, .bold)
                            .foregroundStyle(Palette.route)
                    }
                    if let type = s.typeName ?? s.typeCode {
                        Text(type).monoScaled(13).foregroundStyle(Palette.caption)
                    }
                    let records = logbook.digest.records.filter { $0.sighting.id == s.id }
                    if !records.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(records) { r in
                                Label(r.title, systemImage: "trophy.fill")
                                    .monoScaled(10, .heavy)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .foregroundStyle(Palette.notable)
                                    .background(Palette.notable.opacity(0.14), in: Capsule())
                            }
                        }
                        .padding(.top, 4)
                    }
                    if showsPhotos, s.airframe != nil {
                        PhotoCard(registration: s.registration, hex: s.hex)
                            .frame(maxWidth: 520)
                            .padding(.top, 10)
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
                LabeledContent("In range for", value: s.inRangeText)
                LabeledContent("Closest pass", value: s.closestPreciseText)
                LabeledContent("Altitude then", value: "\(RadarFormat.wholeNumber(s.altitudeAtClosestFeet)) ft")
                LabeledContent("Speed then", value: "\(RadarFormat.wholeNumber(s.speedKnots)) kts")
                if let track = s.trackAtClosest {
                    LabeledContent("Heading", value: "\(Int(track.rounded()) % 360)° \(GeoMath.cardinal(track))")
                }
                if let miles = s.routeMiles {
                    LabeledContent("Route length", value: "\(RadarFormat.wholeNumber(Int(miles.rounded()))) mi")
                }
                if let place = s.placeName { LabeledContent("Watching from", value: place) }
                if let devices = s.devicesText { LabeledContent("Logged on", value: devices) }
            }

            Section("Aircraft") {
                LabeledContent("Registration", value: s.registration ?? "—")
                if let country = s.registrationCountry {
                    LabeledContent("Registered in", value: "\(RegistrationCountry.flag(forCode: country)) \(RegistrationCountry.countryName(forCode: country))")
                }
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
                                .monoScaled(15, .heavy)
                                .foregroundStyle(Palette.route)
                        } label: {
                            Label("Logbook", systemImage: "book.closed.fill")
                        }
                    }
                } footer: {
                    Text("Every time you've seen \(airframe).")
                }
            }

            if toggleFavorite != nil, s.airframe != nil || s.callsign != nil {
                Section {
                    LogbookFavoriteButton(sighting: s)
                } footer: {
                    Text(isFavorite ? "Shows in yellow on the radar, the map and in your logbook."
                                    : "Favorites show in yellow on the radar, the map and in your logbook, whatever flight they're on.")
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
        .background(LogbookBackdrop())
        .navigationTitle(s.displayIdentifier)
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.monospaced)
    }
}
#endif
