//
//  FoldLayout.swift
//  WhatTheFlight
//
//  iPhone Duo: how the phone is being held, and where the radar and the map go when it's
//  half open. Book (the fold runs top to bottom): radar on the left page, map on the right.
//  Tabletop (the fold runs across): radar on the half that stands up, map on the half lying
//  on the table. Open flat or folded shut, the radar has the screen to itself.
//
//  The system reports the fold as a reserved "division" strip: the crease plus a margin
//  either side that interactive content should stay out of. Measured on the Duo simulator,
//  inner screen held as a book (951 × 669 pt): x 455.5–495.5, a 20 pt margin each side of
//  the crease at 475.5. Each pane ends at the strip, so the halves are equal and nothing you
//  can tap sits on the crease.
//

import CoreGraphics

enum FoldPosture: String, Equatable, Sendable, CaseIterable {
    /// No fold on this screen: every other iPhone and iPad, or a Duo folded shut on its
    /// cover screen.
    case none
    /// Open flat: one big screen.
    case flat
    /// Half open, the fold running top to bottom, held like a book.
    case book
    /// Half open, the fold running across, standing on a table like a small laptop.
    case tabletop

    var isHalfOpen: Bool { self == .book || self == .tabletop }
}

/// `UIHinge.Status`, without UIKit.
enum HingeStatus: Equatable, Sendable {
    case unknown, closed, partiallyOpen, fullyOpen
}

/// Screen turns measured clockwise from portrait, in `UIInterfaceOrientation` terms.
enum ScreenTurn: Int, Equatable, Sendable, CaseIterable {
    case portrait = 0, landscapeLeft = 1, portraitUpsideDown = 2, landscapeRight = 3

    func turned(by quarterTurns: Int) -> ScreenTurn {
        ScreenTurn(rawValue: ((rawValue + quarterTurns) % 4 + 4) % 4)!
    }
}

enum FoldLayout {
    /// The margin either side of the crease when the system doesn't report one.
    static let fallbackMargin: CGFloat = 20
    /// A reported fold that would leave either half narrower than this is ignored, and the
    /// screen splits down the middle instead.
    static let minimumPane: CGFloat = 200

    /// The Duo's inner screen sits a quarter turn clockwise from the phone's body (measured
    /// on the simulator: held upright as a book, the device is portrait and the interface is
    /// landscapeLeft). Core Motion and the compass measure from the body, so anything that
    /// maps their axes onto the screen turns the interface back by this much.
    static let innerScreenQuarterTurns = 1

    /// `division` is the system's fold strip in the screen's coordinates, nil when this screen
    /// has none (the cover screen, or any other device). The strip runs along the fold, so
    /// its long side says how the phone is held.
    static func posture(hinge: HingeStatus?, division: CGRect?) -> FoldPosture {
        guard let hinge, let division else { return .none }
        switch hinge {
        case .unknown, .closed: return .none
        case .fullyOpen: return .flat
        case .partiallyOpen: return division.height >= division.width ? .book : .tabletop
        }
    }

    /// The interface orientation against the phone's body, from the one the screen reports.
    static func bodyTurn(screenTurn: ScreenTurn, onInnerScreen: Bool) -> ScreenTurn {
        onInnerScreen ? screenTurn.turned(by: -innerScreenQuarterTurns) : screenTurn
    }

    struct Split: Equatable {
        let posture: FoldPosture
        /// Left page (book) or the standing half (tabletop).
        let radar: CGRect
        /// Right page (book) or the half on the table (tabletop).
        let map: CGRect
        /// The strip over the fold between them.
        let gutter: CGRect
    }

    /// The two halves either side of the fold, in the same coordinates as `division` (the
    /// whole screen, safe areas included). Without a usable strip, the middle of the screen.
    static func split(_ posture: FoldPosture, size: CGSize, division: CGRect?) -> Split? {
        guard posture.isHalfOpen, size.width > 0, size.height > 0 else { return nil }
        let bounds = CGRect(origin: .zero, size: size)
        let alongWidth = posture == .book
        let length = alongWidth ? size.width : size.height

        var gutter: CGRect
        if let clipped = division?.intersection(bounds), !clipped.isNull,
           (alongWidth ? clipped.minX : clipped.minY) >= minimumPane,
           length - (alongWidth ? clipped.maxX : clipped.maxY) >= minimumPane {
            gutter = clipped
        } else {
            let middle = length / 2
            gutter = alongWidth
                ? CGRect(x: middle - fallbackMargin, y: 0, width: 2 * fallbackMargin, height: size.height)
                : CGRect(x: 0, y: middle - fallbackMargin, width: size.width, height: 2 * fallbackMargin)
        }
        // The strip runs the full length of the fold, whatever was reported.
        if alongWidth {
            gutter = CGRect(x: gutter.minX, y: 0, width: gutter.width, height: size.height)
            return Split(posture: posture,
                         radar: CGRect(x: 0, y: 0, width: gutter.minX, height: size.height),
                         map: CGRect(x: gutter.maxX, y: 0, width: size.width - gutter.maxX, height: size.height),
                         gutter: gutter)
        } else {
            gutter = CGRect(x: 0, y: gutter.minY, width: size.width, height: gutter.height)
            return Split(posture: posture,
                         radar: CGRect(x: 0, y: 0, width: size.width, height: gutter.minY),
                         map: CGRect(x: 0, y: gutter.maxY, width: size.width, height: size.height - gutter.maxY),
                         gutter: gutter)
        }
    }
}
