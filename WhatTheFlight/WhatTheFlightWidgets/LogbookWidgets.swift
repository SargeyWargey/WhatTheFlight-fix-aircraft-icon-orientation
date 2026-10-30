//
//  LogbookWidgets.swift
//  WhatTheFlightWidgets
//
//  The widgets that read the logbook (Logbook, Badges, Your Sky): their timelines, the
//  Badges widget's choice of badge, and their configurations. They read the App Group's
//  `LogbookSnapshot`, which the app rewrites whenever the logbook changes and then reloads
//  them; entries at midnight (Logbook) and every half hour (Your Sky) move "today" and the
//  clock's hand on without the app. Their faces are in `LogbookStatsView`, `BadgesView` and
//  `SkyClockView`.
//

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Logbook

struct LogbookStatsProvider: TimelineProvider {
    func placeholder(in context: Context) -> LogbookEntry {
        LogbookEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (LogbookEntry) -> Void) {
        let shared = LogbookSnapshot.shared()
        let useSample = context.isPreview && (shared?.total ?? 0) == 0
        completion(LogbookEntry(date: Date(), snapshot: useSample ? .sample : shared))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LogbookEntry>) -> Void) {
        let snapshot = LogbookSnapshot.shared()
        let now = Date()
        let first = LogbookSnapshot.nextMidnight(after: now)
        let second = LogbookSnapshot.nextMidnight(after: first)
        // The app reloads whenever the logbook changes; midnights only move "today" on.
        let entries = [now, first, second].map { LogbookEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct LogbookStatsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedRadarStore.logbookKind, provider: LogbookStatsProvider()) { entry in
            WidgetFamilyReader { LogbookStatsView(entry: entry, family: $0) }
                .containerBackground(for: .widget) { LogbookWidgetBackdrop() }
        }
        .configurationDisplayName("Logbook")
        .description("Aircraft you've logged today, your streak and your records.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

// MARK: - Badges

struct BadgeEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Badge"
    static let defaultQuery = BadgeQuery()

    let id: String
    let title: String
    let group: String
    let symbol: String

    init(_ badge: LogbookSnapshot.Badge) {
        id = badge.id
        title = badge.title
        group = badge.groupTitle
        symbol = badge.symbol
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(group)", image: .init(systemName: symbol))
    }
}

struct BadgeQuery: EntityQuery {
    func entities(for identifiers: [BadgeEntity.ID]) async throws -> [BadgeEntity] {
        let badges = Self.badges()
        return identifiers.compactMap { id in badges.first { $0.id == id }.map(BadgeEntity.init) }
    }

    func suggestedEntities() async throws -> IntentItemCollection<BadgeEntity> {
        let groups = (SharedRadarStore().logbook ?? .sample).groups
        return IntentItemCollection(sections: groups.map { group in
            IntentItemSection(LocalizedStringResource(stringLiteral: group.title), items: group.badges.map(BadgeEntity.init))
        })
    }

    private static func badges() -> [LogbookSnapshot.Badge] {
        (SharedRadarStore().logbook ?? .sample).badges
    }
}

struct BadgeWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Badge"
    static let description = IntentDescription("Follow one badge, or leave it empty to see the one you're closest to.")

    @Parameter(title: "Badge")
    var badge: BadgeEntity?
}

struct BadgesProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> LogbookEntry {
        LogbookEntry(date: Date(), snapshot: .sample)
    }

    func snapshot(for configuration: BadgeWidgetIntent, in context: Context) async -> LogbookEntry {
        let shared = LogbookSnapshot.shared()
        let useSample = context.isPreview && (shared?.total ?? 0) == 0
        return LogbookEntry(date: Date(), snapshot: useSample ? .sample : shared, badgeID: configuration.badge?.id)
    }

    func timeline(for configuration: BadgeWidgetIntent, in context: Context) async -> Timeline<LogbookEntry> {
        // Badges only move when the logbook does, and the app reloads the widget then.
        let entry = LogbookEntry(date: Date(), snapshot: LogbookSnapshot.shared(), badgeID: configuration.badge?.id)
        return Timeline(entries: [entry], policy: .never)
    }
}

struct BadgesWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: SharedRadarStore.badgesKind, intent: BadgeWidgetIntent.self, provider: BadgesProvider()) { entry in
            WidgetFamilyReader { BadgesView(entry: entry, family: $0) }
                .containerBackground(for: .widget) { LogbookWidgetBackdrop(corner: .bottomTrailing) }
        }
        .configurationDisplayName("Badges")
        .description("Watch a badge fill toward its next level, and see what you've earned.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge,
                            .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

// MARK: - Your Sky

struct SkyClockProvider: TimelineProvider {
    static let step: TimeInterval = 30 * 60
    static let steps = 24

    func placeholder(in context: Context) -> LogbookEntry {
        LogbookEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (LogbookEntry) -> Void) {
        let shared = LogbookSnapshot.shared()
        let useSample = context.isPreview && !(shared?.sky?.showsTimes ?? false)
        completion(LogbookEntry(date: Date(), snapshot: useSample ? .sample : shared))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LogbookEntry>) -> Void) {
        let snapshot = LogbookSnapshot.shared()
        // On the half hour, so the hand moves when the clock does.
        let now = Date()
        let start = Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / Self.step).rounded(.down) * Self.step)
        let entries = [LogbookEntry(date: now, snapshot: snapshot)]
            + (1..<Self.steps).map { LogbookEntry(date: start.addingTimeInterval(Double($0) * Self.step), snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct SkyClockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedRadarStore.skyClockKind, provider: SkyClockProvider()) { entry in
            WidgetFamilyReader { SkyClockView(entry: entry, family: $0) }
                .containerBackground(for: .widget) { LogbookWidgetBackdrop(corner: .center) }
        }
        .configurationDisplayName("Your Sky")
        .description("When aircraft pass over where you watch, and which way they fly.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}
