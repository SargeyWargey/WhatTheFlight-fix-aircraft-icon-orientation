//
//  AppRouter.swift
//  WhatTheFlight
//
//  One place for "open the app at…" requests from widgets (URLs), notifications and Siri
//  intents. The root view watches `pending` and presents the right screen.
//
//    whattheflight://flight/<id>   flight details
//    whattheflight://sky           Sky View
//    whattheflight://sky/<id>      Sky View, guiding you to that flight
//    whattheflight://logbook       the logbook
//

#if os(iOS)
import Foundation
import Observation

@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()

    enum Route: Equatable {
        case flight(String)
        /// Sky View guiding you to this aircraft.
        case find(String)
        case sky
        case logbook
        case radar
        case startSkyWatch
    }

    var pending: Route?

    static let scheme = "whattheflight"

    static func url(for route: Route) -> URL {
        switch route {
        case .flight(let id): return URL(string: "\(scheme)://flight/\(id)")!
        case .sky: return URL(string: "\(scheme)://sky")!
        case .find(let id): return URL(string: "\(scheme)://sky/\(id)")!
        case .logbook: return URL(string: "\(scheme)://logbook")!
        case .radar, .startSkyWatch: return URL(string: "\(scheme)://radar")!
        }
    }

    @discardableResult
    func open(_ url: URL) -> Bool {
        guard url.scheme == Self.scheme else { return false }
        switch url.host() {
        case "flight":
            let id = url.pathComponents.dropFirst().first ?? ""
            pending = id.isEmpty ? .radar : .flight(id)
        case "sky":
            let id = url.pathComponents.dropFirst().first ?? ""
            pending = id.isEmpty ? .sky : .find(id)
        case "logbook": pending = .logbook
        default: pending = .radar
        }
        return true
    }
}
#endif
