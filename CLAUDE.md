# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

WhatTheFlight is a SwiftUI-based flight tracking application that monitors aircraft overhead using FlightRadar24 API data. The project targets iOS, macOS, and visionOS platforms and displays real-time flight information within configurable geographic bounds.

## Build & Test Commands

This is an Xcode project using standard Xcode build commands:

- **Build**: `xcodebuild -project WhatTheFlight.xcodeproj -scheme WhatTheFlight -configuration Debug build`
- **Test**: `xcodebuild -project WhatTheFlight.xcodeproj -scheme WhatTheFlight -configuration Debug test`
- **Run Tests**: `xcodebuild test -project WhatTheFlight.xcodeproj -scheme WhatTheFlight -destination 'platform=iOS Simulator,name=iPhone 15'`
- **Clean**: `xcodebuild -project WhatTheFlight.xcodeproj -scheme WhatTheFlight clean`

For development, open `WhatTheFlight.xcodeproj` in Xcode.

## Architecture

### Core Structure
- **MVVM Pattern**: Uses ViewModels (`MainViewModel`, `SettingsViewModel`) to manage state and business logic
- **Protocol-Oriented Services**: Service layer abstractions enable testability and dependency injection
- **Platform-Specific UI**: Conditional compilation for iOS/macOS differences using `#if os(macOS)`

### Key Components

#### Models (`WhatTheFlight/Models/`)
- `FlightData.swift`: Core flight data structures with nested types for airline, aircraft, route, and position
- `ConnectionStatus.swift`: Network connection state management
- `GeographicBounds.swift`: Coordinate boundary definitions for monitoring areas
- `NotificationSettings.swift`: User notification preferences
- `DisplayPreferences.swift`: UI customization settings

#### Services (`WhatTheFlight/Services/`)
- `FlightService.swift`: Primary service managing flight data fetching, monitoring, and state
- `NetworkManager.swift`: HTTP client for FlightRadar24 API interactions
- `LocationManager.swift`: Core Location wrapper for user position tracking
- `SettingsManager.swift`: UserDefaults persistence layer

#### ViewModels (`WhatTheFlight/ViewModels/`)
- `MainViewModel.swift`: Central state manager coordinating all services
- `SettingsViewModel.swift`: Settings UI state and persistence

#### Views (`WhatTheFlight/Views/`)
- `ContentView.swift`: Root view coordinator
- `FlightDisplayView.swift`: Primary flight information UI
- `SettingsView.swift`: Configuration interface
- `iOSComponents.swift` / `macOSComponents.swift`: Platform-specific UI components

### Testing Structure
- **Unit Tests**: Service and model testing with mocks in `WhatTheFlightTests/`
- **UI Tests**: Full application flow testing in `WhatTheFlightUITests/`
- **Mocks**: Comprehensive mock implementations for all service protocols

### Key Patterns
- **Service Protocols**: All services implement protocols for testability (`FlightServiceProtocol`, `NetworkManagerProtocol`)
- **ObservableObject**: ViewModels and services use Combine for reactive UI updates
- **Async/Await**: Modern concurrency throughout the networking layer
- **Platform Adaptation**: Conditional compilation and protocol-based platform differences

### FlightRadar24 API Integration
The app uses unofficial FlightRadar24 API endpoints with specific data parsing for the array-based response format. The `FlightService` handles rate limiting, retry logic with exponential backoff, and real-time monitoring with configurable intervals.

## Project Context

### Related Hardware Project
The repository includes a `flightportal-main/` directory containing a Python-based hardware project that shares the same flight tracking concept but targets embedded hardware (Adafruit MatrixPortal + LED matrix). This provides reference for:
- FlightRadar24 API usage patterns and geographic bounds configuration
- Flight data parsing strategies
- Display layout concepts for flight information

### Development Status
The project appears to be in active development with:
- Comprehensive testing infrastructure already in place
- Platform-specific UI handling for iOS/macOS/visionOS
- Modern Swift concurrency patterns (async/await)
- Reactive UI updates using Combine/ObservableObject
- Robust error handling and retry mechanisms

### Key Features
- **Real-time Flight Monitoring**: Configurable geographic bounds for tracking overhead aircraft
- **Cross-Platform**: Native SwiftUI implementation for iOS, macOS, and visionOS
- **Offline Capability**: Local caching and graceful degradation during network issues
- **User Customization**: Settings for notifications, display preferences, and monitoring parameters
- **macOS Enhancements**: Window management, keyboard shortcuts, and menu bar integration

### API Constraints
- Uses unofficial FlightRadar24 API (may break without notice)
- Implements rate limiting and exponential backoff for reliability
- Geographic bounds-based querying to minimize API load
- Handles various error conditions (rate limiting, network failures, malformed data)