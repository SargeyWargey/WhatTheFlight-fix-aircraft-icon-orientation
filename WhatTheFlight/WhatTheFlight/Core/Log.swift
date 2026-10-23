//
//  Log.swift
//  WhatTheFlight
//
//  Unified logging (`os.Logger`), one category per area, for what otherwise fails quietly:
//  feed errors and back-off, logbook saves, the Apple TV and Watch links, the camera.
//  Xcode's console shows each message with its file and line; Console.app filters with
//  `subsystem:SargeyWargey.WhatTheFlight category:feed`.
//
//  Levels: `.debug` for chatter (not kept), `.info` for state changes, `.notice` for things
//  worth reading later, `.error` for failures, `.fault` for bugs and data at risk. Interpolated
//  strings are private in release logs unless marked `privacy: .public`; keep coordinates
//  and names private.
//

import os

enum Log {
    static let subsystem = "SargeyWargey.WhatTheFlight"

    /// Polling the traffic feed, pin lookups, searches.
    static let feed = Logger(subsystem: subsystem, category: "feed")
    /// The logbook file, Sky View photos in it.
    static let logbook = Logger(subsystem: subsystem, category: "logbook")
    /// iCloud: logbook and pin sync.
    static let sync = Logger(subsystem: subsystem, category: "sync")
    /// The iPhone → Apple TV hand-off and the Apple Watch connection.
    static let link = Logger(subsystem: subsystem, category: "link")
    /// Location, compass and motion.
    static let sensors = Logger(subsystem: subsystem, category: "sensors")
    /// Sky View's camera and saving photos.
    static let camera = Logger(subsystem: subsystem, category: "camera")
    /// Sky Watch, alerts and notifications.
    static let alerts = Logger(subsystem: subsystem, category: "alerts")
    /// Drawing: the topography shader, the app icon.
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
