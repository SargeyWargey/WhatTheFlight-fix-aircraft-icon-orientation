//
//  WhatTheFlightApp.swift
//  WhatTheFlight
//
//  Created by Joshua Sargent on 8/1/25.
//

import SwiftUI

@main
struct WhatTheFlightApp: App {
    #if os(macOS)
    @StateObject private var windowManager = WindowManager.shared
    #endif
    
    var body: some Scene {
        WindowGroup {
            #if os(macOS)
            ResizableWindowContainer(minWidth: 600, minHeight: 400) {
                ContentView()
            }
            .onAppear {
                windowManager.configureMainWindow()
            }
            #else
            ContentView()
            #endif
        }
        #if os(macOS)
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unified)
        .commands {
            macOSCommands
        }
        #endif
    }
    
    #if os(macOS)
    @CommandsBuilder
    private var macOSCommands: some Commands {
        // File menu commands
        CommandGroup(replacing: .newItem) {
            Button("New Monitoring Session") {
                // Start new monitoring session
                NotificationCenter.default.post(name: .startMonitoring, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)
        }
        
        // View menu commands
        CommandMenu("Flight") {
            Button("Start/Stop Monitoring") {
                NotificationCenter.default.post(name: .toggleMonitoring, object: nil)
            }
            .keyboardShortcut(.space, modifiers: .command)
            
            Button("Refresh Flight Data") {
                NotificationCenter.default.post(name: .refreshFlightData, object: nil)
            }
            .keyboardShortcut("r", modifiers: .command)
            
            Divider()
            
            Button("Next Flight") {
                NotificationCenter.default.post(name: .nextFlight, object: nil)
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            
            Button("Previous Flight") {
                NotificationCenter.default.post(name: .previousFlight, object: nil)
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
        }
        
        // Window menu enhancements
        CommandGroup(after: .windowArrangement) {
            Button("Show Settings") {
                NotificationCenter.default.post(name: .showSettings, object: nil)
            }
            .keyboardShortcut(",", modifiers: .command)
        }
        
        // Help menu
        CommandGroup(replacing: .help) {
            Button("WhatTheFlight Help") {
                if let url = URL(string: "https://github.com/yourusername/whattheflight/wiki") {
                    NSWorkspace.shared.open(url)
                }
            }
            .keyboardShortcut("?", modifiers: .command)
            
            Button("Report Issue") {
                if let url = URL(string: "https://github.com/yourusername/whattheflight/issues") {
                    NSWorkspace.shared.open(url)
                }
            }
            
            Button("Check for Updates") {
                // Placeholder for update checking functionality
                NotificationCenter.default.post(name: .checkForUpdates, object: nil)
            }
        }
    }
    #endif
}

// MARK: - Notification Names for macOS Commands

extension Notification.Name {
    static let startMonitoring = Notification.Name("startMonitoring")
    static let toggleMonitoring = Notification.Name("toggleMonitoring")
    static let refreshFlightData = Notification.Name("refreshFlightData")
    static let nextFlight = Notification.Name("nextFlight")
    static let previousFlight = Notification.Name("previousFlight")
    static let showSettings = Notification.Name("showSettings")
    static let checkForUpdates = Notification.Name("checkForUpdates")
}
