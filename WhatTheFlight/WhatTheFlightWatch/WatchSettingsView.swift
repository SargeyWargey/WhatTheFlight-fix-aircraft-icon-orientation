//
//  WatchSettingsView.swift
//  WhatTheFlightWatch
//
//  The page above the radar. Nearby aircraft first, then a short list: where to watch from,
//  how far, and how the Watch should behave. Helicopters and alert preferences follow the
//  iPhone when it shares them.
//

import SwiftUI

struct WatchSettingsView: View {
    @Bindable var settings: RadarSettings
    @Bindable var watchSettings: WatchSettings
    let location: WatchLocationService
    let link: WatchPhoneLink
    let model: RadarModel
    let open: (WatchRootView.Screen) -> Void
    /// Back to the radar. The radar is also below the end of the list.
    let close: () -> Void
    /// Replays the first-run tour.
    var showTour: () -> Void = {}

    @State private var skyWatchMessage: String?
    @State private var askingPhone = false

    var body: some View {
        List {
            Section {
                Button { open(.nearby) } label: {
                    HStack {
                        Label("Nearby aircraft", systemImage: "list.bullet")
                        Spacer()
                        WatchNearbyCount(model: model)
                    }
                }
            } footer: {
                Text("Or swipe up from the radar.")
            }

            Section {
                Picker("Watch from", selection: $watchSettings.locationSource) {
                    ForEach(WatchSettings.LocationSource.allCases) { Text($0.title).tag($0) }
                }
                if watchSettings.locationSource == .phone {
                    Text(watchSettings.phoneObserver == nil
                         ? "Your iPhone hasn't shared a spot yet. Open What The Flight? on it."
                         : watchSettings.phonePlaceName ?? "Where your iPhone's radar is watching")
                        .font(.mono(10))
                        .foregroundStyle(Palette.caption)
                }
                Picker("Radius", selection: $settings.radiusMiles) {
                    ForEach(radiusChoices, id: \.self) { Text("\(Int($0)) mi").tag($0) }
                }
            } header: {
                Text("Radar")
            } footer: {
                Text("10 mi is about what you can see from the ground. Look further on your iPhone.")
            }

            Section("Display") {
                Toggle("North up", isOn: northUpBinding)
                    .disabled(!location.headingAvailable)
                Toggle("Helicopters", isOn: $settings.showHelicopters)
                Toggle("Radar sweep", isOn: $settings.radarSweep)
                Toggle("Aircraft photos", isOn: $settings.showPhotos)
                if settings.showPhotos {
                    Toggle("Photos on cellular", isOn: $watchSettings.photosOnCellular)
                }
            }

            Section {
                Toggle("Overhead", isOn: $settings.overheadAlerts)
                Toggle("Notable aircraft", isOn: $settings.notableAlerts)
                Toggle("Haptics", isOn: $settings.hapticsEnabled)
            } header: {
                Text("Wrist alerts")
            } footer: {
                Text("While the app is open. For alerts with your wrist down, start Sky Watch on iPhone.")
            }

            Section {
                Button {
                    askingPhone = true
                    Task {
                        skyWatchMessage = await link.requestSkyWatch().message
                        askingPhone = false
                    }
                } label: {
                    HStack {
                        Label("Start Sky Watch on iPhone", systemImage: "dot.radiowaves.left.and.right")
                        if askingPhone { Spacer(); ProgressView().frame(width: 16) }
                    }
                }
                .disabled(askingPhone)
                if let skyWatchMessage {
                    Text(skyWatchMessage).font(.mono(10)).foregroundStyle(Palette.caption)
                }
            } footer: {
                Text("Keeps watching while your iPhone is locked. Overhead alerts tap your wrist.")
            }

            Section {
                NavigationLink {
                    AimStyleSettingsView(watchSettings: watchSettings)
                } label: {
                    HStack {
                        Label("Aim with", systemImage: watchSettings.aimStyle.symbol)
                        Spacer()
                        Text(watchSettings.aimStyle.title).foregroundStyle(Palette.caption)
                    }
                }
                Toggle("Read aloud", isOn: $watchSettings.speakIdentification)
            } header: {
                Text("Identify & Find")
            } footer: {
                Text("Identify reads out the aircraft it locks on to. Pointing arm-out, watchOS treats your wrist as down: the screen dims, but the call-out still plays and the lock taps your wrist. To keep the app up longer, set Settings → General → Return to Clock → What The Flight? to After 1 hour.")
            }

            Section {
                Toggle("Demo traffic", isOn: $settings.demoTraffic)
                Button(action: showTour) {
                    Label("Take the tour", systemImage: "sparkles")
                }
            } footer: {
                Text("Flight data: Flightradar24 (unofficial). Airlines: OpenFlights (ODbL). Airports: OurAirports. Photos: Planespotters.net.")
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: close) { Image(systemName: "xmark") }
                    .accessibilityLabel("Back to radar")
            }
        }
    }

    private var radiusChoices: [Double] {
        Array(Set(WatchSettings.radiusChoices + [settings.radiusMiles])).sorted()
    }

    /// Without a compass the radar can only be north up.
    private var northUpBinding: Binding<Bool> {
        Binding(get: { watchSettings.northUp || !location.headingAvailable },
                set: { watchSettings.northUp = $0 })
    }
}

/// The count in a view of its own: the contacts change every second, and only this label
/// should redraw for that, not the settings list around it.
private struct WatchNearbyCount: View {
    let model: RadarModel

    var body: some View {
        Text("\(model.contacts.count)")
            .font(.mono(14, .bold))
            .monospacedDigit()
            .foregroundStyle(Palette.caption)
    }
}

/// Point or Aim, each explained, plus the fixes that only apply to Point.
struct AimStyleSettingsView: View {
    @Bindable var watchSettings: WatchSettings

    var body: some View {
        List {
            Section {
                ForEach(WristPointing.AimStyle.allCases) { style in
                    Button { watchSettings.aimStyle = style } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: style.symbol)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Palette.signal)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(style.title).font(.headline)
                                Text(style.summary)
                                    .font(.mono(10))
                                    .foregroundStyle(Palette.caption)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            if watchSettings.aimStyle == style {
                                Image(systemName: "checkmark").foregroundStyle(Palette.live)
                            }
                        }
                    }
                    .accessibilityAddTraits(watchSettings.aimStyle == style ? .isSelected : [])
                }
            } footer: {
                Text("A red arrow on the screen's edge shows which way is aiming.")
            }

            if watchSettings.aimStyle == .point {
                Section {
                    Toggle("Turn screen around", isOn: $watchSettings.flipScreen)
                    Toggle("Reverse arm direction", isOn: $watchSettings.flipPointing)
                } header: {
                    Text("If Point misbehaves")
                } footer: {
                    Text("Turn screen around if the text reads upside down. Reverse arm direction only if Find sends you the opposite way to the aircraft.")
                }
            }
        }
        .navigationTitle("Aim with")
    }
}
