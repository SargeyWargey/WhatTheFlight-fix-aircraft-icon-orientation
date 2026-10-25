//
//  ComplicationGallery.swift
//  WhatTheFlightWatch
//
//  DEBUG: every complication in every family on sample traffic, about the size a 46 mm
//  face draws them, for screenshots without editing a watch face. Launch with
//  `-wtf.debugScreen complications` (and `-wtf.debugComplications nearest|radar|next|identify|states`
//  for a page). Curved corner labels and tinted faces only exist on a real face, so the
//  gallery prints each corner's label under it and shows full colour.
//

#if DEBUG
import SwiftUI
import WidgetKit

struct ComplicationGallery: View {
    enum Page: String, CaseIterable {
        case nearest, radar, next, identify, states
    }

    @State private var page: Page = Page(rawValue: UserDefaults.standard.string(forKey: "wtf.debugComplications") ?? "") ?? .nearest
    private let entry = ComplicationSamples.entry
    private let passing = ComplicationSamples.passingEntry

    var body: some View {
        TabView(selection: $page) {
            sheet("Nearest Aircraft") {
                row(circular: NearestComplicationView(entry: entry, family: .accessoryCircular),
                    corner: NearestComplicationView(entry: entry, family: .accessoryCorner).cornerContent,
                    label: NearestComplicationView(entry: entry, family: .accessoryCorner).cornerLabel)
                rectangular(NearestComplicationView(entry: entry, family: .accessoryRectangular))
                rectangular(NearestComplicationView(entry: entry, family: .accessoryRectangular), small: true)
                inline(NearestComplicationView(entry: entry, family: .accessoryInline))
            }
            .tag(Page.nearest)
            sheet("Sky Radar") {
                row(circular: SkyRadarComplicationView(entry: entry, family: .accessoryCircular),
                    corner: SkyRadarComplicationView(entry: entry, family: .accessoryCorner).cornerContent,
                    label: SkyRadarComplicationView(entry: entry, family: .accessoryCorner).cornerLabel)
                rectangular(SkyRadarComplicationView(entry: entry, family: .accessoryRectangular))
                rectangular(SkyRadarComplicationView(entry: entry, family: .accessoryRectangular), small: true)
                inline(SkyRadarComplicationView(entry: entry, family: .accessoryInline))
            }
            .tag(Page.radar)
            sheet("Next Overhead") {
                row(circular: NextOverheadComplicationView(entry: entry, family: .accessoryCircular),
                    corner: NextOverheadComplicationView(entry: entry, family: .accessoryCorner).cornerContent,
                    label: NextOverheadComplicationView(entry: entry, family: .accessoryCorner).cornerLabel)
                rectangular(NextOverheadComplicationView(entry: entry, family: .accessoryRectangular))
                rectangular(NextOverheadComplicationView(entry: passing, family: .accessoryRectangular))
                inline(NextOverheadComplicationView(entry: entry, family: .accessoryInline))
            }
            .tag(Page.next)
            sheet("Identify") {
                row(circular: IdentifyComplicationView(family: .accessoryCircular),
                    corner: IdentifyComplicationView(family: .accessoryCorner).cornerContent,
                    label: IdentifyComplicationView(family: .accessoryCorner).cornerLabel)
                inline(IdentifyComplicationView(family: .accessoryInline))
            }
            .tag(Page.identify)
            sheet("States") {
                HStack(spacing: 6) {
                    circle(NextOverheadComplicationView(entry: passing, family: .accessoryCircular))
                    circle(NextOverheadComplicationView(entry: ComplicationSamples.clearEntry, family: .accessoryCircular))
                    circle(SkyRadarComplicationView(entry: ComplicationSamples.clearEntry, family: .accessoryCircular))
                }
                HStack(spacing: 6) {
                    circle(NearestComplicationView(entry: ComplicationSamples.clearEntry, family: .accessoryCircular))
                    circle(NearestComplicationView(entry: ComplicationSamples.setupEntry, family: .accessoryCircular))
                    circle(SkyRadarComplicationView(entry: ComplicationSamples.setupEntry, family: .accessoryCircular))
                }
                rectangular(NearestComplicationView(entry: ComplicationSamples.setupEntry, family: .accessoryRectangular))
            }
            .tag(Page.states)
        }
        .tabViewStyle(.verticalPage)
        .background(Color.black)
    }

    /// Starts below the cover's close button and the clock; the title sits at the foot.
    private func sheet<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            content()
            Text(title.uppercased())
                .font(.mono(8, .heavy))
                .tracking(0.8)
                .foregroundStyle(Palette.faint)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 34)
        .padding(.horizontal, 4)
    }

    private func row<Circular: View, Corner: View>(circular: Circular, corner: Corner, label: Text) -> some View {
        HStack(alignment: .center, spacing: 10) {
            circle(circular)
            corner
                .frame(width: 34, height: 34)
                .outlined(Circle())
            label
                .font(.mono(10, .semibold))
                .foregroundStyle(Palette.value)
                .lineLimit(2)
        }
    }

    private func circle<V: View>(_ view: V) -> some View {
        view.frame(width: 50, height: 50).outlined(Circle())
    }

    /// 46 mm, or 40 mm with `small`.
    private func rectangular<V: View>(_ view: V, small: Bool = false) -> some View {
        view
            .frame(width: small ? 150 : 176, height: small ? 47 : 55)
            .outlined(RoundedRectangle(cornerRadius: 8))
    }

    private func inline<V: View>(_ view: V) -> some View {
        view
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            .frame(width: 176, alignment: .leading)
    }
}

private extension View {
    /// A hairline where the complication's bounds are.
    func outlined<S: Shape>(_ shape: S) -> some View {
        overlay(shape.stroke(Color.white.opacity(0.12), lineWidth: 0.5))
    }
}
#endif
