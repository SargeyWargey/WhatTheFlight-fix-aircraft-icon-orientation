//
//  LogbookIntents.swift
//  WhatTheFlight
//
//  Siri and Spotlight over the logbook (iPhone / iPad): "Have I seen this plane before?",
//  "How many planes have I seen today?", and every aircraft in the logbook as a Spotlight
//  result that opens its page.
//

#if os(iOS)
import AppIntents
import CoreSpotlight
import UniformTypeIdentifiers

/// The app's open logbook, for intents that run while it's alive; otherwise read from disk.
@MainActor
enum LogbookAccess {
    static weak var live: Logbook?

    static func current() -> Logbook { live ?? Logbook(device: .current) }
}

struct SeenBeforeIntent: AppIntent {
    static let title: LocalizedStringResource = "Have I Seen This Plane Before?"
    static let description = IntentDescription("Checks your logbook for the aircraft nearest you, or a tail number or flight you name.")
    static let openAppWhenRun = false

    @Parameter(title: "Aircraft", description: "A tail number or flight, like N608AT or DAL1751. Leave it empty for the aircraft nearest you.")
    var aircraft: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Have I seen \(\.$aircraft) before?")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let logbook = LogbookAccess.current()
        if let aircraft, !aircraft.trimmingCharacters(in: .whitespaces).isEmpty {
            return .result(dialog: IntentDialog(stringLiteral: LogbookAnswers.seenBefore(aircraft, in: logbook.sightings)))
        }
        let store = SharedRadarStore()
        guard let observer = store.observer else {
            return .result(dialog: "Open What The Flight? once so I know where you're watching from.")
        }
        guard let nearest = try? await NearbyTraffic.contacts(around: observer, radiusMiles: store.radiusMiles).first else {
            return .result(dialog: "I can't see anything flying near you right now.")
        }
        let f = nearest.flight
        let key = f.registration ?? f.hex ?? f.callsign ?? f.displayIdentifier
        let name = SpokenTraffic.spokenName(f)
        let answer = LogbookAnswers.seenBefore(key, label: name, in: logbook.sightings, excluding: f.id)
        return .result(dialog: IntentDialog(stringLiteral: "The nearest is \(name). \(answer)"))
    }
}

struct LogbookTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "Planes Seen Today"
    static let description = IntentDescription("How many aircraft you've logged today, any new types, and the closest pass.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let logbook = LogbookAccess.current()
        return .result(dialog: IntentDialog(stringLiteral: LogbookAnswers.today(DailyRecap(logbook.sightings))))
    }
}

/// Every airframe in the logbook as a Spotlight result ("N608AT · Boeing 717 · Delta · seen
/// 4×"), reindexed when the app goes to the background after the logbook grew.
@MainActor
enum LogbookSpotlight {
    nonisolated static let domain = "airframe"
    nonisolated static let prefix = "airframe:"
    /// The most recently seen airframes; Spotlight is for finding, not archiving.
    nonisolated static let limit = 2_000
    private static var indexedCount = -1

    static func reindex(_ logbook: Logbook, enabled: Bool) {
        let index = CSSearchableIndex.default()
        guard enabled else {
            if indexedCount != 0 { index.deleteSearchableItems(withDomainIdentifiers: [domain]) }
            indexedCount = 0
            return
        }
        let sightings = logbook.sightings
        guard sightings.count != indexedCount else { return }
        indexedCount = sightings.count
        Task.detached(priority: .utility) {
            let items = makeItems(sightings)
            do {
                try await index.deleteSearchableItems(withDomainIdentifiers: [domain])
                try await index.indexSearchableItems(items)
            } catch {
                Log.logbook.error("Spotlight indexing failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    nonisolated static func makeItems(_ sightings: [Sighting]) -> [CSSearchableItem] {
        var visits: [String: [Sighting]] = [:]
        for s in sightings { if let a = s.airframe { visits[a, default: []].append(s) } }
        let recent = visits.sorted { ($0.value.last?.lastSeen ?? .distantPast) > ($1.value.last?.lastSeen ?? .distantPast) }.prefix(limit)
        return recent.map { airframe, list in
            let latest = list.last!
            let attributes = CSSearchableItemAttributeSet(contentType: .content)
            attributes.title = airframe
            attributes.displayName = airframe
            let seen = list.count == 1 ? "seen once" : "seen \(list.count)×"
            attributes.contentDescription = [latest.typeName ?? latest.typeCode, latest.operatorName, seen,
                                             "last \(latest.lastSeen.formatted(date: .abbreviated, time: .omitted))"]
                .compactMap { $0 }.joined(separator: " · ")
            attributes.keywords = Array(Set([airframe, latest.hex, latest.typeCode, latest.typeName, latest.operatorName]
                .compactMap { $0 } + list.compactMap(\.callsign) + list.map(\.displayIdentifier)))
            attributes.lastUsedDate = latest.lastSeen
            let item = CSSearchableItem(uniqueIdentifier: prefix + airframe, domainIdentifier: domain, attributeSet: attributes)
            item.expirationDate = .distantFuture
            return item
        }
    }

    /// The airframe a Spotlight result stands for.
    static func airframe(fromIdentifier id: String) -> String? {
        id.hasPrefix(prefix) ? String(id.dropFirst(prefix.count)) : nil
    }
}
#endif
