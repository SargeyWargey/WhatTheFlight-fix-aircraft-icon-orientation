//
//  AlertNotifier.swift
//  WhatTheFlight
//
//  Delivers traffic alerts as local notifications while the app runs in the background
//  (during Sky Watch). Tapping one opens that flight.
//

#if os(iOS)
import Foundation
import UserNotifications

enum AlertNotifier {
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
        content.userInfo = ["flightID": alert.flightID]
        content.interruptionLevel = alert.reason == .overhead ? .timeSensitive : .active
        let request = UNNotificationRequest(identifier: alert.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

/// Routes notification taps to the flight; shows banners even while the app is open.
final class AlertNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let id = response.notification.request.content.userInfo["flightID"] as? String else { return }
        await MainActor.run { AppRouter.shared.pending = .flight(id) }
    }
}
#endif
