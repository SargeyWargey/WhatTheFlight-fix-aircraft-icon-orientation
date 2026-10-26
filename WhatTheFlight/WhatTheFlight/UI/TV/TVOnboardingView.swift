//
//  TVOnboardingView.swift
//  WhatTheFlight
//
//  The first-run tour on the big screen (pages and drawings in `Onboarding.swift`).
//
//  Siri Remote
//    ◀ ▶  previous / next page        click  continue        MENU  back a page (skips on the first)
//
//  The last page sends you on: set a location, try demo traffic, or start watching.
//

#if os(tvOS)
import SwiftUI

struct TVOnboardingView: View {
    enum Exit { case start, setLocation, demo }

    /// The radar already has a place to watch, so the last page can just start.
    let hasLocation: Bool
    /// "Atlanta, GA", for the last page when a place is already set.
    var placeName: String? = nil
    var showTopography = true
    let onExit: (Exit) -> Void

    private enum Focus: Hashable { case next, skip, primary, secondary }

    #if DEBUG
    /// `-wtf.debugTourPage 3` opens the tour on that page (screenshots).
    @State private var page = min(max(UserDefaults.standard.integer(forKey: "wtf.debugTourPage"), 0), TourPage.pages(for: .tv).count - 1)
    #else
    @State private var page = 0
    #endif
    @State private var forward = true
    @FocusState private var focus: Focus?

    private let pages = TourPage.pages(for: .tv)
    private var isLast: Bool { page == pages.count - 1 }

    var body: some View {
        let item = pages[page]
        VStack(spacing: 0) {
            HStack(spacing: 90) {
                TourArt(art: item.art, unit: 2.1)
                    .frame(width: 760, height: 640)
                    .id(item.id)
                    .transition(slide)

                VStack(alignment: .leading, spacing: 22) {
                    Text(item.eyebrow).radarCaptionTV()
                    Text(item.art == .ready && hasLocation ? "Ready when you are" : item.title)
                        .font(.mono(56, .heavy))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(bodyText(item))
                        .font(.mono(27))
                        .foregroundStyle(Palette.value)
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                    buttons
                        .padding(.top, 30)
                }
                .id("text-\(item.id)")
                .transition(slide)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 40) {
                TourDots(count: pages.count, current: page, unit: 1.8)
                Spacer()
                Text(isLast ? "◀ Back" : "◀ ▶ Move through the tour")
                    .font(.mono(20, .semibold))
                    .foregroundStyle(Palette.caption)
            }
        }
        .padding(.horizontal, 100)
        .padding(.vertical, 60)
        .background(RadarBackdrop(showTopography: showTopography, showSweep: false, isActive: true).ignoresSafeArea())
        .defaultFocus($focus, isLast ? .primary : .next)
        .onExitCommand {
            if page > 0 { go(-1) } else { onExit(hasLocation ? .start : .setLocation) }
        }
    }

    /// The last page asks for a place, unless the radar already has one.
    private func bodyText(_ item: TourPage) -> String {
        guard item.art == .ready, hasLocation else { return item.body }
        return "The radar is watching \(placeName ?? "your spot"). Change it any time in Settings, or send a new spot from the iPhone app."
    }

    private var slide: AnyTransition {
        .asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity))
    }

    @ViewBuilder
    private var buttons: some View {
        if isLast {
            VStack(alignment: .leading, spacing: 24) {
                if hasLocation {
                    pageButton("Start Watching", symbol: "dot.radiowaves.left.and.right", prominent: true, focus: .primary) { onExit(.start) }
                    pageButton("Change Location", symbol: "mappin.and.ellipse", prominent: false, focus: .secondary) { onExit(.setLocation) }
                } else {
                    pageButton("Set Location", symbol: "mappin.and.ellipse", prominent: true, focus: .primary) { onExit(.setLocation) }
                    pageButton("Try Demo Traffic", symbol: "sparkles", prominent: false, focus: .secondary) { onExit(.demo) }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 24) {
                pageButton("Continue", symbol: "arrow.right", prominent: true, focus: .next) { go(1) }
                pageButton("Skip Tour", symbol: "forward.end.fill", prominent: false, focus: .skip) { go(pages.count - 1 - page) }
            }
        }
    }

    private func pageButton(_ title: String, symbol: String, prominent: Bool, focus target: Focus, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
        }
        .buttonStyle(TVPillButtonStyle(prominent: prominent))
        .focused($focus, equals: target)
        .onMoveCommand { direction in
            switch direction {
            case .left: go(-1)
            case .right where !isLast: go(1)
            default: break
            }
        }
    }

    private func go(_ delta: Int) {
        let target = min(max(page + delta, 0), pages.count - 1)
        guard target != page else { return }
        forward = delta > 0
        withAnimation(.smooth(duration: 0.4)) { page = target }
        // The page's buttons are new views: put focus back on the obvious next step.
        Task { @MainActor in focus = target == pages.count - 1 ? .primary : .next }
    }
}
#endif
