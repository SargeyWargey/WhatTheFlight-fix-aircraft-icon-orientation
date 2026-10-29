//
//  WatchlistView.swift
//  WhatTheFlight
//
//  Settings → Alerts → Watchlist (iPhone / iPad): tail numbers, aircraft types, airlines
//  and callsigns to be alerted about, and the sheet that adds one, suggesting types and
//  airlines from the catalogs as you type. `WatchlistMenu` adds and removes them from a
//  flight's details.
//

#if os(iOS)
import SwiftUI

struct WatchlistView: View {
    @Bindable var settings: RadarSettings
    @State private var isAdding = false

    var body: some View {
        Form {
            if settings.watchlist.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "eye")
                            .font(.title2)
                            .foregroundStyle(Palette.ink)
                        Text("Add a tail number, an aircraft type, an airline or a callsign and you'll get an alert whenever one comes into range.")
                            .foregroundStyle(Palette.value)
                        Text("Try “Boeing 747”, “Qatar Airways”, or “RCH” for US Air Force transports. Any aircraft's details can add its type or airline too.")
                            .font(.footnote)
                            .foregroundStyle(Palette.caption)
                    }
                    .padding(.vertical, 6)
                }
            } else {
                Section {
                    ForEach(settings.watchlist) { rule in
                        WatchlistRuleRow(rule: rule)
                            .swipeActions {
                                Button("Remove", systemImage: "trash", role: .destructive) {
                                    withAnimation { settings.removeFromWatchlist(rule) }
                                }
                            }
                    }
                    .onDelete { settings.watchlist.remove(atOffsets: $0) }
                    .onMove { settings.watchlist.move(fromOffsets: $0, toOffset: $1) }
                } header: {
                    SettingsHeader("Watching for")
                } footer: {
                    Text("Alerts arrive like overhead ones: a banner, or a notification while Sky Watch runs. Apple Watch taps your wrist for them too.")
                }
            }

            Section {
                Button("Add to Watchlist", systemImage: "plus.circle.fill") { isAdding = true }
            }
        }
        .settingsPage("Watchlist")
        .toolbar {
            if !settings.watchlist.isEmpty { EditButton() }
        }
        .sheet(isPresented: $isAdding) {
            WatchlistAddView(settings: settings)
        }
    }
}

struct WatchlistRuleRow: View {
    let rule: WatchlistRule

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.title)
                    .foregroundStyle(Palette.value)
                Text(rule.kind.title)
                    .font(.footnote)
                    .foregroundStyle(Palette.caption)
            }
        } icon: {
            Image(systemName: rule.kind.symbol)
                .foregroundStyle(Palette.ink)
        }
    }
}

/// Picks what kind of rule, then suggests: types and airlines from the catalogs, tail numbers
/// and callsigns as typed.
struct WatchlistAddView: View {
    @Bindable var settings: RadarSettings
    var initialKind: WatchlistRule.Kind = .type

    @Environment(\.dismiss) private var dismiss
    @State private var kind: WatchlistRule.Kind = .type
    @State private var text = ""
    @FocusState private var isTyping: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Watch for", selection: $kind) {
                        ForEach(WatchlistRule.Kind.allCases) { Text(shortTitle($0)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    TextField(kind.placeholder, text: $text)
                        .textInputAutocapitalization(kind == .type || kind == .airline ? .words : .characters)
                        .autocorrectionDisabled()
                        .focused($isTyping)
                        .submitLabel(.done)
                        .onSubmit(addTyped)
                } footer: {
                    Text(footer)
                }

                if !suggestions.isEmpty {
                    Section {
                        ForEach(suggestions) { rule in
                            Button {
                                add(rule)
                            } label: {
                                HStack {
                                    WatchlistRuleRow(rule: rule)
                                    Spacer()
                                    if settings.watchlist.contains(rule) {
                                        Image(systemName: "checkmark").foregroundStyle(Palette.ink)
                                    }
                                }
                            }
                            .disabled(settings.watchlist.contains(rule))
                        }
                    } header: {
                        SettingsHeader(kind == .type || kind == .airline ? "Matches" : "Add")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .tint(Palette.ink)
            .navigationTitle("Add to Watchlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: addTyped)
                        .fontWeight(.semibold)
                        .disabled(WatchlistRule.resolve(text, kind: kind) == nil)
                }
            }
            .onAppear {
                kind = initialKind
                isTyping = true
            }
            .onChange(of: kind) { _, _ in text = "" }
        }
        .presentationDetents([.medium, .large])
    }

    private func shortTitle(_ kind: WatchlistRule.Kind) -> String {
        switch kind {
        case .registration: return "Tail"
        case .type: return "Type"
        case .airline: return "Airline"
        case .callsign: return "Callsign"
        }
    }

    private var footer: String {
        switch kind {
        case .registration: return "That one airframe, whatever flight it's on. Favorite an aircraft for the same alert plus a yellow icon."
        case .type: return "Every aircraft of that exact type: a Boeing 747-8 (B748) is a different type from a 747-400 (B744)."
        case .airline: return "Everything that airline flies, passenger or cargo."
        case .callsign: return "Every callsign starting with these letters: RCH for US Air Force Reach flights, NASA, LIFE…"
        }
    }

    private var suggestions: [WatchlistRule] {
        switch kind {
        case .type:
            return AircraftTypeCatalog.search(text, limit: 8).map { WatchlistRule(kind: .type, value: $0.code) }
        case .airline:
            return AirlineCatalog.search(text, limit: 8).map { WatchlistRule(kind: .airline, value: $0.icao) }
        case .registration, .callsign:
            return WatchlistRule.resolve(text, kind: kind).map { [$0] } ?? []
        }
    }

    private func addTyped() {
        if let rule = WatchlistRule.resolve(text, kind: kind) { add(rule) }
    }

    private func add(_ rule: WatchlistRule) {
        settings.addToWatchlist(rule)
        dismiss()
    }
}

/// From a flight's details: watch for its type, its airline or the airframe itself.
struct WatchlistMenu: View {
    let flight: Flight
    let profile: FlightProfile
    @Bindable var settings: RadarSettings

    var body: some View {
        Menu {
            Section("Alert me when one comes into range") {
                ForEach(rules) { rule in
                    let isOn = settings.watchlist.contains(rule)
                    Button {
                        withAnimation(.snappy) {
                            if isOn { settings.removeFromWatchlist(rule) } else { settings.addToWatchlist(rule) }
                        }
                    } label: {
                        Label(rule.offerTitle(for: flight), systemImage: isOn ? "checkmark" : rule.kind.symbol)
                    }
                }
            }
        } label: {
            Label(isWatched ? "Watching" : "Alert Me", systemImage: isWatched ? "eye.fill" : "eye")
                .frame(maxWidth: .infinity)
        }
        .accessibilityHint("Adds this aircraft's type, airline or tail number to your watchlist")
    }

    private var isWatched: Bool { rules.contains(where: settings.watchlist.contains) }

    private var rules: [WatchlistRule] { WatchlistRule.suggestions(for: flight, profile: profile) }
}
#endif
