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

#if os(iOS)
import SwiftUI
import AVFoundation
import UIKit

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

    @State private var motion = SkyMotion()
    @State private var camera = SkyCamera()
    @State private var dragAzimuth: Double?
    @State private var dragPitch = 25.0
    @State private var dragStart: (az: Double, pitch: Double)?
    @State private var loweredSince: Date?
    @State private var lockedID: String?

    @Environment(\.scenePhase) private var scenePhase

    private struct Target: Identifiable {
        let contact: RadarContact
        let elevation: Double
        let projection: SkyProjector.Projection
        var id: String { contact.id }
    }

    var body: some View {
        GeometryReader { geo in
            let projector = makeProjector(size: geo.size)
            let targets = makeTargets(projector)
            let onScreen = targets.filter { $0.projection.isOnScreen(geo.size, margin: -20) }
            let locked = lockedTarget(onScreen, size: geo.size)

            ZStack {
                background
                SkyGrid(projector: projector)
                    .allowsHitTesting(false)

                ForEach(onScreen) { target in
                    SkyMarker(isLocked: target.id == locked?.id, notable: target.contact.flight.notable.first?.tag)
                        .position(target.projection.point)
                        .allowsHitTesting(false)
                }

                ForEach(placedLabels(onScreen, size: geo.size, locked: locked), id: \.target.id) { item in
                    SkyLabel(contact: item.target.contact, isGoal: item.target.id == request.targetID)
                        .position(item.labelCenter)
                        .onTapGesture { onDetail(item.target.id) }
                }

                ForEach(placedArrows(targets.filter { !$0.projection.isOnScreen(geo.size, margin: -20) }, size: geo.size), id: \.target.id) { item in
                    EdgeArrow(contact: item.target.contact, angle: item.target.projection.screenAngle,
                              isGoal: item.target.id == request.targetID)
                        .position(item.labelCenter)
                        .opacity(request.targetID == nil || item.target.id == request.targetID ? 1 : 0.55)
                }

                Reticle(isLocked: locked != nil)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    .allowsHitTesting(false)

                chrome(projector: projector, locked: locked, targets: targets, size: geo.size)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(size: geo.size), including: motion.isAvailable ? .subviews : .all)
            .onChange(of: locked?.id) { _, id in lockedID = id }
            .onChange(of: motion.basis?.forward.z) { _, z in closeIfLowered(z) }
        }
        .ignoresSafeArea()
        .background(Color.black)
        .statusBarHidden()
        .sensoryFeedback(.selection, trigger: lockedID) { _, new in settings.hapticsEnabled && new != nil }
        .onAppear {
            motion.interfaceOrientation = currentInterfaceOrientation
            motion.start()
            if dragAzimuth == nil { dragAzimuth = location.normalizedHeading }
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
    }

    // MARK: Building blocks

    @ViewBuilder
    private var background: some View {
        if camera.state == .running {
            SkyCameraPreview(session: camera.session, device: camera.device)
        } else {
            LinearGradient(colors: [Color(red: 0.05, green: 0.08, blue: 0.2), Color(red: 0.22, green: 0.33, blue: 0.55)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    private func makeProjector(size: CGSize) -> SkyProjector {
        let focal = camera.focalLength(for: size) ?? SkyProjector.focalLength(fieldOfView: 62, across: Double(min(size.width, size.height)))
        if let basis = motion.basis {
            return SkyProjector(right: basis.right, up: basis.up, forward: basis.forward, focalLength: focal, size: size)
        }
        return SkyProjector(azimuth: dragAzimuth ?? location.normalizedHeading, pitch: dragPitch, focalLength: focal, size: size)
    }

    private func makeTargets(_ projector: SkyProjector) -> [Target] {
        let observerFeet = (location.location?.altitude ?? 0) * 3.28084
        let reach = settings.radiusMiles * 1.5
        let pool = model.contacts + model.outsideContacts.filter { $0.distanceMiles <= reach || $0.id == request.targetID }
        return pool.map { contact in
            let elevation = GeoMath.elevationDegrees(groundDistanceMiles: contact.distanceMiles,
                                                     altitudeFeet: Double(contact.flight.altitudeFeet),
                                                     observerAltitudeFeet: observerFeet)
            return Target(contact: contact, elevation: elevation, projection: projector.project(azimuth: contact.bearing, elevation: elevation))
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
    /// the locked-on card at the bottom.
    private func edgePoint(angle: Double, size: CGSize) -> CGPoint {
        let frame = CGRect(x: 40, y: 200, width: size.width - 80, height: size.height - 200 - 170)
        let cx = Double(frame.midX), cy = Double(frame.midY)
        let dx = sin(angle), dy = -cos(angle)
        let halfW = Double(frame.width / 2), halfH = Double(frame.height / 2)
        let t = min(abs(dx) > 1e-6 ? halfW / abs(dx) : .infinity, abs(dy) > 1e-6 ? halfH / abs(dy) : .infinity)
        return CGPoint(x: cx + dx * t, y: cy + dy * t)
    }

    // MARK: Chrome

    @ViewBuilder
    private func chrome(projector: SkyProjector, locked: Target?, targets: [Target], size: CGSize) -> some View {
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
                    Text(statusText)
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

            Spacer()

            if let locked {
                LockedCard(contact: locked.contact, elevation: locked.elevation) { onDetail(locked.id) }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 44)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Text(targets.isEmpty ? "Nothing in range right now" : "Aim the circle at an aircraft")
                    .font(.mono(12, .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassSurface(in: Capsule())
                    .padding(.bottom, 50)
            }
        }
        .animation(.snappy, value: locked?.id)
    }

    private var statusText: String {
        if !motion.isAvailable { return "No motion sensors · drag to look around" }
        switch camera.state {
        case .denied: return "Camera off · labels only"
        case .unavailable: return "No camera · labels only"
        default: return motion.usesTrueNorth ? "Positions are approximate" : "Magnetic north · approximate"
        }
    }

    private func findHint(_ goal: Target, projector: SkyProjector) -> String {
        let turn = GeoMath.shortestDelta(from: projector.lookAzimuth, to: goal.contact.bearing)
        let tilt = goal.elevation - projector.lookElevation
        let name = goal.contact.flight.displayIdentifier
        if abs(turn) > 20 { return "\(name): turn \(turn > 0 ? "right" : "left") \(Int(abs(turn).rounded()))°" }
        if abs(tilt) > 10 { return "\(name): tilt \(tilt > 0 ? "up" : "down") \(Int(abs(tilt).rounded()))°" }
        return "\(name) is right there"
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

    /// Opened by lifting the phone: lowering it to look at the screen closes it again.
    private func closeIfLowered(_ forwardZ: Double?) {
        guard request.byRaise, let forwardZ else { return }
        if forwardZ < -0.6 {
            let since = loweredSince ?? Date()
            loweredSince = since
            if Date().timeIntervalSince(since) > 0.8 { onClose() }
        } else {
            loweredSince = nil
        }
    }

    private var currentInterfaceOrientation: UIInterfaceOrientation {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.effectiveGeometry.interfaceOrientation ?? .portrait
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

private struct SkyMarker: View {
    let isLocked: Bool
    let notable: NotableTag?

    var body: some View {
        Circle()
            .stroke(isLocked ? Palette.signal : (notable.map(Palette.color(for:)) ?? .white), lineWidth: isLocked ? 3 : 2)
            .frame(width: isLocked ? 30 : 20, height: isLocked ? 30 : 20)
            .shadow(color: .black.opacity(0.5), radius: 2)
            .animation(.snappy, value: isLocked)
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

private struct LockedCard: View {
    let contact: RadarContact
    let elevation: Double
    let onTap: () -> Void

    var body: some View {
        let f = contact.flight
        Button(action: onTap) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(f.operatorInfo.compact)
                        .font(.mono(10, .semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text(f.displayIdentifier).font(.mono(24, .heavy))
                        if f.hasRoute {
                            Text("\(f.originIATA ?? "") → \(f.destinationIATA ?? "")")
                                .font(.mono(14, .bold))
                                .foregroundStyle(Palette.route)
                        }
                    }
                    Text([f.typeName ?? f.typeCode, "\(RadarFormat.wholeNumber(f.altitudeFeet)) ft"].compactMap { $0 }.joined(separator: " · "))
                        .font(.mono(11))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                    Text("\(RadarFormat.miles(contact.distanceMiles)) mi away · \(Int(elevation.rounded()))° up · \(RadarFormat.wholeNumber(f.groundSpeedKnots)) kts")
                        .font(.mono(11))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .foregroundStyle(.white)
            .padding(16)
            .glassSurface(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows flight details")
    }
}

/// The live back-camera feed, kept level with the interface as the device rotates.
private struct SkyCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let device: AVCaptureDevice?

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
            view.observation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) { [weak view] c, _ in
                let angle = c.videoRotationAngleForHorizonLevelPreview
                DispatchQueue.main.async { view?.previewLayer.connection?.videoRotationAngle = angle }
            }
        }
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
#endif
