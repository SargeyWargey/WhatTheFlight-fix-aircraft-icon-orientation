//
//  AppIconChoice.swift
//  WhatTheFlight
//
//  The Home Screen icons you can pick in Settings (iPhone, iPad): a concept (Question
//  Contrail, Interrobang, Tally…) in a look. Automatic follows the Home Screen's light or dark
//  setting; Light and Dark keep that version whatever it's set to (those icon sets have no
//  dark slot, so iOS has nothing to swap in). Tinted Home Screens always get the tinted art.
//
//  The primary icon is Question Contrail, Automatic; everything else is an
//  `AppIcon-<name>.appiconset` alternate (`ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS`),
//  and the picker shows the `IconPreview-<name>` images, which carry a dark appearance for the
//  dark look. Art sources: `AppIcons/` at the repo root (round 3: `AppIcons/Round 3`, rendered
//  into the catalog by its `render.sh`). No tvOS alternates: App Store Connect rejects
//  image-stack alternates.
//

#if os(iOS)
import UIKit

enum AppIconConcept: String, CaseIterable, Identifiable, Sendable {
    // Question Contrail
    case contrail, signalRed
    // Round 3: playful
    case interrobang, cloudMark, wideEyed, loopTheLoop, doubleTake, tailFin, departureBoard, birdOrPlane
    // Round 3: aircraft and stats
    case trendContrail, skyByTheHour, headingRose, tally, badgeRing, collection
    // Round 1
    case edgeRadar, nightScope, overhead, compass, perimeter, skyView
    case classic

    var id: String { rawValue }

    enum Group: String, CaseIterable, Identifiable {
        case contrail, playful, stats, more, classic
        var id: String { rawValue }

        var title: String {
            switch self {
            case .contrail: return String(localized: "Question Contrail")
            case .playful: return String(localized: "What the…?!")
            case .stats: return String(localized: "Planes by the Numbers")
            case .more: return String(localized: "More Icons")
            case .classic: return String(localized: "Classic")
            }
        }
    }

    var group: Group {
        switch self {
        case .contrail, .signalRed: return .contrail
        case .interrobang, .cloudMark, .wideEyed, .loopTheLoop, .doubleTake, .tailFin, .departureBoard, .birdOrPlane: return .playful
        case .trendContrail, .skyByTheHour, .headingRose, .tally, .badgeRing, .collection: return .stats
        case .edgeRadar, .nightScope, .overhead, .compass, .perimeter, .skyView: return .more
        case .classic: return .classic
        }
    }

    var title: String {
        switch self {
        case .contrail: return String(localized: "Teal & Coral")
        case .signalRed: return String(localized: "Signal Red")
        case .interrobang: return String(localized: "Interrobang")
        case .cloudMark: return String(localized: "Cloud Mark")
        case .wideEyed: return String(localized: "Wide-Eyed")
        case .loopTheLoop: return String(localized: "Loop-the-Loop")
        case .doubleTake: return String(localized: "Double Take")
        case .tailFin: return String(localized: "Tail Fin")
        case .departureBoard: return String(localized: "Departure Board")
        case .birdOrPlane: return String(localized: "Bird or Plane?")
        case .trendContrail: return String(localized: "Trend Contrail")
        case .skyByTheHour: return String(localized: "Sky by the Hour")
        case .headingRose: return String(localized: "Heading Rose")
        case .tally: return String(localized: "Tally")
        case .badgeRing: return String(localized: "Badge Ring")
        case .collection: return String(localized: "Collection")
        case .edgeRadar: return String(localized: "Edge Radar")
        case .nightScope: return String(localized: "Night Scope")
        case .overhead: return String(localized: "Overhead")
        case .compass: return String(localized: "Compass")
        case .perimeter: return String(localized: "Perimeter")
        case .skyView: return String(localized: "Sky View")
        case .classic: return String(localized: "Classic")
        }
    }

    var subtitle: String {
        switch self {
        case .contrail: return String(localized: "Today's icon")
        case .signalRed: return String(localized: "The radar's red")
        case .interrobang: return String(localized: "Contrails that say ?!")
        case .cloudMark: return String(localized: "A cloud question mark")
        case .wideEyed: return String(localized: "A startled airliner")
        case .loopTheLoop: return String(localized: "A show-off paper plane")
        case .doubleTake: return String(localized: "Look up, look twice")
        case .tailFin: return String(localized: "The airline of ?")
        case .departureBoard: return String(localized: "Flight: ?")
        case .birdOrPlane: return String(localized: "The spotter's joke")
        case .trendContrail: return String(localized: "Up and to the right")
        case .skyByTheHour: return String(localized: "Your sky, hour by hour")
        case .headingRose: return String(localized: "Which way they fly")
        case .tally: return String(localized: "Counting planes")
        case .badgeRing: return String(localized: "Plane Spotter, level 3")
        case .collection: return String(localized: "Six down, three to go")
        case .edgeRadar: return String(localized: "The radar on paper")
        case .nightScope: return String(localized: "A glowing sweep")
        case .overhead: return String(localized: "Looking straight up")
        case .compass: return String(localized: "The compass bezel")
        case .perimeter: return String(localized: "Aircraft on the edge")
        case .skyView: return String(localized: "Through the camera")
        case .classic: return String(localized: "The original icon")
        }
    }

    /// The asset name stem: `AppIcon-<stem>[Light|Dark]`, `IconPreview-<stem>`.
    fileprivate var stem: String {
        switch self {
        case .contrail: return "Contrail"
        case .signalRed: return "SignalRed"
        case .interrobang: return "Interrobang"
        case .cloudMark: return "CloudMark"
        case .wideEyed: return "WideEyed"
        case .loopTheLoop: return "LoopTheLoop"
        case .doubleTake: return "DoubleTake"
        case .tailFin: return "TailFin"
        case .departureBoard: return "DepartureBoard"
        case .birdOrPlane: return "BirdOrPlane"
        case .trendContrail: return "TrendContrail"
        case .skyByTheHour: return "SkyByTheHour"
        case .headingRose: return "HeadingRose"
        case .tally: return "Tally"
        case .badgeRing: return "BadgeRing"
        case .collection: return "Collection"
        case .edgeRadar: return "EdgeRadar"
        case .nightScope: return "NightScope"
        case .overhead: return "Overhead"
        case .compass: return "Compass"
        case .perimeter: return "Perimeter"
        case .skyView: return "SkyView"
        case .classic: return "Classic"
        }
    }

    /// The looks it comes in. Round 1, Signal Red and Classic were only drawn to follow the
    /// Home Screen (Classic has one look whatever the setting).
    var looks: [AppIconChoice.Look] {
        switch self {
        case .signalRed, .edgeRadar, .nightScope, .overhead, .compass, .perimeter, .skyView, .classic: return [.automatic]
        default: return AppIconChoice.Look.allCases
        }
    }
}

struct AppIconChoice: Hashable, Identifiable, Sendable {
    enum Look: String, CaseIterable, Identifiable, Sendable {
        case automatic, light, dark
        var id: String { rawValue }

        var title: String {
            switch self {
            case .automatic: return String(localized: "Automatic")
            case .light: return String(localized: "Light")
            case .dark: return String(localized: "Dark")
            }
        }
    }

    let concept: AppIconConcept
    let look: Look

    var id: String { "\(concept.rawValue).\(look.rawValue)" }

    /// Falls back to Automatic for a concept drawn in one look only.
    init(_ concept: AppIconConcept, _ look: Look = .automatic) {
        self.concept = concept
        self.look = concept.looks.contains(look) ? look : .automatic
    }

    static let primary = AppIconChoice(.contrail)

    static var all: [AppIconChoice] {
        AppIconConcept.allCases.flatMap { concept in concept.looks.map { AppIconChoice(concept, $0) } }
    }

    /// "Interrobang", or "Interrobang · Dark" for a fixed look.
    var title: String {
        guard concept.looks.count > 1, look != .automatic else { return concept.title }
        return "\(concept.title) · \(look.title)"
    }

    /// nil is the primary icon. Teal & Coral's fixed looks keep their original names.
    var iconName: String? {
        switch (concept, look) {
        case (.contrail, .automatic): return nil
        case (.contrail, .light): return "AppIcon-ContrailLight"
        case (.contrail, .dark): return "AppIcon-ContrailDark"
        case (_, .automatic): return "AppIcon-\(concept.stem)"
        case (_, .light): return "AppIcon-\(concept.stem)Light"
        case (_, .dark): return "AppIcon-\(concept.stem)Dark"
        }
    }

    /// The preview image; `previewScheme` picks its light or dark appearance (nil follows the
    /// screen, like Automatic does).
    var previewName: String {
        switch (concept, look) {
        case (.contrail, .automatic): return "IconPreview-Automatic"
        case (.contrail, .light): return "IconPreview-ContrailLight"
        case (.contrail, .dark): return "IconPreview-ContrailDark"
        default: return "IconPreview-\(concept.stem)"
        }
    }

    var previewIsDark: Bool? {
        switch look {
        case .automatic: return nil
        case .light: return false
        case .dark: return true
        }
    }

    @MainActor
    static var current: AppIconChoice {
        let name = UIApplication.shared.alternateIconName
        return all.first { $0.iconName == name } ?? .primary
    }

    /// `-wtf.debugIcon`: `interrobang`, `tally.dark`, or the old names (`automatic`,
    /// `contrailLight`, `contrailDark`, `edgeRadar`…).
    init?(debugName: String) {
        switch debugName {
        case "automatic": self = .primary
        case "contrailLight": self.init(.contrail, .light)
        case "contrailDark": self.init(.contrail, .dark)
        default:
            let parts = debugName.split(separator: ".").map(String.init)
            guard let concept = AppIconConcept(rawValue: parts[0]) else { return nil }
            self.init(concept, parts.count > 1 ? Look(rawValue: parts[1]) ?? .automatic : .automatic)
        }
    }

    /// The system confirms the change with its own alert.
    @MainActor
    func apply() async throws {
        guard UIApplication.shared.supportsAlternateIcons else { throw IconError.unsupported }
        guard UIApplication.shared.alternateIconName != iconName else { return }
        try await UIApplication.shared.setAlternateIconName(iconName)
    }

    enum IconError: LocalizedError {
        case unsupported
        var errorDescription: String? { String(localized: "This device can't change the app icon.") }
    }
}
#endif
