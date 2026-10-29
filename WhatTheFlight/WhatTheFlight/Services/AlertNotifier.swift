//
//  AlertNotifier.swift
//  WhatTheFlight
//
//  Delivers traffic alerts as local notifications while the app runs in the background
//  (during Sky Watch). Tapping one opens that flight. The aircraft rides along in the
//  payload so Apple Watch can draw its own notification (category `wtf.traffic`).
//

#if os(iOS)
import Foundation
import UserNotifications

enum AlertNotifier {
    static let category = TrafficNotification.category
    static let flightKey = TrafficNotification.flightKey
    static let findAction = TrafficNotification.findAction

    /// Registered at launch. Apple Watch shows the same action under its own notification,
    /// where it opens Point & Find instead of Sky View.
    static var trafficCategory: UNNotificationCategory {
        let find = UNNotificationAction(identifier: findAction, title: "Find in the Sky", options: [.foreground],
                                        icon: UNNotificationActionIcon(systemImageName: "scope"))
        return UNNotificationCategory(identifier: category, actions: [find], intentIdentifiers: [])
    }

    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        default: return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
    }

    static func deliver(_ alert: TrafficAlert) {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        content.threadIdentifier = alert.reason.rawValue
        content.categoryIdentifier = category
        var info: [String: Any] = [TrafficNotification.flightIDKey: alert.flightID, "reason": alert.reason.rawValue]
        if let flight = alert.flight, let data = try? JSONEncoder().encode(flight) {
            info[flightKey] = String(decoding: data, as: UTF8.self)
        }
        content.userInfo = info
        content.interruptionLevel = alert.reason == .overhead ? .timeSensitive : .active
        let request = UNNotificationRequest(identifier: alert.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { Log.alerts.error("Couldn't post the alert: \(error.localizedDescription, privacy: .public)") }
        }
    }
}

/// Routes notification taps to the flight; shows banners even while the app is open.
final class AlertNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        if info[DigestNotifier.routeKey] as? String == "logbook" {
            await MainActor.run { AppRouter.shared.pending = .logbook }
            return
        }
        guard let id = info["flightID"] as? String else { return }
        let find = response.actionIdentifier == AlertNotifier.findAction
        await MainActor.run { AppRouter.shared.pending = find ? .find(id) : .flight(id) }
    }
}
#endif
