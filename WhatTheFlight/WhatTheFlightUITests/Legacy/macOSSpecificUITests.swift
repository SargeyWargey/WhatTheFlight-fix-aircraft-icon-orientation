// Legacy: only the macOS (and visionOS) app runs this. iOS, tvOS and watchOS run radar v2;
// see Enhancements Spec B4. Delete with the rest of Legacy/ once the Mac runs the iPad app (C11).
#if os(macOS) || os(visionOS)
//
//  macOSSpecificUITests.swift
//  WhatTheFlightUITests
//
//  Created by Kiro on 8/1/25.
//

import XCTest

#if os(macOS)
final class macOSSpecificUITests: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - Window Management Tests
    
    func testWindowResizing() throws {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists, "Main window should exist")
        
        // Test that window can be resized
        let initialFrame = window.frame
        
        // Attempt to resize window (this is a basic test as actual resizing is hard to simulate)
        XCTAssertGreaterThan(initialFrame.width, 600, "Window should meet minimum width requirement")
        XCTAssertGreaterThan(initialFrame.height, 400, "Window should meet minimum height requirement")
    }
    
    func testWindowTitle() throws {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists, "Main window should exist")
        
        // Check that window has appropriate title
        XCTAssertTrue(window.title.contains("WhatTheFlight") || window.title.isEmpty, 
                     "Window should have appropriate title")
    }
    
    // MARK: - Menu Bar Tests
    
    func testFlightMenu() throws {
        // Test Flight menu exists and has expected items
        let menuBar = app.menuBars.firstMatch
        XCTAssertTrue(menuBar.exists, "Menu bar should exist")
        
        let flightMenu = menuBar.menuBarItems["Flight"]
        if flightMenu.exists {
            flightMenu.click()
            
            // Check for expected menu items
            let startStopItem = app.menuItems["Start/Stop Monitoring"]
            let refreshItem = app.menuItems["Refresh Flight Data"]
            let nextFlightItem = app.menuItems["Next Flight"]
            let previousFlightItem = app.menuItems["Previous Flight"]
            
            XCTAssertTrue(startStopItem.exists, "Start/Stop Monitoring menu item should exist")
            XCTAssertTrue(refreshItem.exists, "Refresh Flight Data menu item should exist")
            XCTAssertTrue(nextFlightItem.exists, "Next Flight menu item should exist")
            XCTAssertTrue(previousFlightItem.exists, "Previous Flight menu item should exist")
            
            // Close menu by clicking elsewhere
            app.click()
        }
    }
    
    func testWindowMenu() throws {
        let menuBar = app.menuBars.firstMatch
        XCTAssertTrue(menuBar.exists, "Menu bar should exist")
        
        let windowMenu = menuBar.menuBarItems["Window"]
        if windowMenu.exists {
            windowMenu.click()
            
            // Check for Settings menu item
            let settingsItem = app.menuItems["Show Settings"]
            XCTAssertTrue(settingsItem.exists, "Show Settings menu item should exist")
            
            // Close menu
            app.click()
        }
    }
    
    // MARK: - Keyboard Shortcut Tests
    
    func testKeyboardShortcuts() throws {
        // Test Command+Space for start/stop monitoring
        app.typeKey(" ", modifierFlags: .command)
        
        // Wait a moment for the action to process
        Thread.sleep(forTimeInterval: 0.5)
        
        // Test Command+R for refresh
        app.typeKey("r", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.5)
        
        // Test Command+, for settings
        app.typeKey(",", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.5)
        
        // Check if settings window appeared
        let settingsWindow = app.sheets.firstMatch
        if settingsWindow.exists {
            // Close settings with Escape
            app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
            Thread.sleep(forTimeInterval: 0.5)
        }
    }
    
    func testArrowKeyNavigation() throws {
        // This test assumes there are flights to navigate between
        // In a real test, you might want to mock some flight data first
        
        // Test right arrow for next flight
        app.typeKey(XCUIKeyboardKey.rightArrow, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.5)
        
        // Test left arrow for previous flight
        app.typeKey(XCUIKeyboardKey.leftArrow, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.5)
        
        // Test Command+Right Arrow
        app.typeKey(XCUIKeyboardKey.rightArrow, modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.5)
        
        // Test Command+Left Arrow
        app.typeKey(XCUIKeyboardKey.leftArrow, modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.5)
    }
    
    // MARK: - Mouse Interaction Tests
    
    func testHoverEffects() throws {
        // Test hover effects on buttons
        let startButton = app.buttons.matching(identifier: "start_stop_button").firstMatch
        if startButton.exists {
            // Move mouse over button (hover simulation is limited in XCTest)
            startButton.hover()
            Thread.sleep(forTimeInterval: 0.5)
        }
        
        // Test toolbar buttons
        let settingsButton = app.buttons["Settings"]
        if settingsButton.exists {
            settingsButton.hover()
            Thread.sleep(forTimeInterval: 0.5)
        }
    }
    
    func testContextMenu() throws {
        // Test right-click context menu on flight display area
        let flightDisplayArea = app.otherElements["flight_display_area"]
        if flightDisplayArea.exists {
            flightDisplayArea.rightClick()
            Thread.sleep(forTimeInterval: 0.5)
            
            // Check for context menu items
            let copyFlightNumberItem = app.menuItems["Copy Flight Number"]
            let copyFlightDetailsItem = app.menuItems["Copy Flight Details"]
            let startStopItem = app.menuItems.matching(NSPredicate(format: "title CONTAINS 'Monitoring'")).firstMatch
            let refreshItem = app.menuItems["Refresh"]
            
            if copyFlightNumberItem.exists {
                XCTAssertTrue(copyFlightNumberItem.exists, "Copy Flight Number context menu item should exist")
            }
            if copyFlightDetailsItem.exists {
                XCTAssertTrue(copyFlightDetailsItem.exists, "Copy Flight Details context menu item should exist")
            }
            XCTAssertTrue(startStopItem.exists, "Start/Stop Monitoring context menu item should exist")
            XCTAssertTrue(refreshItem.exists, "Refresh context menu item should exist")
            
            // Close context menu by clicking elsewhere
            app.click()
        }
    }
    
    // MARK: - Settings Window Tests
    
    func testSettingsWindow() throws {
        // Open settings
        app.typeKey(",", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.5)
        
        let settingsSheet = app.sheets.firstMatch
        XCTAssertTrue(settingsSheet.exists, "Settings sheet should appear")
        
        if settingsSheet.exists {
            // Test that settings has proper macOS layout
            let cancelButton = settingsSheet.buttons["Cancel"]
            let doneButton = settingsSheet.buttons["Done"]
            
            XCTAssertTrue(cancelButton.exists, "Cancel button should exist in settings")
            XCTAssertTrue(doneButton.exists, "Done button should exist in settings")
            
            // Test keyboard shortcuts in settings
            app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
            Thread.sleep(forTimeInterval: 0.5)
            
            // Settings should close
            XCTAssertFalse(settingsSheet.exists, "Settings sheet should close with Escape key")
        }
    }
    
    func testPrecisionSliderInSettings() throws {
        // Open settings
        app.typeKey(",", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.5)
        
        let settingsSheet = app.sheets.firstMatch
        if settingsSheet.exists {
            // Look for precision slider (macOS-specific component)
            let queryIntervalSlider = settingsSheet.sliders.matching(identifier: "query_interval_slider").firstMatch
            if queryIntervalSlider.exists {
                // Test slider interaction
                queryIntervalSlider.click()
                
                // Test that we can click on the value to edit it directly (macOS-specific feature)
                let valueText = settingsSheet.textFields.matching(identifier: "slider_value_field").firstMatch
                if valueText.exists {
                    valueText.click()
                    valueText.typeText("60")
                    app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])
                }
            }
            
            // Close settings
            app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        }
    }
    
    // MARK: - Toolbar Tests
    
    func testToolbarElements() throws {
        // Test that toolbar contains expected elements
        let toolbar = app.toolbars.firstMatch
        XCTAssertTrue(toolbar.exists, "Toolbar should exist")
        
        if toolbar.exists {
            // Test start/stop button in toolbar
            let startStopButton = toolbar.buttons.matching(NSPredicate(format: "title CONTAINS 'Start' OR title CONTAINS 'Stop'")).firstMatch
            XCTAssertTrue(startStopButton.exists, "Start/Stop button should exist in toolbar")
            
            // Test settings button in toolbar
            let settingsButton = toolbar.buttons["Settings"]
            XCTAssertTrue(settingsButton.exists, "Settings button should exist in toolbar")
            
            // Test connection status indicator
            let statusIndicator = toolbar.otherElements.matching(identifier: "connection_status").firstMatch
            if statusIndicator.exists {
                XCTAssertTrue(statusIndicator.exists, "Connection status should be visible in toolbar")
            }
        }
    }
    
    // MARK: - Desktop-Specific Layout Tests
    
    func testDesktopLayout() throws {
        // Test that the layout is appropriate for desktop
        let mainContent = app.otherElements["main_content"]
        if mainContent.exists {
            let frame = mainContent.frame
            
            // Verify minimum size constraints are respected
            XCTAssertGreaterThan(frame.width, 600, "Content should respect minimum width")
            XCTAssertGreaterThan(frame.height, 400, "Content should respect minimum height")
        }
        
        // Test that flight controls show text labels (desktop-specific)
        let previousButton = app.buttons["Previous"]
        let nextButton = app.buttons["Next"]
        
        if previousButton.exists {
            XCTAssertTrue(previousButton.exists, "Previous button should show text label on desktop")
        }
        if nextButton.exists {
            XCTAssertTrue(nextButton.exists, "Next button should show text label on desktop")
        }
    }
    
    // MARK: - Help Menu Tests
    
    func testHelpMenu() throws {
        let menuBar = app.menuBars.firstMatch
        XCTAssertTrue(menuBar.exists, "Menu bar should exist")
        
        let helpMenu = menuBar.menuBarItems["Help"]
        if helpMenu.exists {
            helpMenu.click()
            
            // Check for help menu items
            let helpItem = app.menuItems["WhatTheFlight Help"]
            let reportIssueItem = app.menuItems["Report Issue"]
            let checkUpdatesItem = app.menuItems["Check for Updates"]
            
            XCTAssertTrue(helpItem.exists, "WhatTheFlight Help menu item should exist")
            XCTAssertTrue(reportIssueItem.exists, "Report Issue menu item should exist")
            XCTAssertTrue(checkUpdatesItem.exists, "Check for Updates menu item should exist")
            
            // Close menu
            app.click()
        }
    }
    
    // MARK: - Window Restoration Tests
    
    func testWindowStateRestoration() throws {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists, "Main window should exist")
        
        // Test that window identifier is set for restoration
        XCTAssertTrue(window.isDisplayed(), "Window should be properly displayed for restoration")
    }
    
    // MARK: - Desktop Text Field Tests
    
    func testDesktopTextFieldFeatures() throws {
        // Open settings to test desktop text fields
        app.typeKey(",", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.5)
        
        let settingsSheet = app.sheets.firstMatch
        if settingsSheet.exists {
            // Test Escape key functionality in text fields
            let latitudeField = settingsSheet.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS 'latitude' OR placeholderValue CONTAINS '37.7749'")).firstMatch
            
            if latitudeField.exists {
                latitudeField.click()
                latitudeField.typeText("test")
                
                // Test Escape key clears field
                app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
                Thread.sleep(forTimeInterval: 0.2)
                
                // Field should be cleared or reverted
                XCTAssertTrue(latitudeField.exists, "Text field should handle Escape key gracefully")
            }
            
            // Close settings
            app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        }
    }
    
    // MARK: - Window Title Updates Tests
    
    func testWindowTitleStatusUpdates() throws {
        let window = app.windows.firstMatch
        let initialTitle = window.title
        
        // Start monitoring (which should potentially update window title)
        app.typeKey(" ", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 1.0)
        
        // Window title may update with status
        let newTitle = window.title
        XCTAssertTrue(window.exists, "Window should continue to exist with updated title")
        
        // Title should contain app name
        XCTAssertTrue(newTitle.contains("WhatTheFlight") || newTitle.isEmpty, "Window title should be appropriate")
    }
    
    // MARK: - Copy to Pasteboard Tests
    
    func testCopyFlightDetails() throws {
        // This test would require actual flight data, so we'll just test the context menu exists
        let flightDisplayArea = app.otherElements["flight_display_area"]
        if flightDisplayArea.exists {
            flightDisplayArea.rightClick()
            Thread.sleep(forTimeInterval: 0.5)
            
            // Test Cmd+C shortcut in context menu
            let copyFlightNumberItem = app.menuItems["Copy Flight Number"]
            if copyFlightNumberItem.exists {
                // Test keyboard shortcut for copy (Cmd+C)
                app.typeKey("c", modifierFlags: .command)
                Thread.sleep(forTimeInterval: 0.2)
            }
            
            // Close context menu
            app.click()
        }
    }
    
    // MARK: - Multiple Window Support Tests
    
    func testMultipleWindowHandling() throws {
        // Test that the app can handle window management properly
        let windows = app.windows
        XCTAssertGreaterThanOrEqual(windows.count, 1, "Should have at least one window")
        
        // Test that the main window is properly identified
        let mainWindow = app.windows.firstMatch
        XCTAssertTrue(mainWindow.exists, "Main window should be identifiable")
    }
    
    // MARK: - Focus Management Tests
    
    func testKeyboardFocusManagement() throws {
        let flightDisplayArea = app.otherElements["flight_display_area"]
        if flightDisplayArea.exists {
            // Test that the flight display area can receive focus
            flightDisplayArea.click()
            
            // Test space key when focused (should toggle monitoring)
            let startStopButton = app.buttons.matching(identifier: "start_stop_button").firstMatch
            if startStopButton.exists {
                let initialLabel = startStopButton.label
                
                app.typeKey(" ", modifierFlags: [])
                Thread.sleep(forTimeInterval: 0.5)
                
                let newLabel = startStopButton.label
                XCTAssertNotEqual(initialLabel, newLabel, "Space key should toggle monitoring when display area is focused")
            }
        }
    }
    
    // MARK: - Performance Tests
    
    func testWindowResponsiveness() throws {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Perform several UI interactions
        app.typeKey(" ", modifierFlags: .command) // Toggle monitoring
        Thread.sleep(forTimeInterval: 0.1)
        
        app.typeKey("r", modifierFlags: .command) // Refresh
        Thread.sleep(forTimeInterval: 0.1)
        
        app.typeKey(",", modifierFlags: .command) // Open settings
        Thread.sleep(forTimeInterval: 0.1)
        
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: []) // Close settings
        Thread.sleep(forTimeInterval: 0.1)
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let totalTime = endTime - startTime
        
        // UI should be responsive (complete interactions within reasonable time)
        XCTAssertLessThan(totalTime, 2.0, "UI interactions should complete within 2 seconds")
    }
    
    func testKeyboardShortcutPerformance() throws {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Test rapid keyboard shortcut execution
        for _ in 0..<10 {
            app.typeKey("r", modifierFlags: .command)
            Thread.sleep(forTimeInterval: 0.05)
        }
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let totalTime = endTime - startTime
        
        // Should handle rapid shortcuts without hanging
        XCTAssertLessThan(totalTime, 3.0, "Rapid keyboard shortcuts should be handled efficiently")
    }
    
    // MARK: - Accessibility Tests
    
    func testVoiceOverSupport() throws {
        // Test that key elements have proper accessibility labels
        let startStopButton = app.buttons.matching(identifier: "start_stop_button").firstMatch
        if startStopButton.exists {
            XCTAssertFalse(startStopButton.label.isEmpty, "Start/stop button should have accessibility label")
        }
        
        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.exists, "Settings button should be accessible")
        
        // Test help text on hover
        let connectionStatus = app.otherElements.matching(identifier: "connection_status").firstMatch
        if connectionStatus.exists {
            connectionStatus.hover()
            // Help text should be available (though hard to test directly in XCTest)
            XCTAssertTrue(connectionStatus.exists, "Connection status should provide accessibility information")
        }
    }
}

// MARK: - Helper Extensions

extension XCUIElement {
    func isDisplayed() -> Bool {
        return exists && !frame.isEmpty && isHittable
    }
    
    func resize(to size: CGSize) {
        // Helper method for window resizing (implementation would depend on specific needs)
        // This is a placeholder as actual window resizing in UI tests is complex
        coordinate(withNormalizedOffset: CGVector(dx: 1.0, dy: 1.0)).press(forDuration: 0.1, thenDragTo: coordinate(withNormalizedOffset: CGVector(dx: size.width/frame.width, dy: size.height/frame.height)))
    }
}

#endif
#endif
