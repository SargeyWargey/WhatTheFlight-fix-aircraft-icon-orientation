# WhatTheFlight Technical Stack

## Build System & Platform
- **Build System**: Xcode project with `.xcodeproj` configuration
- **Platforms**: iOS (18.5+), macOS (15.5+), tvOS (18.0+), visionOS (2.5+)
- **Language**: Swift 5.0
- **UI Framework**: SwiftUI with platform-specific adaptations
- **Architecture**: MVVM (Model-View-ViewModel) with service-oriented architecture

## Core Frameworks & Dependencies
- **SwiftUI**: Primary UI framework for all platforms
- **Combine**: Reactive programming and data binding
- **CoreLocation**: GPS services and geographic calculations
- **CloudKit**: Optional settings synchronization across devices
- **CoreMotion**: Device orientation and compass functionality
- **Foundation**: Core Swift functionality and networking

## External APIs
- **FlightRadar24 API**: Primary data source for flight information
  - Search endpoint: `https://data-cloud.flightradar24.com/zones/fcgi/feed.js`
  - Details endpoint: `https://data-live.flightradar24.com/clickhandler/`

## Architecture Patterns
- **MVVM**: Clear separation between UI, business logic, and data
- **Protocol-Oriented**: Extensive use of protocols for testability and modularity
- **Service Layer**: Dedicated services for networking, location, settings, and flight data
- **Reactive Programming**: Combine framework for data flow and state management

## Key Services
- `FlightService`: Core flight monitoring and data management
- `NetworkManager`: HTTP communication and API integration  
- `LocationManager`: Geographic services and permissions
- `SettingsManager`: Configuration persistence and CloudKit sync
- `AircraftPredictionService`: Flight path prediction and calculations

## Common Commands

### Building
```bash
# Open project in Xcode
open WhatTheFlight/WhatTheFlight.xcodeproj

# Build for iOS Simulator
xcodebuild -project WhatTheFlight/WhatTheFlight.xcodeproj -scheme WhatTheFlight -destination 'platform=iOS Simulator,name=iPhone 15 Pro' build

# Build for macOS
xcodebuild -project WhatTheFlight/WhatTheFlight.xcodeproj -scheme WhatTheFlight -destination 'platform=macOS' build
```

### Testing
```bash
# Run unit tests
xcodebuild test -project WhatTheFlight/WhatTheFlight.xcodeproj -scheme WhatTheFlight -destination 'platform=iOS Simulator,name=iPhone 15 Pro'

# Run UI tests
xcodebuild test -project WhatTheFlight/WhatTheFlight.xcodeproj -scheme WhatTheFlight -destination 'platform=iOS Simulator,name=iPhone 15 Pro' -only-testing:WhatTheFlightUITests
```

### Development
- Use Xcode for development, debugging, and Interface Builder
- SwiftUI Previews for rapid UI iteration
- Simulator testing across multiple device types and orientations
- Real device testing required for location services and motion features

## Configuration Files
- `WhatTheFlight.entitlements`: App sandbox and capability permissions
- `project.pbxproj`: Xcode project configuration with multi-platform targets
- Platform-specific Info.plist entries embedded in project configuration

## Performance Considerations
- 30-second default API polling interval (configurable 15-120s)
- Exponential backoff for network failures
- Memory-efficient flight data structures with automatic cleanup
- Battery optimization through power saving mode and background handling