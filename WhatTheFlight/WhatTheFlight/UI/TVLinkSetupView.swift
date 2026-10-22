//
//  TVLinkSetupView.swift
//  WhatTheFlight
//
//  iPhone: "Aim at your Apple TV". Hold the phone up so the camera sees the TV (or lay it
//  flat with the top pointing at the TV), press Send, and the Apple TV learns where it is
//  and which way it faces.
//

#if os(iOS)
import SwiftUI
import AVFoundation

struct TVLinkSetupView: View {
    let settings: RadarSettings
    let location: RadarLocationService

    @State private var compass = AimingCompass()
    @State private var link = TVLinkSender()
    @State private var selectedTV: TVLinkSender.FoundTV?
    @State private var includeDirection = true
    @State private var manualFacing: Double = 0
    @State private var cameraAllowed = false
    @State private var sentHeading: Double?

    private var liveFacing: Double? {
        compass.isAvailable ? compass.heading : manualFacing
    }

    private var sourceCoordinate: CLLocationCoordinate2D? {
        settings.locationMode == .custom ? (settings.customCoordinate ?? location.location?.coordinate) : location.location?.coordinate
    }

    var body: some View {
        ZStack {
            backdrop.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                reticle
                Spacer(minLength: 0)
                controlCard
            }
        }
        .navigationTitle("Aim at Apple TV")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            compass.start()
            link.startBrowsing()
            requestCamera()
        }
        .onDisappear {
            compass.stop()
            link.stop()
        }
        .onChange(of: link.tvs) { _, tvs in
            if selectedTV == nil || !tvs.contains(where: { $0 == selectedTV }) { selectedTV = tvs.first }
            #if DEBUG
            // `-wtf.debugAutoSend YES`: send as soon as a TV shows up (simulator end-to-end test).
            if UserDefaults.standard.bool(forKey: "wtf.debugAutoSend"), canSend { send() }
            #endif
        }
        .sensoryFeedback(.success, trigger: sentHeading)
    }

    // MARK: Pieces

    @ViewBuilder
    private var backdrop: some View {
        if cameraAllowed && compass.isAvailable {
            CameraPreview()
                .overlay(Color.black.opacity(0.15))
        } else {
            RadarBackdrop(showTopography: true, showSweep: false, isActive: true)
        }
    }

    private var reticle: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().stroke(.white.opacity(0.85), lineWidth: 2).frame(width: 170, height: 170)
                Circle().stroke(Palette.signal, lineWidth: 3).frame(width: 18, height: 18)
                ForEach(0..<4) { i in
                    Capsule().fill(.white).frame(width: 3, height: 26)
                        .offset(y: -98)
                        .rotationEffect(.degrees(Double(i) * 90))
                }
            }
            .shadow(color: .black.opacity(0.4), radius: 6)

            if let facing = liveFacing {
                VStack(spacing: 2) {
                    Text("\(Int(facing.rounded()) % 360)°")
                        .font(.mono(54, .heavy))
                        .contentTransition(.numericText(value: facing.rounded()))
                        .animation(.snappy, value: Int(facing.rounded()))
                    Text(GeoMath.cardinal(facing))
                        .font(.mono(18, .bold))
                        .tracking(3)
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 4)
            } else {
                Text("Hold steady…")
                    .font(.mono(16, .semibold))
                    .foregroundStyle(.white)
            }

            Text(instruction)
                .font(.mono(13, .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.black.opacity(0.45), in: Capsule())
        }
        .padding(.top, 20)
    }

    private var instruction: String {
        guard compass.isAvailable else { return "Motion sensors unavailable — pick the direction below" }
        return compass.isUpright
            ? "Center your TV in the circle"
            : "Point the top of your iPhone at the TV"
    }

    private var controlCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            tvRow
            Divider().overlay(Palette.faint.opacity(0.4))
            HStack {
                Label(sourceCoordinate?.shortDescription ?? "Waiting for your location…", systemImage: "location.fill")
                    .font(.mono(12, .semibold))
                    .foregroundStyle(Palette.value)
                    .lineLimit(1)
                Spacer()
            }
            Toggle(isOn: $includeDirection) {
                Text("Send TV direction").font(.mono(13, .semibold))
            }
            .tint(Palette.ink)

            if !compass.isAvailable && includeDirection {
                manualPicker
            }

            Button(action: send) {
                HStack(spacing: 8) {
                    if case .sending = link.phase { ProgressView().tint(.white) }
                    Text(sendTitle)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(RadarButtonStyle(prominent: true))
            .disabled(!canSend)
            .opacity(canSend ? 1 : 0.5)

            statusLine
        }
        .padding(18)
        .glassSurface(in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var tvRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "appletv.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Palette.ink)
            if link.tvs.isEmpty {
                Text("Looking for Apple TV…")
                    .font(.mono(13, .semibold))
                    .foregroundStyle(Palette.value)
                Spacer()
                ProgressView()
            } else if link.tvs.count == 1, let tv = link.tvs.first {
                Text(tv.title).font(.mono(13, .bold)).foregroundStyle(Palette.value)
                Spacer()
                Text("Match the code on your TV").font(.mono(10)).foregroundStyle(Palette.caption)
            } else {
                Picker("Apple TV", selection: $selectedTV) {
                    ForEach(link.tvs) { Text($0.title).tag(Optional($0)) }
                }
                .pickerStyle(.menu)
                .font(.mono(13, .bold))
                Spacer()
            }
        }
    }

    private var manualPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(stride(from: 0.0, to: 360, by: 45)), id: \.self) { degrees in
                    Button(GeoMath.cardinal(degrees)) { manualFacing = degrees }
                        .font(.mono(13, .bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .foregroundStyle(manualFacing == degrees ? .white : Palette.ink)
                        .background(manualFacing == degrees ? Palette.ink : Palette.ink.opacity(0.1), in: Capsule())
                }
            }
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch link.phase {
        case .sent:
            Label(sentSummary, systemImage: "checkmark.circle.fill")
                .font(.mono(12, .semibold))
                .foregroundStyle(Palette.live)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.mono(12, .semibold))
                .foregroundStyle(Palette.signal)
        default:
            Text("Open What The Flight? on your Apple TV. Both devices must be on the same Wi-Fi.")
                .font(.mono(11))
                .foregroundStyle(Palette.caption)
        }
    }

    private var sentSummary: String {
        if let heading = sentHeading, heading >= 0 {
            return "Sent — TV faces \(Int(heading.rounded()) % 360)° \(GeoMath.cardinal(heading))"
        }
        return "Location sent to Apple TV"
    }

    private var sendTitle: String {
        switch link.phase {
        case .sending: return "Sending…"
        case .sent: return "Send Again"
        default: return includeDirection ? "Send Location & Direction" : "Send Location"
        }
    }

    private var canSend: Bool {
        guard selectedTV != nil, sourceCoordinate != nil else { return false }
        if case .sending = link.phase { return false }
        return !includeDirection || liveFacing != nil
    }

    // MARK: Actions

    private func send() {
        guard let tv = selectedTV, let coordinate = sourceCoordinate else { return }
        let facing = includeDirection ? liveFacing : nil
        let payload = TVLink.Payload(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            facingDegrees: facing,
            senderName: UIDevice.current.name,
            sentAt: Date()
        )
        Task {
            await link.send(payload, to: tv)
            if case .sent = link.phase { sentHeading = facing ?? -1 }
        }
    }

    private func requestCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraAllowed = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { cameraAllowed = granted }
            }
        default:
            cameraAllowed = false
        }
    }
}

// MARK: - Camera

/// Live back-camera feed used as an aiming viewfinder.
struct CameraPreview: UIViewRepresentable {
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        let session = AVCaptureSession()

        func configure() {
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.session = session
            let session = self.session
            DispatchQueue.global(qos: .userInitiated).async {
                session.beginConfiguration()
                if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                   let input = try? AVCaptureDeviceInput(device: device),
                   session.canAddInput(input) {
                    session.addInput(input)
                }
                session.commitConfiguration()
                session.startRunning()
            }
        }

        deinit {
            let session = self.session
            DispatchQueue.global(qos: .utility).async { session.stopRunning() }
        }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.configure()
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
#endif
