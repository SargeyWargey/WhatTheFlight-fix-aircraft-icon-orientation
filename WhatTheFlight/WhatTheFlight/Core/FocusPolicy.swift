//
//  FocusPolicy.swift
//  WhatTheFlight
//
//  Decides which aircraft owns the centre of the screen.
//
//  • First launch / nothing focused → the nearest aircraft.
//  • The focused aircraft stays put ("sticky") while it is inside the radius, even if
//    another one becomes closer.
//  • When it leaves the radius (or vanishes from the feed) the current nearest takes over.
//  • A pinned aircraft is kept while the feed still reports it, even outside the radius.
//  • Swipe right always jumps back to the current nearest.
//

import Foundation

struct RadarFocus: Equatable, Sendable {
    var focusedID: String?
    var isPinned: Bool = false
}

enum FocusChange: Equatable, Sendable {
    case none
    case initial
    /// The previous aircraft flew out of the radius.
    case leftRange(previous: String)
    /// The previous aircraft disappeared from the feed (landed, lost signal…).
    case lost(previous: String)
}

enum FocusPolicy {
    /// - Parameters:
    ///   - inRange: contacts inside the radius, sorted nearest first.
    ///   - available: IDs of every aircraft currently in the feed (in or out of range).
    static func resolve(_ state: RadarFocus, inRange: [RadarContact], available: Set<String>) -> (RadarFocus, FocusChange) {
        guard let current = state.focusedID else {
            guard let nearest = inRange.first else { return (state, .none) }
            return (RadarFocus(focusedID: nearest.id, isPinned: false), .initial)
        }
        if inRange.contains(where: { $0.id == current }) {
            return (state, .none)
        }
        if state.isPinned, available.contains(current) {
            return (state, .none)
        }
        let replacement = RadarFocus(focusedID: inRange.first?.id, isPinned: false)
        let change: FocusChange = available.contains(current) ? .leftRange(previous: current) : .lost(previous: current)
        return (replacement, change)
    }

    static func nearest(_ inRange: [RadarContact]) -> RadarFocus {
        RadarFocus(focusedID: inRange.first?.id, isPinned: false)
    }

    /// The next aircraft farther out than the current one, wrapping to the nearest.
    static func next(after state: RadarFocus, inRange: [RadarContact]) -> RadarFocus {
        guard !inRange.isEmpty else { return state }
        guard let current = state.focusedID,
              let index = inRange.firstIndex(where: { $0.id == current }) else {
            return nearest(inRange)
        }
        return RadarFocus(focusedID: inRange[(index + 1) % inRange.count].id, isPinned: false)
    }

    /// The next aircraft closer in than the current one. Stops at the nearest (no wrap),
    /// so holding ◀ on the remote always lands on the closest aircraft.
    static func previous(before state: RadarFocus, inRange: [RadarContact]) -> RadarFocus {
        guard !inRange.isEmpty else { return state }
        guard let current = state.focusedID,
              let index = inRange.firstIndex(where: { $0.id == current }) else {
            return nearest(inRange)
        }
        return RadarFocus(focusedID: inRange[max(0, index - 1)].id, isPinned: false)
    }
}
