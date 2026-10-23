//
//  WatchApp.swift
//  WhatTheFlightWatch
//
//  WhatTheFlight on Apple Watch: the wrist radar, flight details, Point & Find, and the
//  long-look for traffic alerts the iPhone sends. Radar core, catalogs and feed are shared
//  with the iPhone app (see the target's file membership in the project).
//

import SwiftUI
import WatchKit
import WidgetKit
import UserNotifications

@main
struct WhatTheFlightWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate

    init() {
        Catalogs.warmUp()
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
        WKNotificationScene(controller: TrafficNotificationController.self, category: TrafficNotification.category)
    }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching() {
        UNUserNotificationCenter.current().delegate = self
        WatchBackgroundRefresh.schedule()
        #if DEBUG
        // Alerts normally come from the iPhone, which owns the permission. To test the
        // long-look with `xcrun simctl push`, launch once with `-wtf.debugNotifications YES`.
        if UserDefaults.standard.bool(forKey: "wtf.debugNotifications") {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        #endif
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            if let refresh = task as? WKApplicationRefreshBackgroundTask {
                // Complications fetch their own traffic; this just asks WidgetKit to let them.
                WidgetCenter.shared.reloadAllTimelines()
                WatchBackgroundRefresh.schedule()
                refresh.setTaskCompletedWithSnapshot(false)
            } else {
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }

    /// Alerts the iPhone forwards while the Watch app is open: the radar already buzzed.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner]
    }

    /// Tapping the notification opens that flight; "Find in the Sky" guides you to it.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let id = response.notification.request.content.userInfo[TrafficNotification.flightIDKey] as? String else { return }
        let find = response.actionIdentifier == TrafficNotification.findAction
        await MainActor.run { WatchRouter.shared.pending = find ? .find(id) : .flight(id) }
    }
}

enum WatchBackgroundRefresh {
    /// Roughly four an hour is what watchOS allows; ask for every 15 minutes.
    static func schedule() {
        WKApplication.shared().scheduleBackgroundRefresh(withPreferredDate: Date().addingTimeInterval(15 * 60), userInfo: nil) { _ in }
    }
}

/// "Open the app at…" from complications, notifications and Siri.
@MainActor
@Observable
final class WatchRouter {
    static let shared = WatchRouter()

    enum Route: Equatable {
        case flight(String)
        /// Find: guide the arm to this aircraft.
        case find(String)
        /// Identify: "what am I pointing at?"
        case identify
        case radar
    }

    var pending: Route?

    /// `whattheflight://flight/<id>`, `whattheflight://sky/<id>` (Find), `whattheflight://sky` (Identify).
    func open(_ url: URL) {
        guard url.scheme == "whattheflight" else { return }
        let id = url.pathComponents.dropFirst().first
        switch url.host() {
        case "flight": pending = id.map { .flight($0) } ?? .radar
        case "sky": pending = id.map { .find($0) } ?? .identify
        default: pending = .radar
        }
    }
}
