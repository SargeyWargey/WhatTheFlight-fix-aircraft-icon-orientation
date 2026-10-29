//
//  DigestNotifier.swift
//  WhatTheFlight
//
//  Schedules the evening digest (Enhancements Spec C9): one local notification at the
//  chosen time on days the logbook grew, rescheduled whenever the app goes to the
//  background so it counts everything seen so far. Tapping it opens the logbook.
//

#if os(iOS)
import Foundation
import UserNotifications

@MainActor
enum DigestNotifier {
    static let identifier = "wtf.digest"
    nonisolated static let routeKey = "route"

    static func reschedule(logbook: Logbook, settings: RadarSettings, now: Date = Date()) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard settings.dailyDigest, settings.keepLogbook,
              let fire = DailyDigest.fireDate(minutes: settings.digestMinutes, on: now),
              let message = DailyDigest.message(for: DailyRecap(logbook.sightings, day: now)) else { return }
        let content = UNMutableNotificationContent()
        content.title = message.title
        content.body = message.body
        content.sound = .default
        content.threadIdentifier = identifier
        content.userInfo = [routeKey: "logbook"]
        content.interruptionLevel = .passive
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let request = UNNotificationRequest(identifier: identifier, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
        center.add(request) { error in
            if let error { Log.alerts.error("Couldn't schedule the digest: \(error.localizedDescription, privacy: .public)") }
        }
    }
}
#endif
