# Perimeter Miles Indicator Formatting Update

## Overview
Updated the miles indicators on the perimeter of the screen to display whole numbers (no decimal places) while keeping decimal places in the main display area for more precise readings.

## Changes Made

### 1. Perimeter Aircraft Distance Label
- **Location**: `PerimeterAircraftView` in `FlightDisplayView.swift`
- **Change**: Updated from `"%.1f"` to `"%.0f"` format
- **Effect**: Perimeter aircraft now show distance as whole numbers (e.g., "5" instead of "5.2")

### 2. Compact Layout Distance Indicators
Updated all compact/perimeter distance text components to use whole numbers:

#### CountdownDistanceText
- **Purpose**: Compact distance display for small layouts
- **Change**: Format changed from `"%.1f"` to `"%.0f"`

#### PredictiveCountdownDistanceText  
- **Purpose**: Predictive compact distance display using aircraft predictions
- **Change**: Format changed from `"%.1f"` to `"%.0f"`

#### PredictiveNearestApproachText
- **Purpose**: Predictive compact nearest approach display
- **Change**: Format changed from `"%.1f"` to `"%.0f"`

### 3. Main Display Area (Unchanged)
The following components retain decimal places for precise readings:

#### CountdownDistanceView
- **Purpose**: Main display distance with "Distance" label
- **Format**: Still uses `"%.1f"` (e.g., "5.2 mi")

#### PredictiveCountdownDistanceView
- **Purpose**: Main display predictive distance
- **Format**: Still uses `"%.1f"` (e.g., "5.2 mi")

#### PredictiveNearestApproachView
- **Purpose**: Main display nearest approach
- **Format**: Still uses `"%.1f"` (e.g., "2.8 mi")

## User Experience Impact

### Benefits
- **Cleaner Perimeter Display**: Whole numbers reduce visual clutter around screen edges
- **Easier Quick Reading**: Simpler to glance at perimeter aircraft distances
- **Maintained Precision**: Main display area still provides precise decimal readings when needed
- **Consistent Design**: All perimeter/compact indicators now use consistent formatting

### Display Examples
- **Perimeter Aircraft**: Shows "5 mi" instead of "5.2 mi"
- **Main Display**: Still shows "5.2 mi" for precise readings
- **Compact Layout**: Shows "5" instead of "5.2" in tight spaces

## Technical Details
- All changes use standard Swift string formatting
- No functional logic changes, only display formatting
- Maintains backward compatibility
- Successfully builds and compiles

## Files Modified
- `WhatTheFlight/WhatTheFlight/Views/FlightDisplayView.swift`
  - Updated `PerimeterAircraftView` distance label formatting
  - Updated `CountdownDistanceText` formatting
  - Updated `PredictiveCountdownDistanceText` formatting  
  - Updated `PredictiveNearestApproachText` formatting

The changes provide a cleaner, more readable interface while maintaining precision where it matters most.