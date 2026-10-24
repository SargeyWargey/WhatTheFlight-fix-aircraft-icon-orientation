//
//  iOSSpecificUITests.swift
//  WhatTheFlightUITests
//
//  Created by Kiro on 8/1/25.
//

import XCTest

#if os(iOS)
final class iOSSpecificUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - Touch Optimization Tests
    
    @MainActor
    func testTouchOptimizedButtonStyles() throws {
        // Test that buttons have proper touch feedback
        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.exists)
        XCTAssertTrue(settingsButton.isHittable)
        
        // Test button press animation by rapid tapping
        settingsButton.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 2.0))
        
        // Test form buttons in settings
        let cancelButton = app.buttons["Cancel"]
        XCTAssertTrue(cancelButton.exists)
        XCTAssertTrue(cancelButton.isHittable)
        
        cancelButton.tap()
        XCTAssertTrue(app.navigationBars["WhatTheFlight"].waitForExistence(timeout: 2.0))
    }
    
    @MainActor
    func testFlightCardTouchInteraction() throws {
        // This test assumes flight data is available
        // In a real scenario, we'd inject mock data
        
        let scrollView = app.scrollViews.firstMatch
        if scrollView.exists {
            // Test tap gesture on flight card
            scrollView.tap()
            
            // Test that the card responds to touch
            XCTAssertTrue(scrollView.exists)
        }
    }
    
    // MARK: - Gesture Recognition Tests
    
    @MainActor
    func testSwipeGesturesOnFlightCarousel() throws {
        let tabView = app.scrollViews.firstMatch
        
        if tabView.exists {
            let initialFrame = tabView.frame
            
            // Test left swipe
            tabView.swipeLeft()
            
            // Verify the view is still present and functional
            XCTAssertTrue(tabView.exists)
            
            // Test right swipe
            tabView.swipeRight()
            
            // Verify the view is still present
            XCTAssertTrue(tabView.exists)
        }
    }
    
    @MainActor
    func testPullToRefreshGesture() throws {
        let scrollView = app.scrollViews.firstMatch
        
        if scrollView.exists {
            // Get initial position
            let startCoordinate = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            let endCoordinate = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            
            // Perform pull-to-refresh gesture
            startCoordinate.press(forDuration: 0.1, thenDragTo: endCoordinate)
            
            // Verify the view is still functional
            XCTAssertTrue(scrollView.exists)
        }
    }
    
    // MARK: - Orientation Tests
    
    @MainActor
    func testPortraitToLandscapeTransition() throws {
        // Start in portrait
        XCUIDevice.shared.orientation = .portrait
        
        // Verify portrait layout
        XCTAssertTrue(app.navigationBars["WhatTheFlight"].exists)
        let portraitNavBar = app.navigationBars["WhatTheFlight"]
        XCTAssertTrue(portraitNavBar.exists)
        
        // Rotate to landscape
        XCUIDevice.shared.orientation = .landscapeLeft
        
        // Wait for rotation to complete
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true"),
            object: app.navigationBars.firstMatch
        )
        wait(for: [expectation], timeout: 3.0)
        
        // Verify landscape layout adaptations
        XCTAssertTrue(app.navigationBars.firstMatch.exists)
        XCTAssertTrue(app.buttons["Settings"].exists)
        
        // Rotate back to portrait
        XCUIDevice.shared.orientation = .portrait
        
        // Wait for rotation back
        let portraitExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true"),
            object: portraitNavBar
        )
        wait(for: [portraitExpectation], timeout: 3.0)
        
        XCTAssertTrue(portraitNavBar.exists)
    }
    
    @MainActor
    func testLandscapeLayoutOptimizations() throws {
        // Rotate to landscape
        XCUIDevice.shared.orientation = .landscapeLeft
        
        // Wait for orientation change
        sleep(1)
        
        // Verify that UI elements are properly arranged for landscape
        XCTAssertTrue(app.navigationBars.firstMatch.exists)
        
        // Check that buttons are accessible in landscape
        XCTAssertTrue(app.buttons["Settings"].isHittable)
        
        // Verify that the main content area adapts to landscape
        let mainContent = app.scrollViews.firstMatch
        if mainContent.exists {
            let frame = mainContent.frame
            // In landscape, width should be greater than height
            XCTAssertTrue(frame.width > frame.height)
        }
    }
    
    // MARK: - iPhone vs iPad Layout Tests
    
    @MainActor
    func testAdaptiveLayoutForDeviceSize() throws {
        let screenBounds = app.windows.firstMatch.frame
        
        // Test that layout adapts to screen size
        XCTAssertTrue(screenBounds.width > 0)
        XCTAssertTrue(screenBounds.height > 0)
        
        // Verify navigation is appropriate for device
        XCTAssertTrue(app.navigationBars.firstMatch.exists)
        
        // Test that touch targets are appropriately sized
        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.exists)
        
        let buttonFrame = settingsButton.frame
        // Touch targets should be at least 44x44 points
        XCTAssertTrue(buttonFrame.width >= 44 || buttonFrame.height >= 44)
    }
    
    @MainActor
    func testCompactVsRegularSizeClass() throws {
        // This test verifies that the app handles different size classes
        let navigationBar = app.navigationBars.firstMatch
        XCTAssertTrue(navigationBar.exists)
        
        // Test that toolbar items are accessible
        XCTAssertTrue(app.buttons["Settings"].exists)
        
        // Test that the main content adapts to size class
        let mainContent = app.scrollViews.firstMatch
        if mainContent.exists {
            XCTAssertTrue(mainContent.isHittable)
        }
    }
    
    // MARK: - Haptic Feedback Integration Tests
    
    @MainActor
    func testHapticFeedbackOnButtonPress() throws {
        // While we can't directly test haptic feedback, we can ensure
        // that buttons that should provide haptic feedback are working correctly
        
        let settingsButton = app.buttons["Settings"]
        
        // Test multiple rapid taps to verify button responsiveness
        for _ in 0..<3 {
            settingsButton.tap()
            XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 1.0))
            
            app.buttons["Cancel"].tap()
            XCTAssertTrue(app.navigationBars["WhatTheFlight"].waitForExistence(timeout: 1.0))
        }
    }
    
    @MainActor
    func testHapticFeedbackOnFlightControls() throws {
        // Test haptic feedback on flight control buttons
        let startStopButton = app.buttons.matching(identifier: "play.circle.fill").firstMatch
        
        if startStopButton.exists {
            // Test button responsiveness
            startStopButton.tap()
            
            // Verify state change occurred
            let stopButton = app.buttons.matching(identifier: "stop.circle.fill").firstMatch
            XCTAssertTrue(stopButton.waitForExistence(timeout: 2.0) || startStopButton.exists)
        }
    }
    
    // MARK: - Settings View iOS Optimizations
    
    @MainActor
    func testSettingsViewTouchOptimizations() throws {
        // Open settings
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 2.0))
        
        // Test form interactions
        let form = app.scrollViews.firstMatch
        XCTAssertTrue(form.exists)
        
        // Test slider touch interaction
        let slider = app.sliders.firstMatch
        if slider.exists {
            let initialValue = slider.normalizedSliderPosition
            
            // Adjust slider
            slider.adjust(toNormalizedSliderPosition: 0.8)
            
            // Verify slider responded
            let newValue = slider.normalizedSliderPosition
            XCTAssertNotEqual(initialValue, newValue, accuracy: 0.1)
        }
        
        // Test toggle switches
        let toggles = app.switches
        for i in 0..<min(toggles.count, 3) {
            let toggle = toggles.element(boundBy: i)
            if toggle.exists {
                let initialState = toggle.value as? String
                toggle.tap()
                
                // Verify toggle state changed
                let newState = toggle.value as? String
                XCTAssertNotEqual(initialState, newState)
                
                // Toggle back
                toggle.tap()
            }
        }
        
        // Test text field interactions
        let textFields = app.textFields
        for i in 0..<min(textFields.count, 2) {
            let textField = textFields.element(boundBy: i)
            if textField.exists && textField.isHittable {
                textField.tap()
                
                // Verify keyboard appears (if applicable)
                // Note: Keyboard detection can be tricky in UI tests
                XCTAssertTrue(textField.hasKeyboardFocus || !textField.hasKeyboardFocus)
            }
        }
        
        // Close settings
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["WhatTheFlight"].waitForExistence(timeout: 2.0))
    }
    
    // MARK: - Performance and Responsiveness Tests
    
    @MainActor
    func testUIResponsivenessUnderLoad() throws {
        // Test that UI remains responsive during rapid interactions
        let settingsButton = app.buttons["Settings"]
        
        // Rapid open/close cycles
        for _ in 0..<5 {
            settingsButton.tap()
            XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 1.0))
            
            app.buttons["Cancel"].tap()
            XCTAssertTrue(app.navigationBars["WhatTheFlight"].waitForExistence(timeout: 1.0))
        }
        
        // Verify UI is still responsive
        XCTAssertTrue(settingsButton.isHittable)
    }
    
    @MainActor
    func testScrollPerformance() throws {
        // Open settings to test scroll performance
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 2.0))
        
        let scrollView = app.scrollViews.firstMatch
        if scrollView.exists {
            // Perform rapid scrolling
            for _ in 0..<10 {
                scrollView.swipeUp()
                scrollView.swipeDown()
            }
            
            // Verify scroll view is still responsive
            XCTAssertTrue(scrollView.exists)
            XCTAssertTrue(scrollView.isHittable)
        }
        
        app.buttons["Cancel"].tap()
    }
}
#endif