// swift-tools-version:6.0
//
// Runs the radar core's unit tests from the command line with `swift test`, independent of
// the Xcode test targets. Only platform-neutral files are compiled here (no UI, no
// CoreLocation managers). Open WhatTheFlight.xcodeproj to build the app itself.
//
import PackageDescription

let package = Package(
    name: "WhatTheFlightCore",
    platforms: [.macOS(.v15), .iOS(.v18)],
    targets: [
        .target(
            name: "WhatTheFlight",
            path: "WhatTheFlight",
            sources: [
                "Core",
                "Data",
                "Radar",
                "Models/GeographicBounds.swift",
                "Services/FlightFeed.swift",
                "Services/RadarSettings.swift",
                "Services/SharedRadarStore.swift",
                "Services/TVLink.swift",
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "WhatTheFlightTests",
            dependencies: ["WhatTheFlight"],
            path: "WhatTheFlightTests/Radar",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
