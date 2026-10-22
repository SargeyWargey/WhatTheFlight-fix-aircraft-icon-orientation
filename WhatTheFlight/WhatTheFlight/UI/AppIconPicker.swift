//
//  AppIconPicker.swift
//  WhatTheFlight
//
//  Settings → Display → App Icon (iPhone, iPad). The Apple TV has no alternate icons: App
//  Store Connect rejects tvOS alternates built from image stacks.
//

#if os(iOS)
import SwiftUI

/// The icon artwork with the platform's corner shape.
struct AppIconPreview: View {
    let choice: AppIconChoice
    var size: CGFloat

    var body: some View {
        Image(choice.previewName)
            .resizable()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous).stroke(.black.opacity(0.1), lineWidth: 0.5))
    }
}

struct AppIconPickerView: View {
    var onChange: (AppIconChoice) -> Void = { _ in }

    @State private var current = AppIconChoice.current
    @State private var problem: String?

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                ForEach(AppIconChoice.Group.allCases) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(group.rawValue).radarCaption()
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                            ForEach(AppIconChoice.allCases.filter { $0.group == group }) { choice in
                                Button { select(choice) } label: { cell(choice) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
                if let problem {
                    Text(problem).font(.mono(12)).foregroundStyle(Palette.warning)
                }
            }
            .padding(20)
        }
        .background(Palette.paper.ignoresSafeArea())
        .navigationTitle("App Icon")
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.monospaced)
    }

    private func cell(_ choice: AppIconChoice) -> some View {
        let selected = choice == current
        return VStack(spacing: 6) {
            AppIconPreview(choice: choice, size: 72)
                .padding(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(selected ? Palette.ink : .clear, lineWidth: 2.5)
                )
            Text(choice.title)
                .font(.mono(12, .bold))
                .foregroundStyle(selected ? Palette.ink : Palette.value)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(choice.subtitle)
                .font(.mono(9))
                .foregroundStyle(Palette.caption)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(height: 24, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(choice.title), \(choice.subtitle)")
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
