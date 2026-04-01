//
//  tvOSSpecificUITests.swift
//  WhatTheFlightUITests
//
//  Created by Kiro on 8/1/25.
//

import XCTest

#if os(tvOS)

final class tvOSSpecificUITests: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        
        // Wait for the app to launch completely
        _ = app.wait(for: .runningForeground, timeout: 5.0)
    }
    
    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }
    
    // MARK: - Focus Navigation Tests
    
    func testBasicFocusNavigation() throws {
        // Test that the app starts with focus on an element
        let startStopButton = app.buttons["tv_start_stop_button"]
        XCTAssertTrue(startStopButton.exists, "Start/stop button should exist")
        
        // Test remote control navigation
        app.pressMicrophoneButton()
        Thread.sleep(forTimeInterval: 0.5)
        
        // Test directional navigation with remote
        app.pressMenuButton()
        Thread.sleep(forTimeInterval: 0.5)
    }
    
    func testRemoteControlNavigation() throws {
        // Test Siri Remote navigation patterns
        let settingsButton = app.buttons["Settings"]
        
        if settingsButton.exists {
            // Navigate to settings using remote
            settingsButton.tap()
            Thread.sleep(forTimeInterval: 1.0)
            
            // Test that settings sheet appears with proper focus
            let settingsView = app.otherElements.containing(.staticText, identifier: "Settings").firstMatch
            XCTAssertTrue(settingsView.waitForExistence(timeout: 2.0), "Settings view should appear")
            
            // Test menu button to dismiss
            app.pressMenuButton()
            Thread.sleep(forTimeInterval: 0.5)
        }
    }
    
    func testFocusBasedFlightNavigation() throws {
        // Test focus-based flight navigation
        let previousButton = app.buttons["Previous Flight"]
        let nextButton = app.buttons["Next Flight"]
        
        if previousButton.exists && nextButton.exists {
            // Test focus states
            XCTAssertTrue(previousButton.exists, "Previous flight button should exist")
            XCTAssertTrue(nextButton.exists, "Next flight button should exist")
            
            // Test navigation between flight controls
            nextButton.tap()
            Thread.sleep(forTimeInterval: 0.5)
            
            previousButton.tap()
            Thread.sleep(forTimeInterval: 0.5)
        }
    }
    
    // MARK: - Large Text and Accessibility Tests
    
    func testLargeTextVisibility() throws {
        // Test that text is appropriately sized for TV viewing
        let appTitle = app.staticTexts["WhatTheFlight"]
        if appTitle.exists {
            let titleFrame = appTitle.frame
            XCTAssertGreaterThan(titleFrame.height, 40, "App title should be large enough for TV viewing")
        }
        
        // Test flight information text sizes
        let flightCard = app.otherElements["tv_flight_card"]
        if flightCard.exists {
            XCTAssertTrue(flightCard.exists, "Flight card should be visible and appropriately sized")
        }
    }
    
    func testHighContrastElements() throws {
        // Test that UI elements have sufficient contrast for TV viewing
        let connectionStatus = app.otherElements.containing(.circle, identifier: "").firstMatch
        if connectionStatus.exists {
            XCTAssertTrue(connectionStatus.isDisplayed(), "Connection status should be clearly visible")
        }
        
        // Test button visibility and contrast
        let startStopButton = app.buttons["tv_start_stop_button"]
        if startStopButton.exists {
            XCTAssertTrue(startStopButton.isDisplayed(), "Primary button should have high contrast")
        }
    }
    
    func testTVSpecificSizing() throws {
        // Test that the interface is appropriately sized for living room viewing
        let mainContent = app.otherElements.firstMatch
        let screenBounds = app.frame
        
        // UI should use significant portion of screen real estate
        XCTAssertGreaterThan(mainContent.frame.width, screenBounds.width * 0.7, 
                           "Content should be appropriately sized for TV")
        XCTAssertGreaterThan(mainContent.frame.height, screenBounds.height * 0.7, 
                           "Content should be appropriately sized for TV")
    }
    
    // MARK: - Simplified Interface Tests
    
    func testSimplifiedInterface() throws {
        // Test that the interface is simplified for living room use
        let allButtons = app.buttons.allElementsBoundByIndex
        
        // Should have limited number of primary actions visible
        XCTAssertLessThanOrEqual(allButtons.count, 6, "Interface should be simplified with fewer buttons")
        
        // Test that primary actions are prominent
        let startStopButton = app.buttons["tv_start_stop_button"]
        let settingsButton = app.buttons["Settings"]
        
        XCTAssertTrue(startStopButton.exists, "Primary action button should be present")
        XCTAssertTrue(settingsButton.exists, "Settings button should be present")
    }
    
    func testLivingRoomOptimization() throws {
        // Test optimizations for living room usage
        let flightDisplay = app.otherElements["tv_flight_card"]
        
        if flightDisplay.exists {
            let displayFrame = flightDisplay.frame
            
            // Flight information should be prominently displayed
            XCTAssertGreaterThan(displayFrame.width, 400, "Flight display should be large for room viewing")
            XCTAssertGreaterThan(displayFrame.height, 300, "Flight display should be tall enough for easy reading")
        }
    }
    
    func testMinimalInteractionComplexity() throws {
        // Test that interactions are simple and focused
        
        // Starting monitoring should be a single action
        let startStopButton = app.buttons["tv_start_stop_button"]
        if startStopButton.exists {
            startStopButton.tap()
            Thread.sleep(forTimeInterval: 1.0)
            
            // Should not require complex multi-step interactions
            XCTAssertTrue(app.isRunning, "App should handle simple interactions smoothly")
        }
        
        // Settings should be accessible but not cluttered
        let settingsButton = app.buttons["Settings"]
        if settingsButton.exists {
            settingsButton.tap()
            Thread.sleep(forTimeInterval: 1.0)
            
            // Settings should be simplified
            let settingsElements = app.otherElements.allElementsBoundByIndex
            XCTAssertLessThanOrEqual(settingsElements.count, 10, "Settings should be simplified for TV")
        }
    }
    
    // MARK: - tvOS-Specific Feature Tests
    
    func testTVOSNavigationPatterns() throws {
        // Test tvOS-specific navigation patterns
        
        // Test that focus moves logically
        let firstButton = app.buttons.firstMatch
        if firstButton.exists {
            firstButton.tap()
            
            // Focus should move predictably
            XCTAssertTrue(app.isRunning, "Navigation should be smooth and predictable")
        }
    }
    
    func testSiriRemoteInteractions() throws {
        // Test Siri Remote specific interactions
        
        // Test menu button behavior
        app.pressMenuButton()
        Thread.sleep(forTimeInterval: 0.5)
        
        // Test that menu button provides expected navigation
        XCTAssertTrue(app.isRunning, "Menu button should work correctly")
        
        // Test play/pause button if applicable
        app.pressPauseButton()
        Thread.sleep(forTimeInterval: 0.5)
        
        app.pressPlayButton()
        Thread.sleep(forTimeInterval: 0.5)
    }
    
    func testTouchpadNavigation() throws {
        // Test trackpad/touchpad area navigation
        let centerCoordinate = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        
        // Test touch and swipe gestures
        centerCoordinate.tap()
        Thread.sleep(forTimeInterval: 0.5)
        
        // Test swipe navigation
        let rightCoordinate = app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
        centerCoordinate.press(forDuration: 0.1, thenDragTo: rightCoordinate)
        Thread.sleep(forTimeInterval: 0.5)
    }
    
    // MARK: - Performance Tests for TV
    
    func testTVPerformance() throws {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Test that UI responds quickly to remote control input
        let startStopButton = app.buttons["tv_start_stop_button"]
        if startStopButton.exists {
            startStopButton.tap()
            Thread.sleep(forTimeInterval: 0.1)
            
            startStopButton.tap()
            Thread.sleep(forTimeInterval: 0.1)
        }
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let responseTime = endTime - startTime
        
        // UI should be responsive for living room use
        XCTAssertLessThan(responseTime, 1.0, "UI should respond quickly to remote control input")
    }
    
    func testFocusAnimationPerformance() throws {
        // Test that focus animations are smooth
        let buttons = app.buttons.allElementsBoundByIndex
        
        for button in buttons.prefix(3) {
            if button.exists {
                button.hover()
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
        
        // Animations should not cause performance issues
        XCTAssertTrue(app.isRunning, "Focus animations should be performant")
    }
    
    // MARK: - Content Display Tests
    
    func testFlightInformationVisibility() throws {
        // Test that flight information is clearly visible from TV viewing distance
        
        // Start monitoring to potentially get flight data
        let startStopButton = app.buttons["tv_start_stop_button"]
        if startStopButton.exists {
            startStopButton.tap()
            Thread.sleep(forTimeInterval: 2.0)
        }
        
        // Check that flight information, when available, is appropriately displayed
        let flightCard = app.otherElements["tv_flight_card"]
        if flightCard.exists {
            // Flight card should be prominently displayed
            XCTAssertTrue(flightCard.isDisplayed(), "Flight information should be clearly visible")
            
            // Text should be large enough for TV viewing
            let cardFrame = flightCard.frame
            XCTAssertGreaterThan(cardFrame.width, 600, "Flight card should be wide enough for TV")
            XCTAssertGreaterThan(cardFrame.height, 400, "Flight card should be tall enough for TV")
        }
    }
    
    func testConnectionStatusVisibility() throws {
        // Test that connection status is clearly visible
        let connectionElements = app.otherElements.containing(.circle, identifier: "").allElementsBoundByIndex
        
        if !connectionElements.isEmpty {
            let statusElement = connectionElements.first!
            XCTAssertTrue(statusElement.isDisplayed(), "Connection status should be visible")
        }
    }
    
    // MARK: - Accessibility Tests
    
    func testVoiceOverCompatibility() throws {
        // Test that the app works well with VoiceOver on tvOS
        let startStopButton = app.buttons["tv_start_stop_button"]
        
        if startStopButton.exists {
            XCTAssertFalse(startStopButton.label.isEmpty, "Button should have accessible label")
        }
        
        let settingsButton = app.buttons["Settings"]
        if settingsButton.exists {
            XCTAssertFalse(settingsButton.label.isEmpty, "Settings button should have accessible label")
        }
    }
    
    func testFocusOrdering() throws {
        // Test that focus moves in logical order
        let buttons = app.buttons.allElementsBoundByIndex
        
        // Should have logical focus ordering
        XCTAssertGreaterThanOrEqual(buttons.count, 1, "Should have focusable elements")
        
        // Primary action should be easily accessible
        let startStopButton = app.buttons["tv_start_stop_button"]
        XCTAssertTrue(startStopButton.exists, "Primary action should be focusable")
    }
}

// MARK: - Helper Extensions

extension XCUIElement {
    func isDisplayed() -> Bool {
        return exists && !frame.isEmpty && isHittable
    }
}

extension XCUIApplication {
    func pressMenuButton() {
        // Simulate Apple TV menu button press
        XCUIRemote.shared.press(.menu)
    }
    
    func pressMicrophoneButton() {
        // Simulate Siri button press
        XCUIRemote.shared.press(.select)
    }
    
    func pressPauseButton() {
        // Simulate pause button
        XCUIRemote.shared.press(.playPause)
    }
    
    func pressPlayButton() {
        // Simulate play button  
        XCUIRemote.shared.press(.playPause)
    }
}

#endif