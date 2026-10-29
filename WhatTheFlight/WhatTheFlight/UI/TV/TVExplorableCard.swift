//
//  TVExplorableCard.swift
//  WhatTheFlight
//
//  Charts the Siri Remote can explore: the Stats tab's altitude-vs-speed chart and route web.
//  On the page a chart is a card like any other: it lifts when focus reaches it, and the
//  arrows carry on between cards. A click opens it full screen (`TVChartExplorer`), where the
//  chart is the only thing the remote can land on, so every arrow moves the pick inside it;
//  back closes whatever's open inside, then returns to the page.
//

#if os(tvOS)
import SwiftUI

struct TVExplorableCard<Card: View, Explorer: View>: View {
    @Binding var isExploring: Bool
    @ViewBuilder var card: Card
    @ViewBuilder var explorer: Explorer

    @FocusState private var focused: Bool
    @Environment(\.topographyStyle) private var topographyStyle

    var body: some View {
        Button { isExploring = true } label: {
            card
                .padding(28)
                // Fills its row's height too, so two cards side by side match.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                // TVChartCard's look, so it lifts like the cards around it.
                .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Palette.paperShade.opacity(focused ? 0.6 : 0.35)))
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Palette.ink, lineWidth: focused ? 4 : 0))
                .scaleEffect(focused ? 1.02 : 1)
                .shadow(color: .black.opacity(focused ? 0.2 : 0), radius: 20, y: 10)
                .animation(.snappy(duration: 0.18), value: focused)
        }
        .buttonStyle(TVQuietButtonStyle())
        .focused($focused)
        .accessibilityHint("Click to explore the chart.")
        .fullScreenCover(isPresented: $isExploring) {
            explorer
                .environment(\.topographyStyle, topographyStyle)
        }
        // Back on the page, focus returns here: also what a view opened from the chart (the
        // route web's flights) comes back to.
        .onChange(of: isExploring) { _, exploring in
            if !exploring { focused = true }
        }
    }
}

/// A chart full screen, to explore with the remote. The chart is the only thing focus can
/// land on, so every arrow reaches `move`; a click calls `select`. Back calls `back`, which
/// closes anything open inside the chart and returns true, or returns false to go back to
/// the page.
struct TVChartExplorer<Content: View>: View {
    let title: LocalizedStringKey
    var detail: String? = nil
    let hint: LocalizedStringKey
    var move: (ChartDirection) -> Void
    var select: () -> Void
    var back: () -> Bool = { false }
    /// What VoiceOver says about the pick.
    var spoken: () -> String = { "" }
    @ViewBuilder var content: Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LogbookBackdrop()
            VStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.mono(48, .heavy))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    if let detail {
                        Text(detail)
                            .font(.mono(26, .bold))
                            .foregroundStyle(Palette.value)
                    }
                }
                Button(action: select) {
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .buttonStyle(TVQuietButtonStyle())
                .onMoveCommand { direction in
                    switch direction {
                    case .left: move(.left)
                    case .right: move(.right)
                    case .up: move(.up)
                    case .down: move(.down)
                    @unknown default: break
                    }
                }
                .accessibilityLabel(title)
                .accessibilityValue(spoken())
                Text(hint)
                    .font(.mono(22))
                    .foregroundStyle(Palette.caption)
            }
            .padding(.horizontal, 100)
            .padding(.vertical, 60)
        }
        .onExitCommand {
            if !back() { dismiss() }
        }
    }
}
#endif
