//
//  LogbookWidgetPublisher.swift
//  WhatTheFlight
//
//  Keeps the logbook widgets' snapshot (`LogbookSnapshot`) fresh. The digest is rebuilt off
//  the main thread after the logbook saves, at most every five minutes while the app is open
//  and every thirty in the background (Sky Watch), where WidgetKit rations reloads; at once
//  when the app leaves the screen, a badge is earned or the units change. Widgets only reload
//  when something they show has changed.
//

#if os(iOS)
import Foundation
import UIKit
import WidgetKit

@MainActor
final class LogbookWidgetPublisher {
    private weak var logbook: Logbook?
    private var lastPublish = Date.distantPast
    private var building: Task<Void, Never>?

    /// Publishes now, then again whenever the logbook saves.
    func attach(_ logbook: Logbook) {
        self.logbook = logbook
        logbook.onSave = { [weak self] in self?.logbookDidSave() }
        publishNow()
    }

    func publishNow() {
        guard let logbook else { return }
        lastPublish = Date()
        let sightings = logbook.sightings
        let observer = SharedRadarStore().observer
        building?.cancel()
        building = Task.detached(priority: .utility) {
            let digest = LogbookDigest(sightings, now: Date())
            guard !Task.isCancelled else { return }
            let snapshot = LogbookSnapshot(digest: digest, observer: observer)
            let store = SharedRadarStore()
            if let old = store.logbook, old == snapshot.built(at: old.builtAt) { return }
            store.logbook = snapshot
            for kind in SharedRadarStore.logbookKinds { WidgetCenter.shared.reloadTimelines(ofKind: kind) }
        }
    }

    private func logbookDidSave() {
        let gap: TimeInterval = UIApplication.shared.applicationState == .background ? 30 * 60 : 5 * 60
        guard Date().timeIntervalSince(lastPublish) > gap else { return }
        publishNow()
    }
}
#endif
