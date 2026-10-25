//
//  SkyView.swift
//  WhatTheFlight
//
//  Hold the phone up to the sky: the camera feed with every aircraft labelled where it
//  really is, a horizon and compass ticks, and arrows at the edges for anything off-screen.
//  Aim the reticle at a label to lock on; tap the card for details. Labels are plain text
//  (no boxes) and the locked aircraft has none at all — its details sit in the card at the
//  bottom — so nothing covers the real aircraft in the camera view. Without motion sensors
//  (simulator) the view can be dragged around instead.
//
//  Zoom: pinch or tap a lens chip (0.5× / 1× / 2× / 5×…). Positions are dead-reckoned every
//  frame, and when the camera spots the locked aircraft as a dot against the sky the marker
//  snaps onto it and the compass error it reveals shifts every other label too
//  (`SkyCorrection`). The shutter photographs whatever is in the frame and files the photo
//  under the aircraft in the logbook (`SpotPhoto`), with a boarding-pass card to share.
//

#if os(iOS)
import SwiftUI
import AVFoundation
import CoreLocation
import UIKit
import simd

struct SkyRequest: Identifiable, Equatable {
    let id = UUID()
    /// Find mode: guide the user to this aircraft.
    var targetID: String?
    /// Opened by lifting the phone, so lowering it again closes it.
    var byRaise = false
}

struct SkyView: View {
    let model: RadarModel
    let settings: RadarSettings
    let location: RadarLocationService
    let request: SkyRequest
    let onClose: () -> Void
    let onDetail: (String) -> Void

    @LazyState private var motion = SkyMotion()
    @LazyState private var camera = SkyCamera()
    @State private var dragAzimuth: Double?
    @State private var dragPitch = 25.0
    @State private var dragStart: (az: Double, pitch: Double)?
    @State private var pinchStart: Double?
    @State private var loweredSince: Date?
    @State private var lockedID: String?
    @State private var correction = SkyCorrection()
    @State private var viewSize: CGSize = .zero
    @State private var capture: SkyCapture?
    @State private var showsCapture = false
    @State private var isCapturing = false
    @State private var flash = false
    @State private var shutterCount = 0
    @State private var toast: String?
    /// After a photo, lowering the phone to look at it shouldn't close Sky View.
    @State private var keepOpen = false

    @Environment(\.scenePhase) private var scenePhase

    struct Target: Identifiable {
        let contact: RadarContact
        let elevation: Double
        /// Where the feed (plus the compass correction) puts it, east-north-up.
        let direction: SIMD3<Double>
        let projection: SkyProjector.Projection
        /// The marker is on the dot the camera found, not the prediction.
        let isVisual: Bool
        var id: String { contact.id }
    }

    /// Everything on screen at one instant.
    private struct Frame {
        let projector: SkyProjector
        let targets: [Target]
        let onScreen: [Target]
        let locked: Target?
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: scenePhase != .active)) { timeline in
            GeometryReader { geo in
                let frame = makeFrame(size: geo.size, at: timeline.date)
                ZStack {
                    background
                    SkyGrid(projector: frame.projector)
                        .allowsHitTesting(false)

                    ForEach(frame.onScreen) { target in
                        SkyMarker(isLocked: target.id == frame.locked?.id, isVisual: target.isVisual,
                                  notable: target.contact.profile.notable.first?.tag)
                            .position(target.projection.point)
                            .allowsHitTesting(false)
                    }

                    ForEach(placedLabels(frame.onScreen, size: geo.size, locked: frame.locked), id: \.target.id) { item in
                        SkyLabel(contact: item.target.contact, isGoal: item.target.id == request.targetID)
                            .position(item.labelCenter)
                            .onTapGesture { onDetail(item.target.id) }
                    }

                    ForEach(placedArrows(frame.targets.filter { !$0.projection.isOnScreen(geo.size, margin: -20) }, size: geo.size), id: \.target.id) { item in
                        EdgeArrow(contact: item.target.contact, angle: item.target.projection.screenAngle,
                                  isGoal: item.target.id == request.targetID)
                            .position(item.labelCenter)
                            .opacity(request.targetID == nil || item.target.id == request.targetID ? 1 : 0.55)
                    }

                    Reticle(isLocked: frame.locked != nil)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        .allowsHitTesting(false)

                    Color.white
                        .opacity(flash ? 0.55 : 0)
                        .allowsHitTesting(false)

                    chrome(frame, size: geo.size)
                }
                .contentShape(Rectangle())
                .gesture(dragGesture(size: geo.size), including: motion.isAvailable ? .subviews : .all)
                .simultaneousGesture(pinchGesture)
                .onChange(of: frame.locked?.id) { _, id in lockedID = id }
                .onChange(of: trackingKey(frame)) { _, _ in updateTracking(frame) }
                .onChange(of: geo.size, initial: true) { _, size in viewSize = size }
            }
        }
        .ignoresSafeArea()
        .background(Color.black)
        .statusBarHidden()
        .sensoryFeedback(.selection, trigger: lockedID) { _, new in settings.hapticsEnabled && new != nil }
        .sensoryFeedback(.impact(weight: .medium), trigger: shutterCount) { _, _ in settings.hapticsEnabled }
        .onChange(of: motion.basis?.forward.z) { _, z in closeIfLowered(z) }
        .onChange(of: camera.latestFix) { _, fix in learn(from: fix) }
        .onAppear {
            motion.interfaceOrientation = currentInterfaceOrientation
            let tracker = camera.tracker
            motion.onBasis = { tracker.update(basis: $0) }
            motion.start()
            if dragAzimuth == nil { dragAzimuth = location.normalizedHeading }
            #if DEBUG
            // `-wtf.debugCapture YES` takes a photo shortly after opening; `-wtf.debugAim YES`
            // only aims, leaving the locked card on screen (screenshots).
            let capture = UserDefaults.standard.bool(forKey: "wtf.debugCapture")
            if capture || UserDefaults.standard.bool(forKey: "wtf.debugAim") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    // Without motion sensors, aim at the nearest aircraft first.
                    if motion.basis == nil, let nearest = model.contacts.first {
                        dragAzimuth = nearest.bearing
                        dragPitch = GeoMath.elevationDegrees(groundDistanceMiles: nearest.distanceMiles,
                                                             altitudeFeet: Double(nearest.altitudeFeet),
                                                             observerAltitudeFeet: 0)
                    }
                    if capture { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { takePhoto() } }
                }
            }
            #endif
        }
        .task { await camera.start() }
        .onDisappear {
            motion.stop()
            camera.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            motion.interfaceOrientation = currentInterfaceOrientation
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { camera.stop() } else { Task { await camera.start() } }
        }
        .sheet(isPresented: $showsCapture) {
            if let capture {
                NavigationStack {
                    SpotPhotoView(photo: capture.photo, store: capture.store,
                                  alternatives: capture.alternatives.map(\.photo),
                                  notLoggedReason: capture.notLoggedReason,
                                  onReassign: { reassign(to: $0) },
                                  onDelete: deleteCapture)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showsCapture = false }
                            }
                        }
                }
                .presentationDetents([.large])
            }
        }
    }

    // MARK: Building blocks

    @ViewBuilder
    private var background: some View {
        if camera.state == .running {
            SkyCameraPreview(session: camera.session, device: camera.device) { angle in camera.setRotationAngle(angle) }
        } else {
            LinearGradient(colors: [Color(red: 0.05, green: 0.08, blue: 0.2), Color(red: 0.22, green: 0.33, blue: 0.55)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    private func makeFrame(size: CGSize, at date: Date) -> Frame {
        let projector = makeProjector(size: size)
        let targets = makeTargets(projector, at: date)
        let onScreen = targets.filter { $0.projection.isOnScreen(size, margin: -20) }
        return Frame(projector: projector, targets: targets, onScreen: onScreen, locked: lockedTarget(onScreen, size: size))
    }

    private func makeProjector(size: CGSize) -> SkyProjector {
        let focal = camera.focalLength(for: size) ?? SkyProjector.focalLength(fieldOfView: 62, across: Double(min(size.width, size.height)))
        if let basis = motion.basis {
            return SkyProjector(right: basis.right, up: basis.up, forward: basis.forward, focalLength: focal, size: size)
        }
        return SkyProjector(azimuth: dragAzimuth ?? location.normalizedHeading, pitch: dragPitch, focalLength: focal, size: size)
    }

    /// Every aircraft worth showing, dead-reckoned to `date` (the model only moves them once
    /// a second, which shows as jumps when zoomed in).
    private func makeTargets(_ projector: SkyProjector, at date: Date) -> [Target] {
        let observerFeet = (location.location?.altitude ?? 0) * 3.28084
        let reach = settings.radiusMiles * 1.5
        let pool = model.contacts + model.outsideContacts.filter { $0.distanceMiles <= reach || $0.id == request.targetID }
        let fix = camera.latestFix.flatMap { $0.isFresh(at: date) ? $0 : nil }
        return pool.map { pooled in
            let contact = model.observer.map { RadarContact(flight: pooled.flight, observer: $0, at: date, profile: pooled.profile) } ?? pooled
            let elevation = GeoMath.elevationDegrees(groundDistanceMiles: contact.distanceMiles,
                                                     altitudeFeet: Double(contact.altitudeFeet),
                                                     observerAltitudeFeet: observerFeet)
            let direction = SkyProjector.direction(azimuth: correction.azimuth(contact.bearing), elevation: elevation)
            let seen = fix?.flightID == contact.id ? fix : nil
            return Target(contact: contact, elevation: elevation, direction: direction,
                          projection: projector.project(seen?.direction ?? direction), isVisual: seen != nil)
        }
    }

    /// The on-screen aircraft closest to the reticle, if it's close enough to count as aimed at.
    private func lockedTarget(_ onScreen: [Target], size: CGSize) -> Target? {
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        func d(_ t: Target) -> CGFloat { hypot(t.projection.point.x - centre.x, t.projection.point.y - centre.y) }
        guard let best = onScreen.min(by: { d($0) < d($1) }), d(best) < 90 else { return nil }
        return best
    }

    private struct Placed {
        let target: Target
        let labelCenter: CGPoint
    }

    /// Puts each label just above its aircraft, nudging upward to avoid overlaps, nearest
    /// first. The locked aircraft gets no label (the bottom card has its details) and the
    /// sky around it is kept clear, so you can see the real thing inside the ring.
    private func placedLabels(_ onScreen: [Target], size: CGSize, locked: Target?) -> [Placed] {
        let ordered = onScreen
            .filter { $0.id != locked?.id }
            .sorted { $0.contact.distanceMiles < $1.contact.distanceMiles }
        var taken: [CGRect] = []
        if let locked {
            let p = locked.projection.point
            taken.append(CGRect(x: p.x - 45, y: p.y - 45, width: 90, height: 90))
        }
        var result: [Placed] = []
        let labelSize = CGSize(width: 130, height: 40)
        for target in ordered.prefix(14) {
            var center = CGPoint(x: target.projection.point.x, y: target.projection.point.y - 46)
            for _ in 0..<5 {
                let rect = CGRect(x: center.x - labelSize.width / 2, y: center.y - labelSize.height / 2, width: labelSize.width, height: labelSize.height)
                if !taken.contains(where: { $0.intersects(rect) }) { break }
                center.y -= labelSize.height + 4
            }
            center.x = min(max(center.x, labelSize.width / 2 + 8), size.width - labelSize.width / 2 - 8)
            taken.append(CGRect(x: center.x - labelSize.width / 2, y: center.y - labelSize.height / 2, width: labelSize.width, height: labelSize.height))
            result.append(Placed(target: target, labelCenter: center))
        }
        return result
    }

    /// Edge arrows for the nearest off-screen aircraft (the goal always included), dropping
    /// any that would sit on top of one already placed.
    private func placedArrows(_ offScreen: [Target], size: CGSize) -> [Placed] {
        let ordered = offScreen.sorted {
            if $0.id == request.targetID { return true }
            if $1.id == request.targetID { return false }
            return $0.contact.distanceMiles < $1.contact.distanceMiles
        }
        var result: [Placed] = []
        for target in ordered where result.count < 8 {
            let point = edgePoint(angle: target.projection.screenAngle, size: size)
            if target.id != request.targetID, result.contains(where: { hypot($0.labelCenter.x - point.x, $0.labelCenter.y - point.y) < 54 }) { continue }
            result.append(Placed(target: target, labelCenter: point))
        }
        return result
    }

    /// Where a ray from the centre meets the usable frame: clear of the header up top and
    /// the locked-on card and camera controls at the bottom.
    private func edgePoint(angle: Double, size: CGSize) -> CGPoint {
        let frame = CGRect(x: 40, y: 200, width: size.width - 80, height: size.height - 200 - 250)
        let cx = Double(frame.midX), cy = Double(frame.midY)
        let dx = sin(angle), dy = -cos(angle)
        let halfW = Double(frame.width / 2), halfH = Double(frame.height / 2)
        let t = min(abs(dx) > 1e-6 ? halfW / abs(dx) : .infinity, abs(dy) > 1e-6 ? halfH / abs(dy) : .infinity)
        return CGPoint(x: cx + dx * t, y: cy + dy * t)
    }

    // MARK: Visual lock-on

    /// The aircraft the camera should look for: the one you're finding, else the one in the
    /// reticle.
    private func trackedTarget(_ frame: Frame) -> Target? {
        if let goal = request.targetID, let target = frame.onScreen.first(where: { $0.id == goal }) { return target }
        return frame.locked
    }

    /// Changes when the tracked aircraft or its predicted direction moves noticeably.
    private func trackingKey(_ frame: Frame) -> String {
        guard let target = trackedTarget(frame) else { return "" }
        let d = target.direction * 2000
        return "\(target.id) \(Int(d.x)) \(Int(d.y)) \(Int(d.z))"
    }

    private func updateTracking(_ frame: Frame) {
        camera.tracker.update(target: trackedTarget(frame).map { SkyFrameTracker.Target(flightID: $0.id, direction: $0.direction) })
    }

    /// Learns the compass error from where the camera saw the aircraft vs. the prediction.
    private func learn(from fix: VisualFix?) {
        guard let fix, let observer = model.observer,
              let pooled = (model.contacts + model.outsideContacts).first(where: { $0.id == fix.flightID }) else { return }
        let contact = RadarContact(flight: pooled.flight, observer: observer, at: fix.time, profile: pooled.profile)
        let elevation = GeoMath.elevationDegrees(groundDistanceMiles: contact.distanceMiles,
                                                 altitudeFeet: Double(contact.altitudeFeet),
                                                 observerAltitudeFeet: (location.location?.altitude ?? 0) * 3.28084)
        let predicted = SkyProjector.direction(azimuth: correction.azimuth(contact.bearing), elevation: elevation)
        correction.observe(predicted: predicted, observed: fix.direction)
    }

    // MARK: Chrome

    @ViewBuilder
    private func chrome(_ frame: Frame, size: CGSize) -> some View {
        let projector = frame.projector, locked = frame.locked, targets = frame.targets
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .glassSurface(in: Circle(), interactive: true)
                }
                .accessibilityLabel("Close Sky View")
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(Int(projector.lookAzimuth.rounded()) % 360)° \(GeoMath.cardinal(projector.lookAzimuth))  ·  \(Int(projector.lookElevation.rounded()))° up")
                        .font(.mono(13, .bold))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    Text(statusText(locked: locked))
                        .font(.mono(10))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassSurface(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.horizontal, 16)
            .padding(.top, 58)

            if let goalID = request.targetID, let goal = targets.first(where: { $0.id == goalID }), locked?.id != goalID {
                Text(findHint(goal, projector: projector))
                    .font(.mono(13, .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Palette.signal.opacity(0.85), in: Capsule())
                    .padding(.top, 12)
            }

            if let toast {
                Text(toast)
                    .font(.mono(12, .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassSurface(in: Capsule())
                    .padding(.top, 12)
                    .transition(.opacity)
            }

            Spacer()

            if let locked {
                LockedCard(contact: locked.contact, elevation: locked.elevation, isVisual: locked.isVisual,
                           showsPhoto: settings.showPhotos) { onDetail(locked.id) }
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Text(targets.isEmpty ? "Nothing in range right now" : "Aim the circle at an aircraft")
                    .font(.mono(12, .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassSurface(in: Capsule())
            }

            cameraControls
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 34)
        }
        .animation(.snappy, value: locked?.id)
        .animation(.snappy, value: toast)
    }

    /// Last photo · lens chips · shutter.
    private var cameraControls: some View {
        HStack(alignment: .center) {
            Button { if capture != nil { showsCapture = true } } label: {
                ZStack {
                    if let thumbnail = capture?.thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.white.opacity(0.08)
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.white.opacity(0.7), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .opacity(capture == nil ? 0 : 1)
            .disabled(capture == nil)
            .accessibilityLabel("Last photo")

            Spacer(minLength: 8)
            ZoomChips(camera: camera)
            Spacer(minLength: 8)

            Button(action: takePhoto) {
                ZStack {
                    Circle().stroke(.white, lineWidth: 4).frame(width: 66, height: 66)
                    Circle().fill(.white).frame(width: 54, height: 54)
                        .scaleEffect(isCapturing ? 0.85 : 1)
                }
                .shadow(color: .black.opacity(0.35), radius: 3)
            }
            .buttonStyle(.plain)
            .disabled(!canTakePhoto || isCapturing)
            .opacity(canTakePhoto ? 1 : 0.35)
            .accessibilityLabel("Take photo")
            .accessibilityHint("Photographs the aircraft in view and adds it to your logbook")
        }
    }

    private var canTakePhoto: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return camera.state == .running
        #endif
    }

    private func statusText(locked: Target?) -> String {
        if !motion.isAvailable { return "No motion sensors · drag to look around" }
        switch camera.state {
        case .denied: return "Camera off · labels only"
        case .unavailable: return "No camera · labels only"
        default:
            if locked?.isVisual == true { return "Locked on by camera" }
            if correction.observations > 0 { return "Compass corrected \(Int(abs(correction.yaw).rounded()))°" }
            return motion.usesTrueNorth ? "Positions are approximate" : "Magnetic north · approximate"
        }
    }

    private func findHint(_ goal: Target, projector: SkyProjector) -> String {
        let turn = GeoMath.shortestDelta(from: projector.lookAzimuth, to: correction.azimuth(goal.contact.bearing))
        let tilt = goal.elevation - projector.lookElevation
        let name = goal.contact.flight.displayIdentifier
        if abs(turn) > 20 { return "\(name): turn \(turn > 0 ? "right" : "left") \(Int(abs(turn).rounded()))°" }
        if abs(tilt) > 10 { return "\(name): tilt \(tilt > 0 ? "up" : "down") \(Int(abs(tilt).rounded()))°" }
        return "\(name) is right there"
    }

    private func show(_ message: String) {
        toast = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { if toast == message { toast = nil } }
    }

    // MARK: Photos

    /// Photographs the frame and files it under the aircraft in it: the locked one (or the
    /// one you're finding), else whichever is nearest the centre.
    private func takePhoto() {
        guard !isCapturing, viewSize.width > 0 else { return }
        let date = Date()
        let frame = makeFrame(size: viewSize, at: date)
        let centre = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
        let inShot = frame.onScreen.sorted {
            hypot($0.projection.point.x - centre.x, $0.projection.point.y - centre.y)
                < hypot($1.projection.point.x - centre.x, $1.projection.point.y - centre.y)
        }
        let subject = trackedTarget(frame) ?? inShot.first
        guard let subject else {
            show("Aim at an aircraft to photograph it")
            return
        }
        isCapturing = true
        keepOpen = true
        shutterCount += 1
        withAnimation(.easeOut(duration: 0.08)) { flash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { withAnimation(.easeIn(duration: 0.25)) { flash = false } }

        let ordered = [subject] + inShot.filter { $0.id != subject.id }.prefix(5)
        let observer = model.observer
        let placeName = (settings.locationMode == .custom ? settings.customPlaceName : nil) ?? model.logPlaceName
        let observerLocation = location.location
        let projector = frame.projector
        let zoom = camera.displayZoom
        func spot(_ target: Target, point: CGPoint?, width: Int, height: Int) -> SpotPhoto {
            SpotPhoto(contact: target.contact, takenAt: date, device: .current, elevationDegrees: target.elevation,
                      observer: observer, placeName: placeName, displayZoom: zoom, framePoint: point,
                      visuallyLocked: target.isVisual, pixelWidth: width, pixelHeight: height)
        }
        let metadata = SpotPhotoProcessing.metadata(for: spot(subject, point: nil, width: 0, height: 0), observer: observerLocation)

        Task {
            defer { isCapturing = false }
            guard let shot = await shoot(metadata: metadata, frame: frame, targets: ordered) else {
                show("Couldn't take the photo")
                return
            }
            guard let copy = await Task.detached(priority: .userInitiated, operation: { SpotPhotoProcessing.logbookCopy(of: shot.data) }).value else {
                show("Couldn't save the photo")
                return
            }
            // Where each aircraft sits in the photo: the same camera, reframed to the photo.
            let photoProjector = shot.fieldOfView.map { projector.reframed(to: copy.size, longSideFieldOfView: $0) }
            let candidates = ordered.map { target -> SkyCapture.Candidate in
                let point: CGPoint?
                if let photoProjector {
                    // A camera-found aircraft is where its marker was; the rest where predicted.
                    let direction = target.isVisual ? projector.unproject(target.projection.point) : target.direction
                    let seen = photoProjector.project(direction)
                    point = seen.isOnScreen(copy.size) ? CGPoint(x: seen.point.x / copy.size.width, y: seen.point.y / copy.size.height) : nil
                } else {
                    let p = target.projection.point
                    point = CGRect(origin: .zero, size: viewSize).contains(p) ? CGPoint(x: p.x / viewSize.width, y: p.y / viewSize.height) : nil
                }
                return SkyCapture.Candidate(photo: spot(target, point: point, width: Int(copy.size.width), height: Int(copy.size.height)),
                                            contact: target.contact)
            }
            guard let first = candidates.first else { return }

            if settings.skySaveToPhotos, shot.isReal {
                let outcome = await PhotoLibrarySaver.save(shot.data, location: observerLocation, date: date)
                if outcome == .denied { show("Allow adding to Photos in Settings to keep originals") }
            }

            let logbook = model.logbook
            var reason: String?
            if !model.isLogging || logbook == nil {
                reason = settings.demoTraffic ? "Demo traffic isn't logged, but you can still share the card."
                    : settings.locationMode == .custom ? "Photos from a custom spot aren't logged, but you can still share the card."
                    : "The logbook is off, so this photo isn't kept in the app."
            } else if logbook?.addPhoto(first.photo, imageData: copy.data, contact: first.contact,
                                        observer: observer, placeName: placeName) != true {
                reason = "Couldn't add it to the logbook."
            }
            let store = reason == nil ? (logbook?.photoStore ?? SpotPhotoStore(directory: nil)) : SpotPhotoStore(directory: nil)
            if reason != nil { try? store.write(copy.data, id: first.photo.id) }
            capture = SkyCapture(photo: first.photo, subject: first, alternatives: Array(candidates.dropFirst()),
                                 imageData: copy.data, store: store, isLogged: reason == nil, notLoggedReason: reason,
                                 thumbnail: SpotPhotoImages.decode(copy.data, maxPixels: 160))
            if reason == nil { show("Saved to your logbook · tap the photo for its boarding pass") }
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "wtf.debugCapture") { showsCapture = true }
            #endif
        }
    }

    private struct Shot {
        let data: Data
        /// Field of view of the photo's long side; nil for a synthetic shot framed like the screen.
        let fieldOfView: Double?
        let isReal: Bool
    }

    private func shoot(metadata: [String: Any], frame: Frame, targets: [Target]) async -> Shot? {
        if camera.state == .running, let photo = await camera.capturePhoto(metadata: metadata) {
            return Shot(data: photo.data, fieldOfView: photo.fieldOfView, isReal: true)
        }
        #if targetEnvironment(simulator)
        let scale: CGFloat = 3
        let size = CGSize(width: viewSize.width * scale, height: viewSize.height * scale)
        let dots = targets.map { CGPoint(x: $0.projection.point.x * scale, y: $0.projection.point.y * scale) }
        return SyntheticSkyPhoto.make(size: size, dots: dots).map { Shot(data: $0, fieldOfView: nil, isReal: false) }
        #else
        return nil
        #endif
    }

    /// "Wrong aircraft?": credit the same shot to another aircraft that was in it.
    private func reassign(to other: SpotPhoto) {
        guard var current = capture, let candidate = current.alternatives.first(where: { $0.photo.id == other.id }) else { return }
        let replacement = current.photo.reassigned(to: candidate.photo)
        if current.isLogged, let logbook = model.logbook {
            logbook.removePhoto(id: current.photo.id)
            logbook.addPhoto(replacement, imageData: current.imageData, contact: candidate.contact,
                             observer: model.observer, placeName: replacement.placeName)
        } else {
            try? current.store.write(current.imageData, id: replacement.id)
        }
        current.alternatives = current.alternatives.filter { $0.photo.id != other.id } + [current.subject]
        current.subject = SkyCapture.Candidate(photo: replacement, contact: candidate.contact)
        current.photo = replacement
        capture = current
    }

    private func deleteCapture() {
        guard let current = capture else { return }
        if current.isLogged { model.logbook?.removePhoto(id: current.photo.id) }
        capture = nil
    }

    // MARK: Gestures & lifecycle

    private func dragGesture(size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let start = dragStart ?? (dragAzimuth ?? 0, dragPitch)
                dragStart = start
                let degreesPerPoint = 62 / Double(min(size.width, size.height))
                dragAzimuth = GeoMath.normalize(start.az - Double(value.translation.width) * degreesPerPoint)
                dragPitch = min(85, max(-20, start.pitch + Double(value.translation.height) * degreesPerPoint))
            }
            .onEnded { _ in dragStart = nil }
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = pinchStart ?? camera.zoomFactor
                pinchStart = start
                camera.setZoom(start * Double(value.magnification), animated: false)
            }
            .onEnded { _ in pinchStart = nil }
    }

    /// Opened by lifting the phone: lowering it to look at the screen closes it again
    /// (unless you've just taken a photo, or are looking at one).
    private func closeIfLowered(_ forwardZ: Double?) {
        guard request.byRaise, !keepOpen, !showsCapture, let forwardZ else { return }
        if forwardZ < -0.6 {
            let since = loweredSince ?? Date()
            loweredSince = since
            if Date().timeIntervalSince(since) > 0.8 { onClose() }
        } else {
            loweredSince = nil
        }
    }

    /// Against the phone's body, which is what Core Motion measures from (the iPhone Duo's
    /// inner screen reports a quarter turn round from it).
    private var currentInterfaceOrientation: UIInterfaceOrientation {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.bodyInterfaceOrientation ?? .portrait
    }
}

/// The last photo taken in this Sky View session, and the other aircraft in the same shot.
private struct SkyCapture {
    struct Candidate {
        let photo: SpotPhoto
        let contact: RadarContact
    }

    var photo: SpotPhoto
    var subject: Candidate
    var alternatives: [Candidate]
    let imageData: Data
    let store: SpotPhotoStore
    let isLogged: Bool
    let notLoggedReason: String?
    let thumbnail: UIImage?
}

/// 0.5× · 1× · 2× · 5×, Camera-app style: the active lens shows the exact zoom.
private struct ZoomChips: View {
    let camera: SkyCamera

    var body: some View {
        if let zoom = camera.zoom, zoom.stops.count > 1 {
            let active = zoom.nearestStop(to: camera.zoomFactor)
            HStack(spacing: 6) {
                ForEach(zoom.stops, id: \.self) { stop in
                    let isActive = stop == active
                    let shown = isActive ? camera.displayZoom : zoom.displayZoom(for: stop)
                    Button { camera.setZoom(stop, animated: true) } label: {
                        Text(CameraZoom.label(shown) + (isActive ? "×" : ""))
                            .font(.mono(isActive ? 13 : 11, .bold))
                            .foregroundStyle(isActive ? Palette.warning : .white)
                            .frame(width: isActive ? 40 : 32, height: isActive ? 40 : 32)
                            .background(.black.opacity(0.45), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Zoom \(CameraZoom.label(zoom.displayZoom(for: stop))) times")
                }
            }
            .padding(5)
            .glassSurface(in: Capsule())
            .animation(.snappy, value: active)
        }
    }
}

// MARK: - Pieces

/// Horizon line plus compass ticks every 15°, labelled at the cardinal points.
private struct SkyGrid: View {
    let projector: SkyProjector

    var body: some View {
        Canvas { context, size in
            var horizon = Path()
            var started = false
            for az in stride(from: 0.0, through: 360, by: 3) {
                let p = projector.project(azimuth: az, elevation: 0)
                guard p.isInFront, abs(p.point.x) < size.width * 3, abs(p.point.y) < size.height * 3 else { started = false; continue }
                if started { horizon.addLine(to: p.point) } else { horizon.move(to: p.point); started = true }
            }
            context.stroke(horizon, with: .color(.white.opacity(0.55)), style: StrokeStyle(lineWidth: 1.5, dash: [6, 6]))

            for az in stride(from: 0.0, to: 360, by: 15) {
                let p = projector.project(azimuth: az, elevation: 0)
                guard p.isOnScreen(size, margin: 20) else { continue }
                let major = az.truncatingRemainder(dividingBy: 45) == 0
                var tick = Path()
                tick.move(to: CGPoint(x: p.point.x, y: p.point.y - (major ? 10 : 5)))
                tick.addLine(to: CGPoint(x: p.point.x, y: p.point.y + (major ? 10 : 5)))
                context.stroke(tick, with: .color(.white.opacity(major ? 0.9 : 0.5)), lineWidth: major ? 2 : 1)
                if major {
                    let label = GeoMath.cardinal(az)
                    context.draw(Text(label).font(.mono(15, .heavy)).foregroundStyle(label == "N" ? Palette.signal : .white),
                                 at: CGPoint(x: p.point.x, y: p.point.y + 24))
                }
            }
        }
    }
}

/// A ring on each aircraft; corner brackets instead once the camera has found the real dot.
private struct SkyMarker: View {
    let isLocked: Bool
    var isVisual = false
    let notable: NotableTag?

    var body: some View {
        let color = isLocked ? Palette.signal : (notable.map(Palette.color(for:)) ?? .white)
        let size: CGFloat = isLocked ? 30 : 20
        Group {
            if isVisual {
                Brackets()
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: size + 6, height: size + 6)
            } else {
                Circle()
                    .stroke(color, lineWidth: isLocked ? 3 : 2)
                    .frame(width: size, height: size)
            }
        }
        .shadow(color: .black.opacity(0.5), radius: 2)
        .animation(.snappy, value: isLocked)
        .animation(.snappy, value: isVisual)
    }

    private struct Brackets: Shape {
        func path(in rect: CGRect) -> Path {
            let arm = rect.width * 0.3
            var p = Path()
            for (corner, dx, dy) in [(CGPoint(x: rect.minX, y: rect.minY), 1.0, 1.0), (CGPoint(x: rect.maxX, y: rect.minY), -1.0, 1.0),
                                     (CGPoint(x: rect.minX, y: rect.maxY), 1.0, -1.0), (CGPoint(x: rect.maxX, y: rect.maxY), -1.0, -1.0)] {
                p.move(to: CGPoint(x: corner.x + arm * dx, y: corner.y))
                p.addLine(to: corner)
                p.addLine(to: CGPoint(x: corner.x, y: corner.y + arm * dy))
            }
            return p
        }
    }
}

/// Callsign plus type and distance as shadowed text: readable over sky and cloud without a
/// box that could hide the aircraft itself.
private struct SkyLabel: View {
    let contact: RadarContact
    let isGoal: Bool

    var body: some View {
        let f = contact.flight
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                if let tag = f.notable.first?.tag {
                    Image(systemName: tag.symbol).font(.system(size: 9, weight: .heavy)).foregroundStyle(Palette.color(for: tag))
                }
                Text(f.displayIdentifier).font(.mono(13, .heavy))
            }
            Text("\(f.typeCode ?? "—") · \(RadarFormat.miles(contact.distanceMiles)) mi")
                .font(.mono(10, .semibold))
                .opacity(0.85)
        }
        .foregroundStyle(isGoal ? Palette.signal : .white)
        .shadow(color: .black.opacity(0.85), radius: 1.5)
        .shadow(color: .black.opacity(0.5), radius: 4)
        .padding(4)
        .contentShape(Rectangle())
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

private struct EdgeArrow: View {
    let contact: RadarContact
    let angle: Double
    let isGoal: Bool

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "arrowtriangle.up.fill")
                .font(.system(size: isGoal ? 26 : 14, weight: .bold))
                .rotationEffect(.radians(angle))
            Text(contact.flight.displayIdentifier)
                .font(.mono(isGoal ? 13 : 10, .bold))
                .fixedSize()
        }
        .foregroundStyle(isGoal ? Palette.signal : .white)
        .shadow(color: .black.opacity(0.6), radius: 2)
        .accessibilityLabel("\(contact.flight.displayIdentifier) is off screen")
    }
}

private struct Reticle: View {
    let isLocked: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(isLocked ? Palette.signal : .white.opacity(0.8), lineWidth: isLocked ? 3 : 1.5)
                .frame(width: isLocked ? 64 : 80, height: isLocked ? 64 : 80)
            ForEach(0..<4) { i in
                Capsule()
                    .fill(isLocked ? Palette.signal : .white.opacity(0.8))
                    .frame(width: 2, height: 10)
                    .offset(y: -(isLocked ? 40 : 48))
                    .rotationEffect(.degrees(Double(i) * 90))
            }
        }
        .shadow(color: .black.opacity(0.4), radius: 2)
        .animation(.snappy, value: isLocked)
    }
}

/// The locked aircraft: who, where it's going, how high and far, and its photo on the right.
/// Tap for details.
private struct LockedCard: View {
    let contact: RadarContact
    let elevation: Double
    var isVisual = false
    var showsPhoto = true
    let onTap: () -> Void

    var body: some View {
        let f = contact.flight
        Button(action: onTap) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(f.operatorInfo.compact)
                            .monoScaled(10, .semibold)
                            .textCase(.uppercase)
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                        if isVisual {
                            Label("Locked", systemImage: "scope")
                                .monoScaled(9, .heavy)
                                .textCase(.uppercase)
                                .foregroundStyle(Palette.warning)
                                .labelStyle(.titleAndIcon)
                        }
                    }
                    HStack(spacing: 8) {
                        Text(f.displayIdentifier).monoScaled(24, .heavy)
                        if f.hasRoute {
                            Text("\(f.originIATA ?? "") → \(f.destinationIATA ?? "")")
                                .monoScaled(14, .bold)
                                .foregroundStyle(Palette.route)
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    Text([f.typeName ?? f.typeCode, "\(RadarFormat.wholeNumber(contact.altitudeFeet)) ft"].compactMap { $0 }.joined(separator: " · "))
                        .monoScaled(11)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text("\(RadarFormat.miles(contact.distanceMiles)) mi away · \(Int(elevation.rounded()))° up · \(RadarFormat.wholeNumber(f.groundSpeedKnots)) kts")
                        .monoScaled(11)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .padding(8)
                Spacer(minLength: 0)
                // As tall as the text beside it and about as wide as a Planespotters photo
                // (3:2) at that height, so the whole aircraft shows, nose to tail. Inset as far
                // from the card's edge as its corners are rounded less, so the curves run parallel.
                if showsPhoto {
                    AircraftPhotoTile(registration: f.registration, hex: f.hex, width: 142, gap: 4)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(.white)
            .padding(8)
            .glassSurface(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows flight details")
    }
}

/// The live back-camera feed, kept level with the interface as the device rotates.
/// `onAngle` passes each rotation on, so photos and tracked frames turn the same way.
private struct SkyCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let device: AVCaptureDevice?
    var onAngle: (CGFloat) -> Void = { _ in }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        var coordinator: AVCaptureDevice.RotationCoordinator?
        var observation: NSKeyValueObservation?
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        if let device {
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: view.previewLayer)
            view.coordinator = coordinator
            view.previewLayer.connection?.videoRotationAngle = coordinator.videoRotationAngleForHorizonLevelPreview
            onAngle(coordinator.videoRotationAngleForHorizonLevelPreview)
            let onAngle = onAngle
            view.observation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) { [weak view] c, _ in
                let angle = c.videoRotationAngleForHorizonLevelPreview
                DispatchQueue.main.async {
                    view?.previewLayer.connection?.videoRotationAngle = angle
                    onAngle(angle)
                }
            }
        }
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
#endif
