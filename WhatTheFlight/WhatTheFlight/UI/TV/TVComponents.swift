//
//  TVComponents.swift
//  WhatTheFlight
//
//  Building blocks for the 10-foot UI. Everything is focus-driven: big targets, an obvious
//  focused state (ink fill + lift), and chip pickers instead of sliders (tvOS has none).
//

#if os(tvOS)
import SwiftUI

// MARK: - Button styles

/// Capsule button for primary actions.
struct TVPillButtonStyle: ButtonStyle {
    var prominent: Bool
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, prominent: prominent, compact: compact)
    }

    private struct Styled: View {
        let configuration: Configuration
        let prominent: Bool
        let compact: Bool
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .font(.mono(compact ? 22 : 26, .bold))
                .labelStyle(TVLabelStyle())
                .padding(.horizontal, compact ? 26 : 36)
                .padding(.vertical, compact ? 14 : 18)
                .foregroundStyle(isFocused ? Color.white : (prominent ? Palette.ink : Palette.value))
                .background(
                    Capsule().fill(isFocused ? Palette.ink : (prominent ? Palette.ink.opacity(0.14) : Palette.paperShade.opacity(0.55)))
                )
                .scaleEffect(configuration.isPressed ? 0.96 : (isFocused ? 1.08 : 1))
                .shadow(color: .black.opacity(isFocused ? 0.28 : 0), radius: 18, y: 10)
                .animation(.snappy(duration: 0.18), value: isFocused)
                .animation(.snappy(duration: 0.12), value: configuration.isPressed)
        }
    }
}

/// Full-width settings row.
struct TVRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration)
    }

    private struct Styled: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .font(.mono(26, .semibold))
                .foregroundStyle(isFocused ? Color.white : Palette.value)
                .environment(\.tvRowFocused, isFocused)
                .padding(.horizontal, 30)
                .padding(.vertical, 22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(isFocused ? Palette.ink : Palette.paperShade.opacity(0.45))
                )
                .scaleEffect(configuration.isPressed ? 0.98 : (isFocused ? 1.025 : 1))
                .shadow(color: .black.opacity(isFocused ? 0.25 : 0), radius: 20, y: 10)
                .animation(.snappy(duration: 0.18), value: isFocused)
        }
    }
}

/// A selectable chip in a row of choices.
struct TVChipButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, isSelected: isSelected)
    }

    private struct Styled: View {
        let configuration: Configuration
        let isSelected: Bool
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .font(.mono(24, .bold))
                .padding(.horizontal, 26)
                .padding(.vertical, 14)
                .foregroundStyle(isFocused ? Color.white : (isSelected ? Palette.ink : Palette.value))
                .background(
                    Capsule().fill(isFocused ? Palette.ink : (isSelected ? Palette.ink.opacity(0.16) : Palette.paperShade.opacity(0.45)))
                )
                .overlay(Capsule().stroke(isSelected && !isFocused ? Palette.ink : .clear, lineWidth: 3))
                .scaleEffect(configuration.isPressed ? 0.95 : (isFocused ? 1.12 : 1))
                .shadow(color: .black.opacity(isFocused ? 0.25 : 0), radius: 14, y: 8)
                .animation(.snappy(duration: 0.18), value: isFocused)
        }
    }
}

/// Large tile for the main setup actions.
struct TVTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration)
    }

    private struct Styled: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .foregroundStyle(isFocused ? Color.white : Palette.value)
                .environment(\.tvRowFocused, isFocused)
                .padding(28)
                .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(isFocused ? Palette.ink : Palette.paperShade.opacity(0.45))
                )
                .scaleEffect(configuration.isPressed ? 0.97 : (isFocused ? 1.05 : 1))
                .shadow(color: .black.opacity(isFocused ? 0.3 : 0), radius: 24, y: 14)
                .animation(.snappy(duration: 0.2), value: isFocused)
        }
    }
}

/// Sidebar entry in Settings.
struct TVSidebarItemStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, isSelected: isSelected)
    }

    private struct Styled: View {
        let configuration: Configuration
        let isSelected: Bool
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .font(.mono(28, .bold))
                .labelStyle(TVLabelStyle())
                .foregroundStyle(isFocused ? Color.white : (isSelected ? Palette.ink : Palette.caption))
                .padding(.horizontal, 26)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(isFocused ? Palette.ink : (isSelected ? Palette.ink.opacity(0.12) : .clear))
                )
                .scaleEffect(isFocused ? 1.04 : 1)
                .animation(.snappy(duration: 0.18), value: isFocused)
        }
    }
}

/// Hero area: focusable but visually quiet — the content *is* the UI.
struct TVQuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
    }
}

struct TVLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 14) {
            configuration.icon
            configuration.title
        }
    }
}

private struct TVRowFocusedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Lets row content recolour secondary text when its row has focus.
    var tvRowFocused: Bool {
        get { self[TVRowFocusedKey.self] }
        set { self[TVRowFocusedKey.self] = newValue }
    }
}

// MARK: - Rows

/// Title on the left, current value on the right. Click toggles / cycles.
struct TVValueRow: View {
    let title: String
    var subtitle: String? = nil
    let value: String
    var symbol: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RowContent(title: title, subtitle: subtitle, value: value, symbol: symbol)
        }
        .buttonStyle(TVRowButtonStyle())
    }

    private struct RowContent: View {
        let title: String
        let subtitle: String?
        let value: String
        let symbol: String?
        @Environment(\.tvRowFocused) private var focused

        var body: some View {
            HStack(spacing: 20) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 28, weight: .semibold))
                        .frame(width: 40)
                        .foregroundStyle(focused ? .white : Palette.ink)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                    if let subtitle {
                        Text(subtitle)
                            .font(.mono(18))
                            .foregroundStyle(focused ? .white.opacity(0.8) : Palette.caption)
                    }
                }
                Spacer(minLength: 20)
                Text(value)
                    .font(.mono(24, .bold))
                    .foregroundStyle(focused ? .white : Palette.ink)
            }
        }
    }
}

/// On / Off row.
struct TVToggleRow: View {
    let title: String
    var subtitle: String? = nil
    var symbol: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        TVValueRow(title: title, subtitle: subtitle, value: isOn ? "On" : "Off", symbol: symbol) {
            withAnimation(.snappy) { isOn.toggle() }
        }
    }
}

/// A titled row of choices. Left/right moves between chips, click picks.
struct TVChoiceRow<Value: Hashable>: View {
    let title: String
    var subtitle: String? = nil
    let options: [Value]
    let selection: Value
    let label: (Value) -> String
    let onSelect: (Value) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.mono(26, .semibold))
                    .foregroundStyle(Palette.value)
                if let subtitle {
                    Text(subtitle)
                        .font(.mono(18))
                        .foregroundStyle(Palette.caption)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(options, id: \.self) { option in
                        Button(label(option)) {
                            withAnimation(.snappy) { onSelect(option) }
                        }
                        .buttonStyle(TVChipButtonStyle(isSelected: option == selection))
                    }
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 10)
            }
            .scrollClipDisabled()
        }
        .focusSection()
    }
}

struct TVSectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.mono(20, .bold))
            .tracking(3)
            .textCase(.uppercase)
            .foregroundStyle(Palette.caption)
            .padding(.top, 26)
            .padding(.leading, 6)
    }
}

// MARK: - Compass preview

/// A dial showing which way "up" on the TV points, with the radar's N marker.
struct TVFacingDial: View {
    let facing: Double
    var size: CGFloat = 220

    var body: some View {
        ZStack {
            Circle()
                .fill(Palette.paperShade.opacity(0.35))
            Circle()
                .stroke(Palette.faint, lineWidth: 2)
            // Compass card, rotated so the facing direction is at the top (like the TV).
            ZStack {
                ForEach(0..<72) { i in
                    Capsule()
                        .fill(Palette.caption.opacity(i % 6 == 0 ? 0.9 : 0.4))
                        .frame(width: i % 6 == 0 ? 3 : 1.5, height: i % 6 == 0 ? 16 : 8)
                        .offset(y: -size / 2 + 14)
                        .rotationEffect(.degrees(Double(i) * 5))
                }
                ForEach([(0.0, "N"), (90.0, "E"), (180.0, "S"), (270.0, "W")], id: \.0) { degrees, letter in
                    Text(letter)
                        .font(.mono(size * 0.11, .heavy))
                        .foregroundStyle(degrees == 0 ? Palette.signal : Palette.caption)
                        .rotationEffect(.degrees(-(degrees - facing)))
                        .offset(y: -size / 2 + 44)
                        .rotationEffect(.degrees(degrees))
                }
            }
            .rotationEffect(.degrees(-facing))
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: facing)

            // The TV, always "up".
            VStack(spacing: 6) {
                Image(systemName: "tv")
                    .font(.system(size: size * 0.16, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: size * 0.08))
                    .foregroundStyle(Palette.ink)
            }
            .offset(y: -size * 0.06)
            Image(systemName: "sofa.fill")
                .font(.system(size: size * 0.1))
                .foregroundStyle(Palette.caption)
                .offset(y: size * 0.2)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("TV faces \(Int(facing.rounded())) degrees, \(GeoMath.cardinal(facing))")
    }
}
#endif
