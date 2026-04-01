# WhatTheFlight Project Structure

## Root Directory Organization
```
WhatTheFlight/                    # Main Xcode project directory
├── WhatTheFlight/               # Main app target
├── WhatTheFlightTests/          # Unit tests
├── WhatTheFlightUITests/        # UI automation tests
└── WhatTheFlight.xcodeproj/     # Xcode project configuration
```

## Main App Structure (`WhatTheFlight/WhatTheFlight/`)

### Core Application Files
- `WhatTheFlightApp.swift` - App entry point with platform-specific configurations
- `ContentView.swift` - Root view with platform-adaptive layouts
- `WhatTheFlight.entitlements` - App capabilities and sandbox permissions

### Architecture Layers

#### Models (`Models/`)
- `FlightData.swift` - Core flight data structures and calculations
- `GeographicBounds.swift` - Geographic boundary definitions
- `DisplayPreferences.swift` - UI customization settings
- `NotificationSettings.swift` - Alert and notification configurations
- `ConnectionStatus.swift` - Network state management

#### ViewModels (`ViewModels/`)
- `MainViewModel.swift` - Primary business logic coordinator
- `SettingsViewModel.swift` - Settings management and validation

#### Views (`Views/`)
- `FlightDisplayView.swift` - Main radar-style flight display
- `SettingsView.swift` - Configuration interface
- `iOSComponents.swift` - iOS-specific UI components
- `macOSComponents.swift` - macOS-specific UI components  
- `tvOSComponents.swift` - tvOS-specific UI components

#### Services (`Services/`)
- `FlightService.swift` - Flight monitoring and data management
- `NetworkManager.swift` - HTTP communication and API integration
- `LocationManager.swift` - GPS services and geographic calculations
- `SettingsManager.swift` - Configuration persistence and CloudKit sync
- `AircraftPredictionService.swift` - Flight path prediction algorithms
- `AirportDatabase.swift` - Airport code and name resolution
- `IconLayeringManager.swift` - Aircraft icon rendering
- `MotionManager.swift` - Device orientation and compass

### Assets (`Assets.xcassets/`)
- `AppIcon.appiconset/` - Multi-platform app icons
- `helicopter.imageset/` - Aircraft type indicators
- `helicopterActive.imageset/` - Active state indicators
- Platform-specific image assets

## Test Structure

### Unit Tests (`WhatTheFlightTests/`)
```
Models/                          # Model validation tests
Services/                        # Service layer tests  
ViewModels/                      # Business logic tests
Views/                          # View component tests
Mocks/                          # Test doubles and mock objects
```

### UI Tests (`WhatTheFlightUITests/`)
```
WhatTheFlightUITests.swift       # Core UI automation
SettingsViewUITests.swift        # Settings interface tests
iOSSpecificUITests.swift         # iOS platform tests
macOSSpecificUITests.swift       # macOS platform tests
tvOSSpecificUITests.swift        # tvOS platform tests
```

## Supporting Files

### Documentation
- `WhatTheFlight Functional Specification.md` - Comprehensive feature documentation
- `FlightRadar24_API_Data_Fields.md` - API integration reference
- Various enhancement and update documentation files

### Assets & Resources
- `AppIcons/` - Source app icon files in multiple sizes
- `Assests/` - Additional graphics and background images
- `Mockups/` - Design references and prototypes

## Naming Conventions

### Files
- Swift files use PascalCase: `FlightService.swift`
- Test files append "Tests": `FlightServiceTests.swift`
- Mock files prefix with "Mock": `MockFlightService.swift`

### Code Structure
- **Protocols**: End with "Protocol" (`FlightServiceProtocol`)
- **Extensions**: Group related functionality with `// MARK: -` comments
- **Constants**: Use nested structs for organization
- **Published Properties**: Use `@Published` for reactive data binding

### Platform-Specific Code
```swift
#if os(iOS)
// iOS-specific implementation
#elseif os(macOS)  
// macOS-specific implementation
#elseif os(tvOS)
// tvOS-specific implementation
#endif
```

## Key Architectural Principles
- **Protocol-Oriented Design**: Extensive use of protocols for testability
- **Dependency Injection**: Services injected into ViewModels for testing
- **Reactive Programming**: Combine framework for data flow
- **Platform Adaptation**: Single codebase with platform-specific optimizations
- **Service Layer Separation**: Clear boundaries between UI, business logic, and data