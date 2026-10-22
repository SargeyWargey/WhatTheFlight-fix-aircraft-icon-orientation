//
//  AppIconChoice.swift
//  WhatTheFlight
//
//  The Home Screen icons you can pick in Settings (iPhone, iPad). Automatic is the primary
//  icon, which follows light and dark mode; the rest are `AppIcon-<name>.appiconset`
//  alternates, and the picker shows the `IconPreview-<name>` images. Art source: `AppIcons/`
//  at the repo root. No tvOS alternates: App Store Connect rejects image-stack alternates.
//

#if os(iOS)
import UIKit

enum AppIconChoice: String, CaseIterable, Identifiable, Sendable {
    case automatic, contrailLight, contrailDark, signalRed
    case edgeRadar, nightScope, overhead, compass, perimeter, skyView
    case classic

    var id: String { rawValue }

    enum Group: String, CaseIterable, Identifiable {
        case contrail = "Question Contrail"
        case concepts = "More Icons"
        case classic = "Classic"
        var id: String { rawValue }
    }

    var group: Group {
        switch self {
        case .automatic, .contrailLight, .contrailDark, .signalRed: return .contrail
        case .edgeRadar, .nightScope, .overhead, .compass, .perimeter, .skyView: return .concepts
        case .classic: return .classic
        }
    }

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .contrailLight: return "Teal"
        case .contrailDark: return "Night"
        case .signalRed: return "Signal Red"
        case .edgeRadar: return "Edge Radar"
        case .nightScope: return "Night Scope"
        case .overhead: return "Overhead"
        case .compass: return "Compass"
        case .perimeter: return "Perimeter"
        case .skyView: return "Sky View"
        case .classic: return "Classic"
        }
    }

    var subtitle: String {
        switch self {
        case .automatic: return "Teal in light mode, night in dark mode"
        case .contrailLight: return "Always teal"
        case .contrailDark: return "Always night"
        case .signalRed: return "The radar's red"
        case .edgeRadar: return "The radar on paper"
        case .nightScope: return "A glowing sweep"
        case .overhead: return "Looking straight up"
        case .compass: return "The compass bezel"
        case .perimeter: return "Aircraft on the edge"
        case .skyView: return "Through the camera"
        case .classic: return "The original icon"
        }
    }

    private var assetSuffix: String {
        switch self {
        case .automatic: return "Automatic"
        case .contrailLight: return "ContrailLight"
        case .contrailDark: return "ContrailDark"
        case .signalRed: return "SignalRed"
        case .edgeRadar: return "EdgeRadar"
        case .nightScope: return "NightScope"
        case .overhead: return "Overhead"
        case .compass: return "Compass"
        case .perimeter: return "Perimeter"
        case .skyView: return "SkyView"
        case .classic: return "Classic"
        }
    }

    /// nil is the primary icon.
    var iconName: String? {
        guard self != .automatic else { return nil }
        return "AppIcon-\(assetSuffix)"
    }

    var previewName: String { "IconPreview-\(assetSuffix)" }

    @MainActor
    static var current: AppIconChoice {
        let name = UIApplication.shared.alternateIconName
        return allCases.first { $0.iconName == name } ?? .automatic
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
        var errorDescription: String? { "This device can't change the app icon." }
    }
}
#endif
