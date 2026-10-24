// Legacy: only the macOS (and visionOS) app runs this. iOS, tvOS and watchOS run radar v2;
// see Enhancements Spec B4. Delete with the rest of Legacy/ once the Mac runs the iPad app (C11).
#if os(macOS) || os(visionOS)
//
//  macOSComponents.swift
//  WhatTheFlight
//
//  Created by Kiro on 8/1/25.
//

import SwiftUI

#if os(macOS)
import AppKit

// MARK: - macOS-Specific Button Styles

/// Desktop-optimized button style for macOS with hover effects
struct DesktopOptimizedButtonStyle: ButtonStyle {
    @State private var isHovered = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : (isHovered ? 1.02 : 1.0))
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.2), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}

/// macOS-specific toolbar button style
struct ToolbarButtonStyle: ButtonStyle {
    @State private var isHovered = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.2), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

// MARK: - macOS-Specific Layout Components

/// macOS-specific resizable window container with minimum size constraints
struct ResizableWindowContainer<Content: View>: View {
    let content: Content
    let minWidth: CGFloat
    let minHeight: CGFloat
    
    init(minWidth: CGFloat = 600, minHeight: CGFloat = 400, @ViewBuilder content: () -> Content) {
        self.minWidth = minWidth
        self.minHeight = minHeight
        self.content = content()
    }
    
    var body: some View {
        content
            .frame(minWidth: minWidth, minHeight: minHeight)
            .onAppear {
                // Set minimum window size
                if let window = NSApplication.shared.windows.first {
                    window.minSize = NSSize(width: minWidth, height: minHeight)
                    window.isRestorable = true
                    window.identifier = NSUserInterfaceItemIdentifier("WhatTheFlightMainWindow")
                }
            }
    }
}

/// macOS-specific split view for better desktop layout
struct DesktopSplitView<Primary: View, Secondary: View>: View {
    let primary: Primary
    let secondary: Secondary
    @State private var splitRatio: CGFloat = 0.7
    
    init(@ViewBuilder primary: () -> Primary, @ViewBuilder secondary: () -> Secondary) {
        self.primary = primary()
        self.secondary = secondary()
    }
    
    var body: some View {
        HSplitView {
            primary
                .frame(minWidth: 300)
            
            secondary
                .frame(minWidth: 200)
        }
    }
}

/// macOS-specific context menu provider
struct ContextMenuProvider<Content: View>: View {
    let content: Content
    let menuItems: [ContextMenuItem]
    
    init(@ViewBuilder content: () -> Content, menuItems: [ContextMenuItem]) {
        self.content = content()
        self.menuItems = menuItems
    }
    
    var body: some View {
        content
            .contextMenu {
                ForEach(menuItems, id: \.title) { item in
                    Button(item.title) {
                        item.action()
                    }
                    .keyboardShortcut(item.keyboardShortcut ?? KeyboardShortcut(.clear))
                }
            }
    }
}

struct ContextMenuItem {
    let title: String
    let action: () -> Void
    let keyboardShortcut: KeyboardShortcut?
    
    init(title: String, keyboardShortcut: KeyboardShortcut? = nil, action: @escaping () -> Void) {
        self.title = title
        self.keyboardShortcut = keyboardShortcut
        self.action = action
    }
}

// MARK: - macOS-Specific Input Handling

/// Enhanced text field with macOS-specific keyboard shortcuts
struct DesktopTextField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    let onCommit: (() -> Void)?
    
    init(title: String, text: Binding<String>, placeholder: String = "", onCommit: (() -> Void)? = nil) {
        self.title = title
        self._text = text
        self.placeholder = placeholder
        self.onCommit = onCommit
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    onCommit?()
                }
                .onExitCommand {
                    // Handle Escape key
                    text = ""
                }
        }
    }
}

/// macOS-specific slider with precise input capabilities
struct PrecisionSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    let onValueChanged: ((Double) -> Void)?
    
    @State private var isEditing = false
    @State private var textValue = ""
    
    init(title: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double = 1.0, unit: String = "", onValueChanged: ((Double) -> Void)? = nil) {
        self.title = title
        self._value = value
        self.range = range
        self.step = step
        self.unit = unit
        self.onValueChanged = onValueChanged
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                
                if isEditing {
                    TextField("Value", text: $textValue)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .accessibilityIdentifier("slider_value_field")
                        .onSubmit {
                            commitTextValue()
                        }
                        .onExitCommand {
                            cancelTextEditing()
                        }
                } else {
                    Text("\(Int(value))\(unit)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .onTapGesture {
                            startTextEditing()
                        }
                }
            }
            
            Slider(value: $value, in: range, step: step) {
                Text(title)
            } minimumValueLabel: {
                Text("\(Int(range.lowerBound))\(unit)")
                    .font(.caption)
            } maximumValueLabel: {
                Text("\(Int(range.upperBound))\(unit)")
                    .font(.caption)
            }
            .accessibilityIdentifier("query_interval_slider")
            .onChange(of: value) { _, newValue in
                onValueChanged?(newValue)
            }
        }
    }
    
    private func startTextEditing() {
        textValue = String(Int(value))
        isEditing = true
    }
    
    private func commitTextValue() {
        if let newValue = Double(textValue), range.contains(newValue) {
            value = newValue
            onValueChanged?(newValue)
        }
        isEditing = false
    }
    
    private func cancelTextEditing() {
        isEditing = false
        textValue = ""
    }
}

// MARK: - macOS-Specific Window Management

class WindowManager: ObservableObject {
    static let shared = WindowManager()
    
    private init() {}
    
    func configureMainWindow() {
        guard let window = NSApplication.shared.windows.first else { return }
        
        window.minSize = NSSize(width: 600, height: 400)
        window.setContentSize(NSSize(width: 800, height: 600))
        window.center()
        window.isRestorable = true
        window.identifier = NSUserInterfaceItemIdentifier("WhatTheFlightMainWindow")
        
        // Enable full-size content view
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        
        // Set window title
        window.title = "What The Flight?"
        
        // Configure window to be closable but not minimizable to prevent accidental closure
        window.styleMask.insert(.closable)
        window.styleMask.insert(.miniaturizable)
        
        // Enable automatic window restoration
        window.restorationClass = MainWindowRestoration.self
    }
    
    func showSettingsWindow() {
        // Implementation for showing settings in a separate window if needed
        // This could be used for a more traditional macOS settings experience
    }
    
    func updateWindowTitle(status: String?) {
        guard let window = NSApplication.shared.windows.first else { return }
        
        if let status = status {
            window.title = "What The Flight? — \(status)"
        } else {
            window.title = "What The Flight?"
        }
    }
}

// MARK: - Window Restoration

class MainWindowRestoration: NSObject, NSWindowRestoration {
    static func restoreWindow(withIdentifier identifier: NSUserInterfaceItemIdentifier, 
                             state: NSCoder, 
                             completionHandler: @escaping (NSWindow?, Error?) -> Void) {
        // Handle window restoration if needed
        completionHandler(nil, nil)
    }
}

// MARK: - Keyboard Shortcut Handling

struct KeyboardShortcutHandler: View {
    let onToggleMonitoring: () -> Void
    let onShowSettings: () -> Void
    let onRefresh: () -> Void
    let onQuit: () -> Void
    
    var body: some View {
        EmptyView()
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.keyboardShortcutNotification)) { notification in
                handleKeyboardShortcut(notification)
            }
    }
    
    private func handleKeyboardShortcut(_ notification: Notification) {
        guard let shortcut = notification.object as? String else { return }
        
        switch shortcut {
        case "toggleMonitoring":
            onToggleMonitoring()
        case "showSettings":
            onShowSettings()
        case "refresh":
            onRefresh()
        case "quit":
            onQuit()
        default:
            break
        }
    }
}

// MARK: - macOS-Specific Preferences

struct DesktopPreferencesView<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Preferences toolbar
            HStack {
                Text("Preferences")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Content
            ScrollView {
                content
                    .padding()
            }
        }
        .frame(width: 500, height: 600)
    }
}

#endif

// MARK: - Copy to Pasteboard Support

#if os(macOS)
extension NSPasteboard {
    func setFlightData(_ flight: FlightData) {
        clearContents()
        
        var flightDetails = "Flight: \(flight.displayIdentifier)\n"
        
        if let airline = flight.airline {
            flightDetails += "Airline: \(airline.name)\n"
        }
        
        if let aircraft = flight.aircraft {
            flightDetails += "Aircraft: \(aircraft.model)\n"
        }
        
        if let route = flight.route {
            flightDetails += "Route: \(route.origin.displayName) → \(route.destination.displayName)\n"
        }
        
        if let position = flight.position {
            if let altitude = position.altitude {
                flightDetails += "Altitude: \(altitude) ft\n"
            }
            if let speed = position.speed {
                flightDetails += "Speed: \(speed) kts\n"
            }
            if let heading = position.heading {
                flightDetails += "Heading: \(heading)°\n"
            }
        }
        
        setString(flightDetails, forType: .string)
    }
}
#endif

// MARK: - Extensions

#if os(macOS)
extension NSApplication {
    static let keyboardShortcutNotification = Notification.Name("KeyboardShortcut")
}
#endif
#endif
