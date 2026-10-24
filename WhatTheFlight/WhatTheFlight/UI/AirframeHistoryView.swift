//
//  AirframeHistoryView.swift
//  WhatTheFlight
//
//  One airframe's story in your logbook (iPhone and iPad): reached from the "Logbook N"
//  button on an aircraft's page and from Most Seen. Where it ranks among your regulars, the
//  all-time numbers, the routes it flew over you, when it tends to come by, your photos of
//  it and every visit. Also the Sky View photo gallery (the Photos tab).
//

#if os(iOS)
import SwiftUI

/// "Logbook  4" — the airframe's all-time sighting count, as a capsule on its pages.
struct LogbookCountLabel: View {
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 12, weight: .bold))
            Text("Logbook")
                .monoScaled(12, .bold)
            Text(RadarFormat.wholeNumber(count))
                .monoScaled(13, .heavy)
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

/// Every time this airframe came by, newest first, with what it tells you: how often, how
/// close, when it usually shows up and which routes it flies.
struct AirframeHistoryView: View {
    let airframe: String
    let logbook: Logbook
    var onTrack: ((String) -> Void)?
    var isLive: (String) -> Bool = { _ in false }

    @Environment(\.radarObserver) private var observer

    var body: some View {
        let summary = logbook.summary(airframe: airframe)
        let rank = logbook.digest.regularRank(airframe: airframe)
        List {
            if let latest = summary.latest {
                Section {
                    VStack(spacing: 6) {
                        AircraftGlyph(silhouette: latest.silhouette, size: 48, spinsRotor: false)
                            .foregroundStyle(latest.tint)
                        if let rank {
                            Label(rank == 1 ? "Your #1 regular" : "Your #\(rank) regular", systemImage: "arrow.triangle.2.circlepath")
                                .monoScaled(10, .heavy)
                                .textCase(.uppercase)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .foregroundStyle(Palette.notable)
                                .background(Palette.notable.opacity(0.14), in: Capsule())
                        }
                        Text(latest.operatorName).radarCaption(scales: true)
                        Text(airframe)
                            .monoScaled(36, .heavy)
                            .foregroundStyle(Palette.ink)
                        let country = summary.registrationCountry.map(RegistrationCountry.countryName(forCode:))
                        Text([latest.typeName ?? latest.typeCode, country].compactMap { $0 }.joined(separator: " · "))
                            .monoScaled(13)
                            .foregroundStyle(Palette.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        LogbookStatTile(title: "Times seen", value: RadarFormat.wholeNumber(summary.count))
                        LogbookStatTile(title: "Closest ever", value: summary.closest?.closestPreciseText ?? "—")
                        LogbookStatTile(title: "First seen", value: summary.first?.firstSeen.formatted(date: .abbreviated, time: .omitted) ?? "—")
                        LogbookStatTile(title: "Last seen", value: summary.latest.map { AirframeHistoryView.when($0.lastSeen) } ?? "—")
                        LogbookStatTile(title: "Usually", value: summary.usualHour().map(LogbookFormat.hourRange) ?? "—", symbol: "clock")
                        LogbookStatTile(title: "Flights", value: RadarFormat.wholeNumber(summary.flights), symbol: "number")
                    }
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    .listRowBackground(Color.clear)
                }

                let routes = summary.routes
                if !routes.isEmpty {
                    Section("Routes it flew over you") {
                        ForEach(routes, id: \.route) { r in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(r.route).monoScaled(14, .bold).foregroundStyle(Palette.route)
                                    Text(r.flight).monoScaled(11).foregroundStyle(Palette.caption)
                                    Spacer()
                                    Text("\(r.count)×").monoScaled(14, .heavy).foregroundStyle(Palette.value)
                                }
                                LogbookShareBar(share: Double(r.count) / Double(routes[0].count), strength: 0.85)
                                    .frame(height: 4)
                            }
                            .padding(.vertical, 4)
                            .listRowBackground(Palette.paperShade.opacity(0.25))
                            .accessibilityElement(children: .combine)
                        }
                    }
                }

                if summary.count > 1 {
                    Section {
                        LogbookHourlyChart(counts: summary.hourly(), highlight: summary.usualHour(), height: 80)
                            .padding(.vertical, 6)
                            .listRowBackground(Palette.paperShade.opacity(0.25))
                    } header: {
                        HStack {
                            Text("When it comes by")
                            Spacer()
                            if let hour = summary.usualHour() { Text("Usually \(LogbookFormat.hourRange(hour))") }
                        }
                    }
                }

                let photos = summary.history.flatMap(\.spotPhotos)
                if !photos.isEmpty {
                    Section("Your photos · \(photos.count)") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(photos) { photo in
                                    NavigationLink {
                                        SpotPhotoView(photo: photo, store: logbook.photoStore, onDelete: { logbook.removePhoto(id: photo.id) })
                                    } label: {
                                        SpotPhotoThumbnail(photo: photo, store: logbook.photoStore, size: 84)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
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

            if let latest = summary.latest, latest.canLocate, !isLive(latest.id) {
                Section {
                    NavigationLink {
                        WhereaboutsView(title: latest.registration ?? latest.displayIdentifier, registration: latest.registration,
                                        callsign: latest.callsign, seenFlightID: latest.id, observer: observer ?? latest.observerCoordinate)
                    } label: {
                        Label("Where Is It Now?", systemImage: "location.magnifyingglass")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(LogbookBackdrop())
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
                        .monoScaled(12, .bold)
                        .foregroundStyle(isLive ? Palette.signal : Palette.value)
                    Spacer()
                    if isLive {
                        Text("ON RADAR").monoScaled(9, .heavy).tracking(1.5).foregroundStyle(Palette.signal)
                    }
                }
                HStack(spacing: 6) {
                    Text(s.displayIdentifier)
                        .monoScaled(15, .heavy)
                        .foregroundStyle(Palette.ink)
                    if let route = s.routeText {
                        Text(route)
                            .monoScaled(12, .semibold)
                            .foregroundStyle(Palette.route)
                    }
                    if !s.spotPhotos.isEmpty {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Palette.signal)
                            .accessibilityLabel("Photographed")
                    }
                }
                HStack(spacing: 8) {
                    Text("\(s.closestText) closest · \(RadarFormat.wholeNumber(s.altitudeAtClosestFeet)) ft · \(RadarFormat.wholeNumber(s.speedKnots)) kts")
                    Label(s.inRangeText.lowercased(), systemImage: "clock")
                        .labelStyle(.titleAndIcon)
                        .accessibilityLabel("\(s.inRangeText) in range")
                }
                .monoScaled(11)
                .foregroundStyle(Palette.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            .padding(.vertical, 2)
        }
    }
}

/// Every Sky View photo in the logbook, newest first, by month.
struct SpotPhotoGallery: View {
    let logbook: Logbook

    var body: some View {
        let photos = logbook.allPhotos
        let months = Dictionary(grouping: photos) { Calendar.current.dateInterval(of: .month, for: $0.takenAt)?.start ?? $0.takenAt }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18, pinnedViews: []) {
                ForEach(months.keys.sorted(by: >), id: \.self) { month in
                    LogbookHeader(title: LogbookGrouping.monthTitle(month)) {
                        Text("\(months[month]!.count)").foregroundStyle(Palette.caption)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                        ForEach(months[month]!) { photo in
                            NavigationLink {
                                SpotPhotoView(photo: photo, store: logbook.photoStore, onDelete: { logbook.removePhoto(id: photo.id) })
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    SpotPhotoThumbnail(photo: photo, store: logbook.photoStore, size: 104)
                                    Text(photo.displayIdentifier)
                                        .monoScaled(11, .bold)
                                        .foregroundStyle(Palette.ink)
                                        .lineLimit(1)
                                    Text(photo.takenAt.formatted(.dateTime.month(.abbreviated).day()))
                                        .monoScaled(10)
                                        .foregroundStyle(Palette.caption)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
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
        .background(LogbookBackdrop())
        .navigationTitle(photos.isEmpty ? "Photos" : "Photos · \(photos.count)")
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.monospaced)
    }
}
#endif
