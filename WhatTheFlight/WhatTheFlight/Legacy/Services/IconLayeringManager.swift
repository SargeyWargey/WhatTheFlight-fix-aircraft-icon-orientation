// Legacy: only the macOS (and visionOS) app runs this. iOS, tvOS and watchOS run radar v2;
// see Enhancements Spec B4. Delete with the rest of Legacy/ once the Mac runs the iPad app (C11).
#if os(macOS) || os(visionOS)
//
//  IconLayeringManager.swift
//  WhatTheFlight
//
//  Created by Kiro on 8/3/25.
//

import SwiftUI
import CoreLocation

/// Represents layering information for an aircraft icon
struct AircraftIconLayer {
    let flight: FlightData
    let position: CGPoint
    let distance: Double
    let isFocused: Bool
    let zIndex: Int
    let opacity: Double
    let proximityThreshold: Double
}

/// Manages the layering and opacity of overlapping aircraft icons
class IconLayeringManager: ObservableObject {
    
    /// Icon size for overlap detection (approximate size of aircraft icons)
    private let iconSize: CGSize = CGSize(width: 24, height: 24)
    
    /// Calculate layering information for all aircraft icons
    func calculateLayering(
        flights: [FlightData],
        positions: [String: CGPoint],
        distances: [String: Double],
        focusedFlightId: String?,
        proximityThreshold: Double
    ) -> [AircraftIconLayer] {
        
        // Create initial layer data
        var layers: [AircraftIconLayer] = []
        
        for flight in flights {
            guard let position = positions[flight.id],
                  let distance = distances[flight.id] else { continue }
            
            let isFocused = flight.id == focusedFlightId
            
            layers.append(AircraftIconLayer(
                flight: flight,
                position: position,
                distance: distance,
                isFocused: isFocused,
                zIndex: 0, // Will be calculated
                opacity: 1.0, // Will be calculated
                proximityThreshold: proximityThreshold
            ))
        }
        
        // Calculate overlaps and assign z-index and opacity
        return calculateOverlapsAndLayering(layers: layers)
    }
    
    /// Calculate overlaps and assign appropriate z-index and opacity values
    private func calculateOverlapsAndLayering(layers: [AircraftIconLayer]) -> [AircraftIconLayer] {
        var updatedLayers: [AircraftIconLayer] = []
        
        for (index, layer) in layers.enumerated() {
            let overlappingLayers = findOverlappingLayers(for: layer, in: layers, excluding: index)
            
            var zIndex: Int
            var opacity: Double = 1.0
            
            if layer.isFocused {
                // Focused aircraft always on top
                zIndex = 1000
            } else if overlappingLayers.isEmpty {
                // No overlaps, standard z-index
                zIndex = 100
            } else {
                // Has overlaps, calculate priority based on distance and focus
                let allOverlapping = overlappingLayers + [layer]
                let sortedByPriority = sortByPriority(layers: allOverlapping)
                
                if let priorityIndex = sortedByPriority.firstIndex(where: { $0.flight.id == layer.flight.id }) {
                    zIndex = 200 - priorityIndex // Higher priority = higher z-index
                    
                    // Set opacity to 70% if not the top layer
                    if priorityIndex > 0 {
                        opacity = 0.3
                    }
                } else {
                    zIndex = 100
                }
            }
            
            updatedLayers.append(AircraftIconLayer(
                flight: layer.flight,
                position: layer.position,
                distance: layer.distance,
                isFocused: layer.isFocused,
                zIndex: zIndex,
                opacity: opacity,
                proximityThreshold: layer.proximityThreshold
            ))
        }
        
        return updatedLayers
    }
    
    /// Find all layers that overlap with the given layer
    private func findOverlappingLayers(
        for targetLayer: AircraftIconLayer,
        in allLayers: [AircraftIconLayer],
        excluding excludeIndex: Int
    ) -> [AircraftIconLayer] {
        
        let targetRect = CGRect(
            x: targetLayer.position.x - iconSize.width / 2,
            y: targetLayer.position.y - iconSize.height / 2,
            width: iconSize.width,
            height: iconSize.height
        )
        
        var overlapping: [AircraftIconLayer] = []
        
        for (index, layer) in allLayers.enumerated() {
            if index == excludeIndex { continue }
            
            let layerRect = CGRect(
                x: layer.position.x - iconSize.width / 2,
                y: layer.position.y - iconSize.height / 2,
                width: iconSize.width,
                height: iconSize.height
            )
            
            if targetRect.intersects(layerRect) {
                overlapping.append(layer)
            }
        }
        
        return overlapping
    }
    
    /// Sort layers by priority: focused first, then by distance (closest first)
    private func sortByPriority(layers: [AircraftIconLayer]) -> [AircraftIconLayer] {
        return layers.sorted { layer1, layer2 in
            // Focused aircraft always has highest priority
            if layer1.isFocused && !layer2.isFocused {
                return true
            }
            if !layer1.isFocused && layer2.isFocused {
                return false
            }
            
            // If both focused or both not focused, sort by distance (closest first)
            return layer1.distance < layer2.distance
        }
    }
}
#endif
