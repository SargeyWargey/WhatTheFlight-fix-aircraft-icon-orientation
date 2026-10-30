//
//  WidgetGallery.swift
//  WhatTheFlight
//
//  DEBUG: `-wtf.debugWidgets YES` draws every face of the logbook widgets (Logbook, Badges,
//  Your Sky) at iPhone and iPad widget sizes, from the gallery's sample logbook and from
//  this device's, in light and dark, to tmp/Widgets-<widget>-<sample|live>-<light|dark>.png
//  in the app's container. The faces are the widget extension's own views, compiled into
//  the app for this (see the target's membership exceptions).
//

#if os(iOS) && DEBUG
import SwiftUI
import WidgetKit

enum WidgetGallery {
    private struct Face {
        let family: WidgetFamily
        let size: CGSize
    }

    /// iPhone 17 Pro sizes, and an 11-inch iPad's extra large.
    private static let home: [Face] = [
        Face(family: .systemSmall, size: CGSize(width: 170, height: 170)),
        Face(family: .systemMedium, size: CGSize(width: 364, height: 170)),
        Face(family: .systemLarge, size: CGSize(width: 364, height: 382)),
        Face(family: .systemExtraLarge, size: CGSize(width: 690, height: 330)),
    ]
    private static let lock: [Face] = [
        Face(family: .accessoryCircular, size: CGSize(width: 72, height: 72)),
        Face(family: .accessoryRectangular, size: CGSize(width: 172, height: 76)),
        Face(family: .accessoryInline, size: CGSize(width: 257, height: 26)),
    ]

    private enum Widget: String, CaseIterable {
        case logbook, badges, sky

        var families: Set<WidgetFamily> {
            switch self {
            case .logbook: return [.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline]
            case .badges: return [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline]
            case .sky: return [.systemSmall, .systemMedium, .accessoryCircular]
            }
        }

        var corner: UnitPoint {
            switch self {
            case .logbook: return .topTrailing
            case .badges: return .bottomTrailing
            case .sky: return .center
            }
        }

        @MainActor @ViewBuilder
        func face(_ entry: LogbookEntry, _ family: WidgetFamily) -> some View {
            switch self {
            case .logbook: LogbookStatsView(entry: entry, family: family)
            case .badges: BadgesView(entry: entry, family: family)
            case .sky: SkyClockView(entry: entry, family: family)
            }
        }
    }

    @MainActor
    static func write(live: LogbookSnapshot?, to directory: URL = FileManager.default.temporaryDirectory) {
        let now = Date()
        for (name, snapshot) in [("sample", LogbookSnapshot.sample), ("live", live)] {
            let entry = LogbookEntry(date: now, snapshot: snapshot)
            for widget in Widget.allCases {
                for scheme in [ColorScheme.light, .dark] {
                    let sheet = contactSheet(widget, entry: entry).environment(\.colorScheme, scheme)
                    let renderer = ImageRenderer(content: sheet)
                    renderer.scale = 3
                    let file = directory.appendingPathComponent("Widgets-\(widget.rawValue)-\(name)-\(scheme == .dark ? "dark" : "light").png")
                    try? renderer.uiImage?.pngData()?.write(to: file)
                }
            }
        }
        Log.ui.notice("Widget faces written to \(directory.path, privacy: .public)")
    }

    @MainActor
    private static func contactSheet(_ widget: Widget, entry: LogbookEntry) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(home.filter { widget.families.contains($0.family) }, id: \.family) { face in
                widget.face(entry, face.family)
                    .padding(16)
                    .frame(width: face.size.width, height: face.size.height)
                    .background { LogbookWidgetBackdrop(corner: widget.corner) }
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            HStack(alignment: .center, spacing: 18) {
                ForEach(lock.filter { widget.families.contains($0.family) }, id: \.family) { face in
                    widget.face(entry, face.family)
                        .frame(width: face.size.width, height: face.size.height)
                        .foregroundStyle(.white)
                        .environment(\.colorScheme, .dark)
                        .environment(\.widgetRenderingMode, .vibrant)
                }
            }
            .padding(14)
            .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(20)
        .background(Color(white: 0.5))
    }
}
#endif
