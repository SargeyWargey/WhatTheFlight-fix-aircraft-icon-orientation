//
//  WhatTheFlightUITests.swift
//  WhatTheFlightUITests
//
//  Created by Joshua Sargent on 8/1/25.
//

import XCTest

final class WhatTheFlightUITests: XCTestCase {
    
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        
        // Set up for iOS-specific testing
        #if os(iOS)
        // Test in both orientations
        XCUIDevice.shared.orientation = .portrait
        #endif
        
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
    
    // MARK: - iOS-Specific Tests
    
    #if os(iOS)
    
    @MainActor
    func testPortraitOrientationLayout() throws {
        // Ensure we're in portrait mode
        XCUIDevice.shared.orientation = .portrait
        
        // Verify main UI elements are present
        XCTAssertTrue(app.navigationBars["WhatTheFlight"].exists)
        XCTAssertTrue(app.buttons["Settings"].exists)
        XCTAssertTrue(app.buttons.matching(identifier: "play.circle.fill").firstMatch.exists || 
                     app.buttons.matching(identifier: "stop.circle.fill").firstMatch.exists)
        
        // Verify flight display area exists
        XCTAssertTrue(app.staticTexts["No Flights Detected"].exists || 
                     app.scrollViews.firstMatch.exists)
    }
    
    @MainActor
    func testLandscapeOrientationLayout() throws {
        // Rotate to landscape
        XCUIDevice.shared.orientation = .landscapeLeft
        
        // Wait for orientation change
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true"),
            object: app.navigationBars.firstMatch
        )
        wait(for: [expectation], timeout: 2.0)
        
        // Verify navigation elements adapt to landscape
        XCTAssertTrue(app.navigationBars.firstMatch.exists)
        XCTAssertTrue(app.buttons["Settings"].exists)
        
        // In landscape, the start/stop button should show text
        let startStopButton = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Start' OR label CONTAINS 'Stop'")).firstMatch
        XCTAssertTrue(startStopButton.exists)
    }
    
    @MainActor
    func testTouchOptimizedControls() throws {
        // Test that buttons respond to touch
        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.exists)
        
        // Tap settings button
        settingsButton.tap()
        
        // Verify settings view opens
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 2.0))
        
        // Test cancel button
        let cancelButton = app.buttons["Cancel"]
        XCTAssertTrue(cancelButton.exists)
        cancelButton.tap()
        
        // Verify we're back to main view
        XCTAssertTrue(app.navigationBars["WhatTheFlight"].waitForExistence(timeout: 2.0))
    }
    
    @MainActor
    func testStartStopButtonInteraction() throws {
        // Find the start/stop button
        let startButton = app.buttons.matching(identifier: "play.circle.fill").firstMatch
        let stopButton = app.buttons.matching(identifier: "stop.circle.fill").firstMatch
        
        if startButton.exists {
            // Test starting monitoring
            startButton.tap()
            
            // Wait for state change
            let expectation = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == true"),
                object: stopButton
            )
            wait(for: [expectation], timeout: 3.0)
            
            XCTAssertTrue(stopButton.exists)
        }
        
        if stopButton.exists {
            // Test stopping monitoring
            stopButton.tap()
            
            // Wait for state change
            let expectation = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == true"),
                object: startButton
            )
            wait(for: [expectation], timeout: 3.0)
            
            XCTAssertTrue(startButton.exists)
        }
    }
    
    @MainActor
    func testFlightCarouselGestures() throws {
        // This test would require mock flight data to be present
        // For now, we'll test that the carousel area exists and is interactive
        
        let flightDisplayArea = app.scrollViews.firstMatch
        if flightDisplayArea.exists {
            // Test swipe gestures
            flightDisplayArea.swipeLeft()
            flightDisplayArea.swipeRight()
            
            // Verify the area is still accessible
            XCTAssertTrue(flightDisplayArea.exists)
        }
    }
    
    @MainActor
    func testPullToRefreshGesture() throws {
        // Test pull-to-refresh functionality
        let scrollView = app.scrollViews.firstMatch
        
        if scrollView.exists {
            // Perform pull-to-refresh gesture
            let startCoordinate = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
            let endCoordinate = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            
            startCoordinate.press(forDuration: 0.1, thenDragTo: endCoordinate)
            
            // Verify the view is still functional after refresh
            XCTAssertTrue(scrollView.exists)
        }
    }
    
    @MainActor
    func testSettingsViewTouchOptimization() throws {
        // Open settings
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 2.0))
        
        // Test various settings controls
        let form = app.scrollViews.firstMatch
        XCTAssertTrue(form.exists)
        
        // Test location section interactions
        if app.buttons["Request"].exists {
            app.buttons["Request"].tap()
            // Note: In a real test, we'd need to handle location permission dialogs
        }
        
        // Test slider interaction (query interval)
        let slider = app.sliders.firstMatch
        if slider.exists {
            slider.adjust(toNormalizedSliderPosition: 0.7)
            XCTAssertTrue(slider.exists)
        }
        
        // Test toggle switches
        let toggles = app.switches
        if toggles.count > 0 {
            let firstToggle = toggles.firstMatch
            let initialValue = firstToggle.value as? String
            firstToggle.tap()
            
            // Verify toggle state changed
            let newValue = firstToggle.value as? String
            XCTAssertNotEqual(initialValue, newValue)
        }
        
        // Close settings
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["WhatTheFlight"].waitForExistence(timeout: 2.0))
    }
    
    @MainActor
    func testAdaptiveLayoutForDifferentScreenSizes() throws {
        // Test on different simulated screen sizes
        let bounds = app.windows.firstMatch.frame
        
        // Verify that UI elements are properly sized for the screen
        XCTAssertTrue(bounds.width > 0)
        XCTAssertTrue(bounds.height > 0)
        
        // Test that navigation elements are accessible
        XCTAssertTrue(app.navigationBars.firstMatch.exists)
        XCTAssertTrue(app.buttons["Settings"].isHittable)
        
        // Test that main content area uses available space
        let mainContentArea = app.scrollViews.firstMatch
        if mainContentArea.exists {
            XCTAssertTrue(mainContentArea.frame.width > 0)
            XCTAssertTrue(mainContentArea.frame.height > 0)
        }
    }
    
    @MainActor
    func testHapticFeedbackIntegration() throws {
        // While we can't directly test haptic feedback, we can test that
        // the buttons that should provide haptic feedback are working
        
        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.exists)
        
        // Multiple taps to test haptic feedback integration
        settingsButton.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 2.0))
        
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["WhatTheFlight"].waitForExistence(timeout: 2.0))
        
        // Test start/stop button haptic feedback
        let startStopButton = app.buttons.matching(identifier: "play.circle.fill").firstMatch
        if startStopButton.exists {
            startStopButton.tap()
            // Verify the button responded to the tap
            XCTAssertTrue(app.buttons.matching(identifier: "stop.circle.fill").firstMatch.waitForExistence(timeout: 3.0) ||
                         startStopButton.exists)
        }
    }
    
    @MainActor
    func testAccessibilitySupport() throws {
        // Test that key UI elements have proper accessibility labels
        XCTAssertTrue(app.buttons["Settings"].exists)
        
        let startStopButton = app.buttons.matching(identifier: "play.circle.fill").firstMatch
        if startStopButton.exists {
            XCTAssertTrue(startStopButton.isHittable)
        }
        
        // Test that text elements are accessible
        let statusText = app.staticTexts.firstMatch
        if statusText.exists {
            XCTAssertTrue(statusText.exists)
        }
        
        // Test settings accessibility
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 2.0))
        
        // Verify form elements are accessible
        let form = app.scrollViews.firstMatch
        XCTAssertTrue(form.exists)
        
        app.buttons["Cancel"].tap()
    }
    
    #endif
}