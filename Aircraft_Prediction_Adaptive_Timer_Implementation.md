# Aircraft Prediction Service - Adaptive Timer Implementation

## Overview
Successfully implemented adaptive timer intervals in `AircraftPredictionService.swift` to optimize CPU usage while maintaining accuracy where it matters most. The system now uses different update frequencies based on aircraft distance from the user location.

## Implementation Details

### Timer Intervals
- **Close Distance (< 2 miles)**: 1-second updates for maximum accuracy
- **Medium Distance (2-5 miles)**: 2-second updates for balanced performance
- **Distant Aircraft (> 5 miles)**: 5-second updates for reduced CPU usage

### Key Changes Made

#### 1. AircraftPredictionService.swift
- **Added distance-based properties**:
  - `userLocation: CLLocation?` - Tracks user location for distance calculations
  - Distance thresholds: `closeDistanceThreshold` (2.0 miles), `mediumDistanceThreshold` (5.0 miles)
  - Timer intervals: `closeUpdateInterval` (1.0s), `mediumUpdateInterval` (2.0s), `distantUpdateInterval` (5.0s)

- **New Methods**:
  - `updateUserLocation(_:)` - Updates user location and restarts timer with adaptive interval
  - `calculateOptimalUpdateInterval()` - Determines best interval based on closest aircraft distance
  - `restartAdaptiveTimer()` - Restarts timer with new adaptive interval
  - `adjustTimerIfNeeded()` - Checks if timer interval needs adjustment during updates

- **Enhanced Existing Methods**:
  - `updateFlightData(_:)` - Now calls `restartAdaptiveTimer()` when flight data changes
  - `startPredictionUpdates()` - Uses adaptive interval and includes timer adjustment check

#### 2. MainViewModel.swift
- **Enhanced user location integration**:
  - `updateBounds(_:)` - Now updates prediction service with new user location
  - Settings binding - Updates prediction service when geographic bounds change
  - Flight data updates - Ensures prediction service has current user location

## Benefits

### Performance Optimization
- **Reduced CPU Usage**: Distant aircraft (>5 miles) now update 5x less frequently
- **Intelligent Scaling**: Timer automatically adjusts as aircraft move closer or farther
- **Smooth Transitions**: Timer adjusts dynamically without interrupting predictions

### Maintained Accuracy
- **High Precision for Close Aircraft**: 1-second updates for aircraft within 2 miles
- **Balanced Performance**: 2-second updates for medium-distance aircraft
- **Sufficient Tracking**: 5-second updates still provide good tracking for distant aircraft

### Adaptive Behavior
- **Dynamic Adjustment**: Timer interval changes automatically based on closest aircraft
- **User Location Aware**: System responds to changes in user location
- **Flight Data Responsive**: Timer adjusts when new aircraft enter or leave the area

## Technical Implementation

### Distance Calculation
```swift
let flightLocation = CLLocation(latitude: position.latitude, longitude: position.longitude)
let distance = userLocation.distance(from: flightLocation) * 0.000621371 // Convert to miles
```

### Interval Selection Logic
```swift
if closestDistance < closeDistanceThreshold {
    return closeUpdateInterval  // 1 second
} else if closestDistance < mediumDistanceThreshold {
    return mediumUpdateInterval // 2 seconds
} else {
    return distantUpdateInterval // 5 seconds
}
```

### Timer Management
- Timer restarts only when optimal interval changes significantly (>0.1 second difference)
- Prevents unnecessary timer recreation for minor distance fluctuations
- Maintains smooth prediction updates during transitions

## Testing
- ✅ Code compiles successfully
- ✅ No breaking changes to existing functionality
- ✅ Maintains backward compatibility with existing prediction methods
- ✅ Integrates seamlessly with MainViewModel and user location updates

## Future Enhancements
- Could add configurable distance thresholds via settings
- Potential for even more granular intervals (e.g., very close < 0.5 miles)
- Option to disable adaptive timing for consistent intervals if needed