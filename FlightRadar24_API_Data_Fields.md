# FlightRadar24 API Data Fields Documentation

This document provides a comprehensive overview of all data fields available from the FlightRadar24 API as implemented in the WhatTheFlight application.

## API Response Structure

The FlightRadar24 API returns flight data as a JSON object where each flight is keyed by its unique ID and contains an array of data fields.

### Raw API Response Format

```json
{
  "flight_id_1": [
    "ICAO24_code",      // [0] ICAO24 hex identifier
    40.7128,            // [1] Latitude (decimal degrees)
    -74.0060,           // [2] Longitude (decimal degrees)
    270,                // [3] Track/Heading (degrees)
    35000,              // [4] Altitude (feet)
    450,                // [5] Speed (knots)
    "1200",             // [6] Squawk code
    "T-KJFK1",          // [7] Radar identifier
    "B738",             // [8] Aircraft model code
    "N123AA",           // [9] Aircraft registration
    1691234567,         // [10] Timestamp (Unix)
    "JFK",              // [11] Origin airport (IATA code)
    "LAX",              // [12] Destination airport (IATA code)
    "AA123",            // [13] Flight number
    0,                  // [14] On ground flag (0/1)
    0,                  // [15] Vertical speed (ft/min)
    "AAL123",           // [16] Callsign
    1                   // [17] Data source
  ],
  "full_count": 1234,
  "version": 4
}
```

## Parsed Data Structure

The raw API data is parsed into structured Swift objects for easier use within the application.

### FlightData (Main Object)

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| `id` | String | Unique flight identifier from API | `"abc123"` |
| `flightNumber` | String? | Commercial flight number | `"AA123"` |
| `callsign` | String? | Air traffic control callsign | `"AAL123"` |
| `airline` | AirlineInfo? | Airline information | See AirlineInfo below |
| `aircraft` | AircraftInfo? | Aircraft details | See AircraftInfo below |
| `route` | RouteInfo? | Origin and destination | See RouteInfo below |
| `position` | FlightPosition? | Current position and movement | See FlightPosition below |
| `lastUpdated` | Date | When data was last refreshed | `2025-08-02T10:30:00Z` |

#### Computed Properties
| Property | Type | Description | Example |
|----------|------|-------------|---------|
| `displayIdentifier` | String | Primary display name (flight number, callsign, or ID) | `"AA123"` |
| `routeDescription` | String | Formatted route string | `"JFK → LAX"` |
| `aircraftDescription` | String | Formatted airline and aircraft info | `"American Airlines • Boeing 737-800"` |

#### Location Methods
| Method | Return Type | Description | Example |
|--------|-------------|-------------|---------|
| `distanceFromLocation(_:)` | Double? | Distance in miles from given location | `245.7` |
| `bearingFromLocation(_:)` | Double? | Cardinal direction (0-360°) from given location | `270.5` |
| `isMovingTowardsLocation(_:)` | Bool? | Whether aircraft is approaching given location | `true` |

### AirlineInfo

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| `name` | String | Full airline name | `"American Airlines"` |
| `code` | String? | IATA airline code | `"AA"` |

**Example:**
```swift
AirlineInfo(name: "American Airlines", code: "AA")
```

### AircraftInfo

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| `model` | String | Aircraft model/type | `"Boeing 737-800"` |
| `code` | String | Aircraft type code | `"B738"` |
| `registration` | String? | Aircraft tail number | `"N123AA"` |

**Example:**
```swift
AircraftInfo(model: "Boeing 737-800", code: "B738", registration: "N123AA")
```

### RouteInfo

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| `origin` | AirportInfo | Departure airport | See AirportInfo below |
| `destination` | AirportInfo | Arrival airport | See AirportInfo below |

**Example:**
```swift
RouteInfo(
    origin: AirportInfo(name: "John F. Kennedy International Airport", iataCode: "JFK", city: "New York"),
    destination: AirportInfo(name: "Los Angeles International Airport", iataCode: "LAX", city: "Los Angeles")
)
```

### AirportInfo

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| `name` | String | Full airport name | `"John F. Kennedy International Airport"` |
| `iataCode` | String | 3-letter IATA airport code | `"JFK"` |
| `city` | String? | Airport city | `"New York"` |

#### Computed Properties
| Property | Type | Description | Example |
|----------|------|-------------|---------|
| `displayName` | String | Airport name without "Airport" suffix | `"John F. Kennedy International"` |

**Example:**
```swift
AirportInfo(name: "John F. Kennedy International Airport", iataCode: "JFK", city: "New York")
```

### FlightPosition

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| `latitude` | Double | Latitude in decimal degrees | `40.7128` |
| `longitude` | Double | Longitude in decimal degrees | `-74.0060` |
| `altitude` | Int? | Altitude in feet | `35000` |
| `speed` | Int? | Ground speed in knots | `450` |
| `heading` | Int? | Track/heading in degrees (0-360) | `270` |

#### Computed Properties
| Property | Type | Description | Example |
|----------|------|-------------|---------|
| `isValid` | Bool | Whether coordinates are in valid ranges | `true` |
| `altitudeDescription` | String | Formatted altitude string | `"35000 ft"` |
| `speedDescription` | String | Formatted speed string | `"450 kts"` |

**Example:**
```swift
FlightPosition(latitude: 40.7128, longitude: -74.0060, altitude: 35000, speed: 450, heading: 270)
```

## Raw API Array Index Reference

When parsing the raw API response array, the following indices correspond to specific data fields:

| Index | Field | Type | Description | Example |
|-------|-------|------|-------------|---------|
| 0 | ICAO24 Code | String | Aircraft unique identifier | `"A12345"` |
| 1 | Latitude | Double | Position latitude | `40.7128` |
| 2 | Longitude | Double | Position longitude | `-74.0060` |
| 3 | Track/Heading | Int | Aircraft heading (degrees) | `270` |
| 4 | Altitude | Int | Altitude in feet | `35000` |
| 5 | Speed | Int | Ground speed in knots | `450` |
| 6 | Squawk | String | Transponder code | `"1200"` |
| 7 | Radar | String | Radar facility identifier | `"T-KJFK1"` |
| 8 | Aircraft Model | String | Aircraft type code | `"B738"` |
| 9 | Registration | String | Aircraft tail number | `"N123AA"` |
| 10 | Timestamp | Int | Unix timestamp | `1691234567` |
| 11 | Origin | String | Origin airport IATA code | `"JFK"` |
| 12 | Destination | String | Destination airport IATA code | `"LAX"` |
| 13 | Flight Number | String | Commercial flight number | `"AA123"` |
| 14 | On Ground | Int | Ground status (0=airborne, 1=ground) | `0` |
| 15 | Vertical Speed | Int | Rate of climb/descent (ft/min) | `0` |
| 16 | Callsign | String | ATC callsign | `"AAL123"` |
| 17 | Source | Int | Data source identifier | `1` |

## Complete Example

Here's a complete example of a parsed FlightData object with all fields populated:

```swift
FlightData(
    id: "abc123",
    flightNumber: "AA123",
    callsign: "AAL123",
    airline: AirlineInfo(name: "American Airlines", code: "AA"),
    aircraft: AircraftInfo(model: "Boeing 737-800", code: "B738", registration: "N123AA"),
    route: RouteInfo(
        origin: AirportInfo(name: "John F. Kennedy International Airport", iataCode: "JFK", city: "New York"),
        destination: AirportInfo(name: "Los Angeles International Airport", iataCode: "LAX", city: "Los Angeles")
    ),
    position: FlightPosition(latitude: 40.7128, longitude: -74.0060, altitude: 35000, speed: 450, heading: 270),
    lastUpdated: Date()
)
```

## Data Availability Notes

- **Optional Fields**: Most fields except `id`, `position.latitude`, `position.longitude`, and `lastUpdated` are optional and may be `nil` if not provided by the API
- **Airline Information**: The `airline` field is typically populated separately from detailed flight lookups, not the main position feed
- **Aircraft Type Detection**: Helicopter vs airplane detection is performed by checking if the aircraft code contains "H"
- **Distance Calculations**: All distance calculations are performed client-side using CoreLocation
- **Coordinate Validation**: Position coordinates are validated to ensure they fall within valid latitude (-90 to 90) and longitude (-180 to 180) ranges

## Rate Limiting Information

### What the Code Shows:

1. **Rate Limit Detection**: The app detects HTTP 429 status codes (rate limited) and handles them specifically
2. **Retry Logic**: When rate limited, it uses exponential backoff with these settings:
    - **Max Retries**: 5 attempts
    - **Base Delay**: 1 second
    - **Exponential Backoff**: Delay doubles each retry (1s, 2s, 4s, 8s, 16s)
    - **Default Query Interval**: 30 seconds

### What the Documentation Says:

- The FlightRadar24 API is **unofficial** and may change without notice
- **Rate limiting is enforced server-side**
- The app implements rate limiting handling and exponential backoff for reliability

### Exact Rate Limits:

The code doesn't specify the exact rate limits because:

1. **It's an unofficial API** - FlightRadar24 doesn't publish official documentation
2. **Limits may vary** - They could change without notice
3. **Server-side enforcement** - The limits are determined by FlightRadar24's servers

### What We Can Infer:

- **30-second intervals seem safe** - This is the default the app uses
- **10-second intervals were risky** - That's why you had the enhanced tracking feature removed
- **Geographic bounds help** - The app queries specific areas rather than global data, which reduces load
- **Retry logic suggests limits exist** - The sophisticated backoff system indicates rate limiting is a real concern

### Recommendations:

1. **Stick with 30-second intervals** - This appears to be a safe default
2. **Monitor for 429 errors** - The app will show "Rate Limited" status if you hit limits
3. **Consider longer intervals** - If you're still getting rate limited, you could increase to 45-60 seconds
4. **Smaller geographic bounds** - Reduce the search radius to minimize data requested per call

The app is well-designed to handle rate limiting gracefully, so you should see clear feedback if you're hitting limits rather than just failing silently.