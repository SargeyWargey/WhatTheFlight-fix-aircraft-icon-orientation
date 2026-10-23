# WhatTheFlight Code Enhancement Recommendations

## Overview
This document provides a comprehensive list of code optimizations and best practices for the WhatTheFlight iOS/macOS/tvOS app. Each recommendation includes specific implementation guidance that can be copy-pasted into Claude for implementation.

---

## 1. Performance Optimizations

### <font color="#00b050">1.1 Replace HStack/VStack with LazyHStack/LazyVStack for Large Lists - <font color="#00b050">IMPLEMENTED</font></font>
*Radar v2 (iPhone, iPad, Apple TV, Watch): already true. Every long list is a `List`, `LazyVStack` or `LazyVGrid`. The radar edge isn't a list: icons sit at their bearings and are capped at 32 (8 on the Watch), so a lazy stack doesn't apply there. Its real per-frame cost was the perimeter track, fixed under 1.2. The legacy files named below only build the macOS app.*
**Priority: High**
**Files: FlightDisplayView.swift, SettingsView.swift**

Replace standard stacks with lazy stacks for better performance when displaying large numbers of aircraft icons.

```swift
// Current implementation in perimeterAircraftOverlay
ForEach(layeredIcons, id: \.flight.id) { layerInfo in
    PerimeterAircraftView(...)
}

// Enhanced implementation:
ScrollView {
    LazyVStack {
        ForEach(layeredIcons, id: \.flight.id) { layerInfo in
            PerimeterAircraftView(...)
        }
    }
}
```

**Prompt for Claude:**
"Replace the ForEach loop in perimeterAircraftOverlay function in FlightDisplayView.swift with LazyVStack wrapped in ScrollView for better performance when displaying many aircraft icons. Ensure the lazy loading only creates views when they become visible."

### <font color="#00b050">1.2 Implement View Caching for Aircraft Icons - <font color="#00b050">IMPLEMENTED</font></font>
*Radar v2: each flight's operator, notable tags and type are worked out once per feed (`FlightProfile`, carried on `RadarContact.profile`), not every tick and every redraw. Perimeter track samples are cached by screen size, and the logbook is indexed by airframe. See Enhancements Spec B1, B2, B9.*
**Priority: High**
**Files: FlightDisplayView.swift, IconLayeringManager.swift**

Cache calculated positions and distances to avoid recalculating on every frame.

**Prompt for Claude:**
"Add a caching mechanism to IconLayeringManager.swift that stores calculated aircraft positions and distances. Only recalculate when aircraft data actually changes (not just on every view update). Use a dictionary keyed by flight ID with timestamp-based cache invalidation."

### <font color="#00b050">1.3 Optimize AsyncImage Loading with Placeholder Management - <font color="#00b050">IMPLEMENTED</font></font>
*Radar v2: `ProviderPhoto` (`UI/ProviderPhoto.swift`) replaces `AsyncImage` on the iPhone detail sheet and the Apple TV flight and logbook screens. It loads through `AircraftPhotoProvider` (Planespotters' required User-Agent, disk cache), decodes off the main thread and keeps decoded images in memory. Only the legacy macOS `FlightDisplayView` still uses `AsyncImage`. See Enhancements Spec A4.*
**Priority: Medium**
**Files: FlightDisplayView.swift**

The current AsyncImage implementation could be optimized with better placeholder management and caching.

**Prompt for Claude:**
"Optimize the AsyncImage implementation in CenterFlightView's aircraftPhotoSection. Add proper image caching, reduce placeholder rendering overhead, and implement progressive loading with a smaller initial placeholder that scales up when the image loads."

### <font color="#00b050">1.4 Reduce Timer Frequency for Background Updates - <font color="#00b050">IMPLEMENTED</font></font>
*Radar v2 counterpart: network polling adapts too (`Core/PollingPolicy.swift`): 5 s while something passes within a mile, up to 3× the setting when the sky is empty, never under 10 s on the Watch. See Enhancements Spec B5.*
**Priority: Medium**
**Files: AircraftPredictionService.swift, MainViewModel.swift**

Current 1-second prediction updates may be excessive.

**Prompt for Claude:**
"Modify AircraftPredictionService.swift to use adaptive timer intervals. Use 1-second updates when aircraft are very close (< 2 miles), 2-second updates for medium distance (2-5 miles), and 5-second updates for distant aircraft (> 5 miles). This should reduce CPU usage while maintaining accuracy where it matters most."

---

## 2. SwiftUI Best Practices

### <font color="#00b050">2.1 Replace .onChange with Modern SwiftUI Patterns - <font color="#00b050">IMPLEMENTED</font></font>
*Radar v2: wherever `onAppear` and an `onChange` ran the same work, it is now one `onChange(of:initial: true)`: the TV root's idle timer and logbook sync, the maps' framing (detail, whereabouts, TV logbook), the TV place search, and the edge icons' pulse. Groups of related `onChange`s now watch one derived value: the TV and Watch observer (coordinate, place and mode as one key), and the Watch's `isTracking`, which fixes Enhancements A1. The iPhone root does the same: idle timer, logbook sync, one observer key, and the raise detector as a derived value (done with the iPhone Duo work). Its compass and clock observers sit in a tiny child view (`ChangeObserver`), and its centre state and map pane are read in their own views, so the root and any sheet over it no longer re-evaluate on every compass update or tick.*
**Priority: High**
**Files: ContentView.swift, SettingsView.swift, FlightDisplayView.swift**

Many `.onChange` modifiers can be replaced with more efficient patterns.

**Prompt for Claude:**
"Replace all .onChange(of:) modifiers in ContentView.swift with the newer .onChange(of:initial:_:) pattern where appropriate. Focus on the scenePhase, flight data, and settings change handlers. Ensure the new pattern captures the correct state values."

### <font color="#00b050">2.2 Implement Proper @StateObject vs @ObservedObject Usage - <font color="#00b050">IMPLEMENTED</font></font>
*Radar v2 uses Observation (`@Observable`), not `ObservableObject`. Owners hold objects in state and children take them as plain properties, which was already the case. The modern trap is that `@State private var x = Object()` runs `Object()` on every view init, unlike `@StateObject`. Sheets over the radar are re-created every tick and on every compass update, so Sky View built an `AVCaptureSession`, and the TV link screen an `MCSession`, many times a second. `@LazyState` (`UI/LazyState.swift`) builds the object once, the first time `body` reads it. It is used for all 18 view-owned objects (camera, motion managers, location services, Multipeer, place search, speech, logbook).*
**Priority: Medium**
**Files: ContentView.swift, FlightDisplayView.swift**

Some objects are created as @StateObject when they should be @ObservedObject and vice versa.

**Prompt for Claude:**
"Review and fix @StateObject vs @ObservedObject usage in ContentView.swift and FlightDisplayView.swift. MainViewModel should be @StateObject in ContentView but @ObservedObject when passed to child views. MotionManager and IconLayeringManager should follow the same pattern."

### 2.3 Use ViewThatFits More Effectively
*Radar v2: reviewed, not needed yet. The radar face, edge track, iPad map pane and TV split are laid out from their measured size, and every text row checked (detail actions and stats, TV action row, Watch details) fits at the fixed type sizes, so a `ViewThatFits` would never switch. It becomes useful with Dynamic Type (Enhancements A6). The detail sheet's button row and stat tiles are the places for it then.*
**Priority: Medium**
**Files: FlightDisplayView.swift**

The current ViewThatFits implementation could be expanded to more components.

**Prompt for Claude:**
"Expand the use of ViewThatFits in FlightDisplayView.swift to handle different screen sizes more gracefully. Add ViewThatFits to the main radar display content and perimeter aircraft display to automatically adapt to different device orientations and screen sizes."

### <font color="#00b050">2.4 Implement Proper Task Lifecycle Management - <font color="#00b050">IMPLEMENTED</font></font>
*Radar v2: the iPhone → TV hand-off task is kept and cancelled when its screen closes, and its waits stop on cancellation (Enhancements A12). The TV root's place naming is a `.task(id:)` that cancels a stale lookup. The TV's radius re-query is debounced in a `.task(id:)` (A13). Naming an iPhone hand-off or a picked TV place can no longer be overwritten by an older lookup. Synchronous start/stop pairs (compass, sensors) stay `onAppear`/`onDisappear`, which is right for them. The iPhone root's place naming was a new unstructured task on every GPS fix. It is now a `.task(id:)` keyed on `PlaceNamer`'s ~5 km square, so moving into a new area cancels a stale lookup, but a slow one isn't cancelled by every fix.*
**Priority: High**
**Files: FlightDisplayView.swift, AircraftPredictionService.swift**

Replace .onAppear/.onDisappear with .task for better async lifecycle management.

**Prompt for Claude:**
"Replace .onAppear and .onDisappear modifiers in FlightDisplayView.swift with .task modifiers for better async lifecycle management. Ensure proper cancellation of async operations when views disappear. Focus on the motionManager lifecycle and aircraft photo loading tasks."

---

## 3. Architecture Improvements

### <font color="#00b050">3.1 Implement Dependency Injection Container - <font color="#00b050">IMPLEMENTED</font></font>
*Radar v2: already in place, through initialisers rather than a container. `RadarModel(settings:liveFeed:demoFeed:)` gets its feeds and settings passed in, and the observer is pushed in, so it never touches CoreLocation. `FlightRadarFeed(session:)`, `Logbook(fileURL:photoDirectory:device:)` and `NearbyTraffic`'s `feed:` are injectable too. The root views (`RadarRootView`, `TVRadarRootView`, `WatchRootView`) are where everything is built. Tests swap in `StubFeed`, `StubURLProtocol` and in-memory logbooks. A `ServiceContainer` would only add a service locator on top. The few `.shared` singletons are genuinely one-per-app (router, Sky Watch, Watch link, photo provider).*
**Priority: Medium**
**Files: ContentView.swift, MainViewModel.swift**

Current service initialization is tightly coupled.

**Prompt for Claude:**
"Create a ServiceContainer class that manages all service dependencies (NetworkManager, FlightService, SettingsManager, LocationManager). Modify ContentView.swift to use dependency injection instead of creating services directly in the init method. This will improve testability and modularity."

### <font color="#00b050">3.2 Add Proper Error Handling with Result Types - <font color="#00b050">IMPLEMENTED</font></font>
*Radar v2: done differently. `async throws` with a typed `FeedError` is the modern form, and `Result` is kept for the one place it helps: `FlightRadarFeed.fetchAll` collects partial failures from parallel requests. Two real gaps were fixed. A logbook file that fails to decode used to be silently replaced by the next save; it is now set aside as `Logbook-unreadable-<time>.json`, and saving pauses for the session if the file can't even be opened. The feed called every network failure "You're offline"; DNS, TLS and refused connections now read "Can't reach Flightradar24 right now" (`FeedError.unreachable`). Tests: `ErrorHandlingTests`.*
**Priority: High**
**Files: NetworkManager.swift, FlightService.swift**

Current error handling could be more robust.

**Prompt for Claude:**
"Refactor NetworkManager.swift and FlightService.swift to use Result<Success, Failure> return types instead of throwing errors directly. This will provide better error handling and make the async/await code more robust. Update all calling code to handle the Result types appropriately."

### <font color="#00b050">3.3 Implement Repository Pattern for Data Management - <font color="#00b050">IMPLEMENTED</font></font>
*Radar v2: already in place. `protocol FlightFeed` is the repository (`flights(in:)`, `search`, `lookup`), with `FlightRadarFeed` and `DemoTrafficFeed` behind it and `FlightFeedParser` doing the mapping. `RadarModel` holds the business logic: radius filter, sorting, focus, pins, dead reckoning and polling policy. A second data source (Enhancements C1) is another `FlightFeed`.*
**Priority: Medium**
**Files: FlightService.swift, MainViewModel.swift**

Separate data access from business logic.

**Prompt for Claude:**
"Create a FlightRepository protocol and implementation that separates data fetching from business logic. Move all API calls from FlightService to FlightRepository, and have FlightService focus on business logic like filtering, sorting, and state management."

### <font color="#00b050">3.4 Add Proper Logging Infrastructure - <font color="#00b050">IMPLEMENTED</font></font>
*Radar v2: `Log` (`Core/Log.swift`) gives one `os.Logger` per area: feed, logbook, sync, link, sensors, camera, alerts, ui. That's Apple's unified logging, so Xcode's console already shows each message's file and line, and Console.app filters by category. It replaces the last `print`s and covers failures that used to be silent: feed errors with the real URL error or HTTP status, back-off and recovery, logbook and sync-state saves, iCloud fetches, Watch context and Apple TV hand-off failures, the camera, saving to Photos, the Sky Watch Live Activity, posting alerts and location errors. Interpolated strings stay private in release logs unless marked public.*
**Priority: Low**
**Files: All service files**

Current print statements should be replaced with proper logging.

**Prompt for Claude:**
"Create a Logger protocol and implementation that provides different log levels (debug, info, warning, error). Replace all print statements throughout the codebase with proper logging calls. Include file name, function name, and line number in log messages for better debugging."

---

## 4. Memory Management

### <font color="#00b050">4.1 Fix Potential Memory Leaks in Combine Publishers - <font color="#00b050">IMPLEMENTED</font></font>
*Radar v2: already clean. There's no Combine (Observation instead); the one publisher is a SwiftUI `.onReceive` that SwiftUI cancels itself. Every long-lived callback (Core Motion handlers, `NotificationCenter` observers, KVO on the camera's zoom, the frame tracker, logbook and pin sync) captures `[weak self]`, and repeating work is a `Task` cancelled by `stop()` or by its view's `.task`. Sky View hands the motion manager a closure holding only the frame tracker, so closing it releases the camera and sensors. The closures the root views store hold app-lifetime objects only.*
**Priority: High**
**Files: MainViewModel.swift, SettingsManager.swift**

Some Combine subscriptions may not be properly cancelled.

**Prompt for Claude:**
"Review all Combine publishers in MainViewModel.swift and SettingsManager.swift for potential memory leaks. Ensure all subscriptions are properly stored in cancellables and cancelled when objects are deallocated. Add weak self captures where appropriate to prevent retain cycles."

### <font color="#00b050">4.2 Optimize Image Memory Usage - <font color="#00b050">IMPLEMENTED</font></font>
*Radar v2: both image caches are now limited by decoded size, not count: Sky View photos to 50 MB (a 1600 px photo page is about 7 MB) and Planespotters photos to 30 MB. Being `NSCache`, they also empty themselves under memory pressure. Sky View photos were already decoded at the size shown (400 px thumbnails, 1600 px pages, via ImageIO). The Apple Watch decoded Planespotters photos at full size on the main thread; it now decodes them off the main thread at the screen's width.*
**Priority: Medium**
**Files: FlightDisplayView.swift**

Aircraft photos may consume excessive memory.

**Prompt for Claude:**
"Add image memory management to the aircraft photo loading in FlightDisplayView.swift. Implement image resizing to appropriate display sizes, add memory pressure handling, and implement an LRU cache for aircraft photos with a reasonable memory limit (e.g., 50MB)."

### <font color="#00b050">4.3 Implement Proper Timer Cleanup - <font color="#00b050">IMPLEMENTED</font></font>
*Radar v2: there are no `Timer`s. Polling and the 1 Hz tick are `Task` loops that `RadarModel.stop()` cancels, and `start()` guards against a second copy. Animation uses `TimelineView`, which pauses itself. The counterpart gap was a sensor left on: `RadarLocationService` began device-orientation updates (they run the accelerometer) in `start()` and never ended them. `stop()` now removes the observer and balances `begin` with `end`.*
**Priority: High**
**Files: AircraftPredictionService.swift, MainViewModel.swift, FlightService.swift**

Ensure all timers are properly invalidated.

**Prompt for Claude:**
"Add comprehensive timer cleanup to all classes that use Timer. Ensure timers are invalidated in deinit methods and when objects are no longer needed. Add timer state tracking to prevent multiple timers from running simultaneously."

---

## 5. User Experience Enhancements

### 5.1 Add Haptic Feedback Consistently
**Priority: Low**
**Files: ContentView.swift, SettingsView.swift**

Haptic feedback is inconsistent across the app.

**Prompt for Claude:**
"Add consistent haptic feedback throughout the app. Create a HapticManager class that provides different feedback types (light, medium, heavy, success, error). Use appropriate feedback for different user interactions like button taps, swipe gestures, and state changes."

### 5.2 Implement Smooth Animations for State Transitions
**Priority: Medium**
**Files: FlightDisplayView.swift, ContentView.swift**

Some state transitions are abrupt.

**Prompt for Claude:**
"Add smooth animations for major state transitions in the app. Focus on connection status changes, flight selection changes, and settings updates. Use appropriate animation curves and durations. Ensure animations can be disabled via the settings."

### 5.3 Add Loading States for Better UX
**Priority: Medium**
**Files: FlightDisplayView.swift, SettingsView.swift**

Some operations lack proper loading indicators.

**Prompt for Claude:**
"Add comprehensive loading states throughout the app. Create a LoadingStateView component that can be reused. Add loading indicators for flight data fetching, location requests, settings sync, and aircraft photo loading. Ensure loading states are accessible."

---

## 6. Accessibility Improvements

### 6.1 Add Comprehensive VoiceOver Support
**Priority: High**
**Files: FlightDisplayView.swift, ContentView.swift**

Current accessibility support is minimal.

**Prompt for Claude:**
"Add comprehensive VoiceOver support to FlightDisplayView.swift. Add accessibility labels, hints, and values for all interactive elements. Ensure aircraft information is properly announced, and navigation between aircraft is accessible. Add accessibility actions for common operations."

### 6.2 Implement Dynamic Type Support
**Priority: Medium**
**Files: All view files**

Text doesn't scale properly with system font sizes.

**Prompt for Claude:**
"Add proper Dynamic Type support throughout the app. Ensure all text scales appropriately with system font size settings. Use .font(.title), .font(.body), etc. instead of fixed font sizes. Test with the largest accessibility font sizes."

### 6.3 Add High Contrast Mode Support
**Priority: Low**
**Files: All view files**

Colors may not be accessible in high contrast mode.

**Prompt for Claude:**
"Add high contrast mode support by creating adaptive colors that work well in both normal and high contrast modes. Update all color definitions to use semantic colors or create custom colors that adapt to accessibility settings."

---

## 7. Code Quality & Maintainability

### 7.1 Extract Magic Numbers to Constants
**Priority: Medium**
**Files: All files**

Many magic numbers are scattered throughout the code.

**Prompt for Claude:**
"Extract all magic numbers throughout the codebase into properly named constants. Create a Constants.swift file with nested structs for different categories (UI, Network, Location, etc.). Replace all hardcoded values with references to these constants."

### 7.2 Add Comprehensive Unit Tests
**Priority: High**
**Files: Test files**

Current test coverage appears minimal.

**Prompt for Claude:**
"Create comprehensive unit tests for all service classes (NetworkManager, FlightService, SettingsManager, LocationManager). Focus on testing business logic, error handling, and edge cases. Use dependency injection to make classes more testable."

### 7.3 Implement Proper Documentation
**Priority: Low**
**Files: All files**

Code documentation is inconsistent.

**Prompt for Claude:**
"Add comprehensive documentation to all public methods and properties throughout the codebase. Use proper Swift documentation format with /// comments. Include parameter descriptions, return value descriptions, and usage examples where appropriate."

### 7.4 Refactor Large Methods
**Priority: Medium**
**Files: FlightDisplayView.swift, MainViewModel.swift**

Some methods are too long and complex.

**Prompt for Claude:**
"Refactor large methods in FlightDisplayView.swift and MainViewModel.swift into smaller, more focused methods. Focus on the calculateAircraftPositions, setupBindings, and body computed properties. Each method should have a single responsibility."

---

## 8. Security & Privacy

### 8.1 Add Location Privacy Descriptions
**Priority: High**
**Files: Info.plist, LocationManager.swift**

Location usage descriptions should be more specific.

**Prompt for Claude:**
"Update location privacy descriptions in Info.plist to be more specific about how location data is used. Add runtime privacy explanations in LocationManager.swift that users can access. Ensure location data is only used for the stated purposes."

### 8.2 Implement Data Encryption for Sensitive Settings
**Priority: Medium**
**Files: SettingsManager.swift**

Some settings might benefit from encryption.

**Prompt for Claude:**
"Add encryption for sensitive settings in SettingsManager.swift. Use Keychain Services for storing sensitive data like API keys or user preferences that shouldn't be easily accessible. Provide migration from UserDefaults to Keychain for existing users."

### 8.3 Add Network Security Measures
**Priority: Medium**
**Files: NetworkManager.swift**

Network requests could be more secure.

**Prompt for Claude:**
"Add network security measures to NetworkManager.swift including certificate pinning, request signing, and rate limiting. Implement proper SSL/TLS validation and add protection against common network attacks."

---

## 9. Platform-Specific Optimizations

### 9.1 Optimize for macOS with Native Controls
**Priority: Medium**
**Files: ContentView.swift, SettingsView.swift**

macOS version could use more native controls.

**Prompt for Claude:**
"Enhance the macOS version with native macOS controls and behaviors. Add proper menu bar integration, keyboard shortcuts, and window management. Use NSToolbar instead of SwiftUI toolbar where appropriate for better native feel."

### 9.2 Improve tvOS Navigation
**Priority: Medium**
**Files: tvOSComponents.swift, ContentView.swift**

tvOS navigation could be more intuitive.

**Prompt for Claude:**
"Improve tvOS navigation by adding proper focus management, better remote control support, and more intuitive navigation patterns. Ensure all interactive elements are properly focusable and provide clear visual feedback."

### 9.3 Add iPad-Specific Layouts
**Priority: Low**
**Files: ContentView.swift, FlightDisplayView.swift**

iPad could benefit from more sophisticated layouts.

**Prompt for Claude:**
"Create iPad-specific layouts that take advantage of the larger screen. Implement split-view layouts, sidebar navigation, and multi-column displays where appropriate. Use size classes to provide optimal layouts for different iPad orientations."

---

## 10. Data Management

### 10.1 Implement Core Data for Offline Storage
**Priority: Medium**
**Files: New Core Data stack**

Add offline capability for flight history.

**Prompt for Claude:**
"Implement Core Data stack for storing flight history and offline capabilities. Create entities for FlightData, AircraftInfo, and RouteInfo. Add data synchronization between Core Data and the network layer. Implement proper data migration strategies."

### 10.2 Add Data Validation Layer
**Priority: High**
**Files: FlightData.swift, NetworkManager.swift**

Current data validation is minimal.

**Prompt for Claude:**
"Add comprehensive data validation to FlightData.swift and NetworkManager.swift. Validate all incoming data from the API, sanitize user inputs, and provide meaningful error messages for invalid data. Implement data schema validation."

### 10.3 Implement Data Compression
**Priority: Low**
**Files: NetworkManager.swift, SettingsManager.swift**

Large data transfers could be compressed.

**Prompt for Claude:**
"Add data compression to network requests and local storage. Implement gzip compression for API requests and compress large data structures before storing in UserDefaults or CloudKit. Measure and optimize data transfer sizes."

---

## Implementation Priority Guide

### High Priority (Implement First)
1. Performance optimizations (1.1, 1.4)
2. SwiftUI best practices (2.1, 2.4)
3. Memory management fixes (4.1, 4.3)
4. Accessibility improvements (6.1)
5. Error handling improvements (3.2)
6. Data validation (10.2)

### Medium Priority (Implement Second)
7. Architecture improvements (3.1, 3.3)
8. User experience enhancements (5.2, 5.3)
9. Code quality improvements (7.1, 7.4)
10. Platform-specific optimizations (9.1, 9.2)

### Low Priority (Implement Later)
11. Advanced features (remaining items)
12. Documentation and testing
13. Security enhancements
14. Performance fine-tuning

---

## Usage Instructions

Each recommendation includes a specific prompt that can be copied and pasted into Claude for implementation. When using these prompts:

1. **Copy the exact prompt text** provided for each recommendation
2. **Provide the relevant file(s)** mentioned in the recommendation
3. **Test thoroughly** after each implementation
4. **Implement in priority order** for best results
5. **Consider dependencies** between recommendations

## Notes

- All recommendations are based on SwiftUI best practices and performance optimization principles
- Each prompt is designed to be self-contained and actionable
- Implementation should be done incrementally with testing between changes
- Some recommendations may require additional dependencies or framework updates

---

*Generated on: January 8, 2025*
*Based on: WhatTheFlight codebase analysis using SwiftUI best practices*