//
//  FoldMonitor.swift
//  WhatTheFlight
//
//  iPhone Duo: watches the hinge (`UIHingeInteraction`) and where the screen folds
//  (`UIView.reservedRegions(kind: .division)`) and settles them into a `FoldPosture`
//  (`Core/FoldLayout.swift`). `RadarRootView` gives the radar and the map half the screen
//  each while the phone is half open. Other devices never report a hinge and stay `.none`.
//
//  The inner screen turns with the phone like an iPad's (iOS doesn't ask the app which
//  orientations it supports there), and it is mounted a quarter turn round from the phone's
//  body. `bodyInterfaceOrientation` undoes that for anything that measures from the body.
//

#if os(iOS)
import SwiftUI
import UIKit

@MainActor
@Observable
final class FoldMonitor {
    /// Settled: a half-open posture only counts once it has held for a moment, so unfolding
    /// straight to flat doesn't flash the split on the way past.
    private(set) var posture: FoldPosture = .none
    /// The fold strip in window coordinates (safe areas included); nil off the inner screen.
    private(set) var division: CGRect?
    /// This phone folds (its hinge has reported), whichever screen the app is on now.
    private(set) var isFoldable = false

    /// On the inner screen, which has the fold (open flat or half open).
    var isOnInnerScreen: Bool { division != nil }

    /// The hinge has reported once: until then changes land at once, so a Duo launched half
    /// open starts split instead of animating into it.
    @ObservationIgnored private var isSettled = false
    @ObservationIgnored private var pending: FoldPosture?
    @ObservationIgnored private var settleTask: Task<Void, Never>?
    #if DEBUG
    /// `-wtf.debugFold book|tabletop|flat` holds a posture, for screenshots without moving
    /// the simulator's hinge.
    @ObservationIgnored private let forced = UserDefaults.standard.string(forKey: "wtf.debugFold")
        .flatMap(FoldPosture.init(rawValue:))
    #endif

    static let settleDelay: Duration = .milliseconds(350)

    fileprivate func report(hinge: HingeStatus?, division: CGRect?) {
        if hinge != nil, !isFoldable { isFoldable = true }
        if division != self.division { self.division = division }
        var next = FoldLayout.posture(hinge: hinge, division: division)
        #if DEBUG
        if let forced {
            isFoldable = true
            next = forced
        }
        #endif
        settle(on: next)
        if hinge != nil { isSettled = true }
    }

    private func settle(on next: FoldPosture) {
        guard next != posture else {
            pending = nil
            settleTask?.cancel()
            return
        }
        // Leaving the split (flat, or folded shut) and the hinge's first report happen at
        // once; so does book ↔ tabletop, which only changes on a rotation anyway.
        guard isSettled, next.isHalfOpen, !posture.isHalfOpen else {
            commit(next)
            return
        }
        guard pending != next else { return }
        pending = next
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled, let self, self.pending == next else { return }
            self.commit(next)
        }
    }

    private func commit(_ next: FoldPosture) {
        pending = nil
        settleTask?.cancel()
        withAnimation(isSettled ? .smooth(duration: 0.45) : nil) { posture = next }
    }
}

/// Reads the hinge and the fold strip. Put it behind the root view, full screen
/// (`.ignoresSafeArea()`).
struct FoldSensor: UIViewRepresentable {
    let monitor: FoldMonitor

    func makeUIView(context: Context) -> SensorView { SensorView(monitor: monitor) }
    func updateUIView(_ uiView: SensorView, context: Context) {}

    final class SensorView: UIView {
        private let monitor: FoldMonitor
        private var hinge: HingeStatus?

        init(monitor: FoldMonitor) {
            self.monitor = monitor
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            if #available(iOS 27.1, *) {
                addInteraction(UIHingeInteraction { [weak self] _, update in
                    guard let self else { return }
                    // nil: the view left a hierarchy that has a hinge.
                    hinge = update.hinge.map { HingeStatus($0.status) }
                    report()
                })
            }
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            report()
        }

        // The strip moves when the screen turns or the app changes screens; both lay out again.
        override func layoutSubviews() {
            super.layoutSubviews()
            report()
        }

        private func report() {
            guard window != nil else { return }
            monitor.report(hinge: hinge, division: foldDivision.map { convert($0, to: nil) })
        }
    }
}

extension UIView {
    /// The fold strip in this view's coordinates, flat or half open; nil on a screen
    /// without one.
    var foldDivision: CGRect? {
        guard #available(iOS 27.1, *) else { return nil }
        return reservedRegions(kind: .division, options: .includeInactive).first?.frame
    }
}

extension UIWindowScene {
    /// The interface orientation measured against the phone's body, which is what Core
    /// Motion and the compass measure from. The same as `effectiveGeometry`'s everywhere but
    /// the Duo's inner screen, which reports landscape while the phone is held upright.
    var bodyInterfaceOrientation: UIInterfaceOrientation {
        let screen = effectiveGeometry.interfaceOrientation
        guard let turn = ScreenTurn(screen) else { return screen }
        let onInnerScreen = (keyWindow ?? windows.first)?.foldDivision != nil
        return UIInterfaceOrientation(FoldLayout.bodyTurn(screenTurn: turn, onInnerScreen: onInnerScreen))
    }
}

private extension ScreenTurn {
    init?(_ orientation: UIInterfaceOrientation) {
        switch orientation {
        case .portrait: self = .portrait
        case .landscapeLeft: self = .landscapeLeft
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeRight: self = .landscapeRight
        default: return nil
        }
    }
}

private extension UIInterfaceOrientation {
    init(_ turn: ScreenTurn) {
        switch turn {
        case .portrait: self = .portrait
        case .landscapeLeft: self = .landscapeLeft
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeRight: self = .landscapeRight
        }
    }
}

@available(iOS 27.1, *)
private extension HingeStatus {
    init(_ status: UIHinge.Status) {
        switch status {
        case .closed: self = .closed
        case .partiallyOpen: self = .partiallyOpen
        case .fullyOpen: self = .fullyOpen
        default: self = .unknown
        }
    }
}

extension EnvironmentValues {
    /// This iPhone folds (iPhone Duo): settings show the map rows.
    @Entry var isFoldable = false
}
#endif
