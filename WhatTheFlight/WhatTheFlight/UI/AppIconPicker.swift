//
//  AppIconPicker.swift
//  WhatTheFlight
//
//  Settings → Display → App Icon (iPhone, iPad): one Automatic / Light / Dark switch, then
//  every concept in its group. Picking a concept applies it in the switch's look; moving the
//  switch re-dresses the icon you have. The Apple TV has no alternate icons: App Store
//  Connect rejects tvOS alternates built from image stacks.
//

#if os(iOS)
import SwiftUI

/// The icon artwork with the platform's corner shape, in the choice's look.
struct AppIconPreview: View {
    let choice: AppIconChoice
    var size: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
        Group {
            if let dark = choice.previewIsDark {
                // The preview image's own light or dark appearance, whatever the screen's.
                Image(choice.previewName).resizable().environment(\.colorScheme, dark ? .dark : .light)
            } else {
                Image(choice.previewName).resizable()
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.stroke(.black.opacity(0.1), lineWidth: 0.5))
    }
}

struct AppIconPickerView: View {
    var onChange: (AppIconChoice) -> Void = { _ in }

    @State private var current = AppIconChoice.current
    @State private var look = AppIconChoice.current.look
    @State private var problem: String?

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Look", selection: $look) {
                        ForEach(AppIconChoice.Look.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text(lookFooter)
                        .font(.footnote)
                        .foregroundStyle(Palette.caption)
                }
                ForEach(AppIconConcept.Group.allCases) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(group.title).radarCaption(scales: true)
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                            ForEach(AppIconConcept.allCases.filter { $0.group == group }) { concept in
                                Button { select(AppIconChoice(concept, look)) } label: { cell(concept) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
                if let problem {
                    Text(problem).font(.footnote).foregroundStyle(Palette.warning)
                }
            }
            .padding(20)
        }
        .background(Palette.paper.ignoresSafeArea())
        .navigationTitle("App Icon")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: look) { _, newLook in
            let next = AppIconChoice(current.concept, newLook)
            if next != current { select(next) }
        }
    }

    private var lookFooter: String {
        let tinted = String(localized: "A tinted Home Screen always shows the tinted version.")
        switch look {
        case .automatic: return String(localized: "Each icon follows your Home Screen's light or dark setting.") + " " + tinted
        case .light: return String(localized: "Each icon stays light, even on a dark Home Screen.") + " " + tinted
        case .dark: return String(localized: "Each icon stays dark, even on a light Home Screen.") + " " + tinted
        }
    }

    private func cell(_ concept: AppIconConcept) -> some View {
        let choice = AppIconChoice(concept, look)
        let selected = concept == current.concept
        // Round 1, Signal Red and Classic only come in Automatic.
        let subtitle = choice.look == look ? concept.subtitle : String(localized: "Follows your Home Screen")
        return VStack(spacing: 6) {
            AppIconPreview(choice: choice, size: 72)
                .padding(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(selected ? Palette.ink : .clear, lineWidth: 2.5)
                )
            Text(concept.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(selected ? Palette.ink : Palette.value)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(Palette.caption)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(height: 28, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(choice.title), \(subtitle)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func select(_ choice: AppIconChoice) {
        problem = nil
        Task {
            do {
                try await choice.apply()
                current = choice
                onChange(choice)
            } catch {
                problem = error.localizedDescription
            }
        }
    }
}
#endif
