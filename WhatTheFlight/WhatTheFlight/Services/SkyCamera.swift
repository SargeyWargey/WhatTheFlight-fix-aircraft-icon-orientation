//
//  SkyCamera.swift
//  WhatTheFlight
//
//  The back camera behind Sky View. It uses the multi-lens "virtual" camera, so one zoom
//  factor runs from the ultra-wide through the telephoto and iOS changes lenses itself;
//  `fieldOfView` always reports what the current zoom leaves on screen, which keeps the
//  labels on the aircraft. It also takes the photos (full resolution, flight details written
//  into the file's metadata) and watches frames for the tracked aircraft (`SkyFrameTracker`).
//

#if os(iOS)
import Foundation
import AVFoundation
import CoreMedia
import ImageIO
import Observation
import simd

@MainActor
@Observable
final class SkyCamera {
    enum State: Equatable { case idle, starting, running, denied, unavailable }

    private(set) var state: State = .idle
    /// The lenses, zoom range and stops. Nil until the camera is running.
    private(set) var zoom: CameraZoom?
    /// The device's zoom factor (1 = the widest lens), following ramps as they happen.
    private(set) var zoomFactor: Double = 1
    /// Sensor frame in pixels (long side, short side).
    private(set) var sensorSize = CGSize(width: 1920, height: 1080)
    /// The tracked aircraft, where the camera last saw it.
    private(set) var latestFix: VisualFix?

    /// Horizontal field of view of the sensor's long side at the current zoom, in degrees.
    var fieldOfView: Double { zoom?.fieldOfView(at: zoomFactor) ?? 0 }
    /// The number on the zoom chip ("5" for 5×).
    var displayZoom: Double { zoom?.displayZoom(for: zoomFactor) ?? 1 }

    @ObservationIgnored let session = AVCaptureSession()
    @ObservationIgnored private(set) var device: AVCaptureDevice?
    @ObservationIgnored let tracker = SkyFrameTracker()
    @ObservationIgnored private let photoOutput = AVCapturePhotoOutput()
    @ObservationIgnored private let videoOutput = AVCaptureVideoDataOutput()
    @ObservationIgnored private let queue = DispatchQueue(label: "wtf.skycamera")
    @ObservationIgnored private let frameQueue = DispatchQueue(label: "wtf.skycamera.frames", qos: .userInitiated)
    @ObservationIgnored private var zoomObservation: NSKeyValueObservation?
    @ObservationIgnored private var inFlight: [PhotoCaptureDelegate] = []
    @ObservationIgnored private var isConfigured = false

    init() {
        tracker.onFix = { [weak self] fix in
            Task { @MainActor in self?.latestFix = fix }
        }
    }

    /// Ultra-wide + wide + telephoto where there is one, down to the plain wide camera.
    static func bestBackCamera() -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
        for type in types {
            if let device = AVCaptureDevice.default(type, for: .video, position: .back) { return device }
        }
        return nil
    }

    func start() async {
        guard state == .idle || state == .denied else { return }
        // No camera (simulator, some iPads): don't ask for a permission we can't use.
        guard let device = device ?? Self.bestBackCamera() else {
            state = .unavailable
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { state = .denied; return }
        default:
            state = .denied
            return
        }
        state = .starting
        self.device = device
        if !isConfigured {
            guard let input = try? AVCaptureDeviceInput(device: device) else {
                state = .unavailable
                return
            }
            isConfigured = true
            let work = CaptureWork(session: session, input: input, photoOutput: photoOutput, videoOutput: videoOutput,
                                   tracker: tracker, frameQueue: frameQueue)
            await run { work.configure() }
        }
        let work = CaptureWork(session: session)
        await run { work.session.startRunning() }

        let format = device.activeFormat
        let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        sensorSize = CGSize(width: CGFloat(max(dims.width, dims.height)), height: CGFloat(min(dims.width, dims.height)))
        let lens = CameraZoom(baseFieldOfView: Double(format.videoFieldOfView),
                              displayMultiplier: Double(device.displayVideoZoomFactorMultiplier),
                              lensSwitchFactors: device.virtualDeviceSwitchOverVideoZoomFactors.map(\.doubleValue),
                              minFactor: Double(device.minAvailableVideoZoomFactor),
                              maxFactor: Double(device.maxAvailableVideoZoomFactor))
        zoom = lens
        observeZoom(device)
        // Open on the 1× lens, like the Camera app (and like Sky View before zoom).
        if abs(zoomFactor - 1) < 0.001 { setZoom(lens.standardFactor, animated: false) }
        state = session.isRunning ? .running : .unavailable
    }

    func stop() {
        let work = CaptureWork(session: session)
        queue.async { work.session.stopRunning() }
        if state == .running || state == .starting { state = .idle }
        latestFix = nil
    }

    /// Focal length in points for a preview that aspect-fills `size`.
    func focalLength(for size: CGSize) -> Double? {
        guard state == .running, fieldOfView > 1 else { return nil }
        let long = Double(sensorSize.width), short = Double(sensorSize.height)
        let viewLong = Double(max(size.width, size.height)), viewShort = Double(min(size.width, size.height))
        let fill = max(viewLong / long, viewShort / short)
        return (long / 2) / tan(fieldOfView.radians / 2) * fill
    }

    // MARK: Zoom

    /// Pinches set the factor directly; chip taps ramp to it like the Camera app.
    func setZoom(_ factor: Double, animated: Bool) {
        guard let device, let zoom else { return }
        let target = CGFloat(zoom.clamp(factor))
        let box = DeviceBox(device: device)
        queue.async {
            guard (try? box.device.lockForConfiguration()) != nil else { return }
            if animated {
                box.device.ramp(toVideoZoomFactor: target, withRate: 12)
            } else {
                box.device.cancelVideoZoomRamp()
                box.device.videoZoomFactor = target
            }
            box.device.unlockForConfiguration()
        }
        if !animated { zoomFactor = Double(target) }
        tracker.update(fieldOfView: zoom.fieldOfView(at: Double(target)))
    }

    private func observeZoom(_ device: AVCaptureDevice) {
        zoomObservation = device.observe(\.videoZoomFactor, options: [.initial, .new]) { [weak self] device, _ in
            let factor = Double(device.videoZoomFactor)
            Task { @MainActor in
                guard let self else { return }
                self.zoomFactor = factor
                self.tracker.update(fieldOfView: self.fieldOfView)
            }
        }
    }

    // MARK: Orientation

    /// The preview's rotation, which follows the interface. Photos and tracked frames use
    /// the same one, so "up" in them is "up" on screen and in `SkyProjector`.
    func setRotationAngle(_ angle: CGFloat) {
        let work = CaptureWork(session: session, photoOutput: photoOutput, videoOutput: videoOutput)
        queue.async {
            for connection in [work.photoOutput?.connection(with: .video), work.videoOutput?.connection(with: .video)] {
                if let connection, connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
            }
        }
    }

    // MARK: Photos

    struct CapturedPhoto {
        /// The full-resolution file (HEIC where supported), metadata included.
        let data: Data
        /// Field of view of the photo's long side, in degrees.
        let fieldOfView: Double
        let displayZoom: Double
    }

    /// Takes a photo; `metadata` (ImageIO property dictionaries: IPTC, GPS…) is merged into
    /// the file's own.
    func capturePhoto(metadata: [String: Any]) async -> CapturedPhoto? {
        guard state == .running else { return nil }
        let fieldOfView = fieldOfView, displayZoom = displayZoom
        let output = photoOutput
        let settings: AVCapturePhotoSettings
        if output.availablePhotoCodecTypes.contains(.hevc) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        } else {
            settings = AVCapturePhotoSettings()
        }
        settings.maxPhotoDimensions = output.maxPhotoDimensions
        settings.photoQualityPrioritization = .balanced
        let delegate = PhotoCaptureDelegate(metadata: metadata)
        inFlight.append(delegate)
        let data: Data? = await withCheckedContinuation { continuation in
            delegate.completion = { continuation.resume(returning: $0) }
            let work = CaptureWork(session: session, photoOutput: output)
            let request = PhotoRequest(settings: settings, delegate: delegate)
            queue.async { work.photoOutput?.capturePhoto(with: request.settings, delegate: request.delegate) }
        }
        inFlight.removeAll { $0 === delegate }
        return data.map { CapturedPhoto(data: $0, fieldOfView: fieldOfView, displayZoom: displayZoom) }
    }

    private func run(_ work: @escaping @Sendable () -> Void) async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            queue.async {
                work()
                done.resume()
            }
        }
    }
}

/// Carries the capture objects onto the camera's serial queue. AVFoundation's types aren't
/// Sendable, but Apple's guidance is exactly this: configure, start and stop the session on
/// one dedicated queue (it blocks), never on the main thread. Nothing else touches them
/// concurrently.
private struct CaptureWork: @unchecked Sendable {
    let session: AVCaptureSession
    var input: AVCaptureDeviceInput? = nil
    var photoOutput: AVCapturePhotoOutput? = nil
    var videoOutput: AVCaptureVideoDataOutput? = nil
    var tracker: SkyFrameTracker? = nil
    var frameQueue: DispatchQueue? = nil

    func configure() {
        session.beginConfiguration()
        session.sessionPreset = .high
        if let input, session.canAddInput(input) { session.addInput(input) }
        if let photoOutput, session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .balanced
            if let device = input?.device,
               let largest = device.activeFormat.supportedMaxPhotoDimensions.max(by: { $0.width * $0.height < $1.width * $1.height }) {
                photoOutput.maxPhotoDimensions = largest
            }
        }
        if let videoOutput, let tracker, let frameQueue, session.canAddOutput(videoOutput) {
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(tracker, queue: frameQueue)
            session.addOutput(videoOutput)
        }
        session.commitConfiguration()
    }
}

private struct DeviceBox: @unchecked Sendable { let device: AVCaptureDevice }

private struct PhotoRequest: @unchecked Sendable {
    let settings: AVCapturePhotoSettings
    let delegate: PhotoCaptureDelegate
}

/// One photo: hands back the file data with the flight details merged into its metadata.
private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, AVCapturePhotoFileDataRepresentationCustomizer, @unchecked Sendable {
    private let extra: [String: Any]
    var completion: ((Data?) -> Void)?

    init(metadata: [String: Any]) {
        extra = metadata
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        finish(error == nil ? photo.fileDataRepresentation(with: self) : nil)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        // Normally already finished above; this covers a capture that failed outright.
        finish(nil)
    }

    func replacementMetadata(for photo: AVCapturePhoto) -> [String: Any]? {
        var metadata = photo.metadata
        for (key, value) in extra {
            if let added = value as? [String: Any], let existing = metadata[key] as? [String: Any] {
                metadata[key] = existing.merging(added) { _, new in new }
            } else {
                metadata[key] = value
            }
        }
        return metadata
    }

    private func finish(_ data: Data?) {
        guard let completion else { return }
        self.completion = nil
        completion(data)
    }
}

// MARK: - Frame tracking

/// Looks for the tracked aircraft in camera frames, off the main actor: projects where it
/// should be, searches around that point for a dot (`SkyBlobDetector`), and reports a
/// `VisualFix` once two frames in a row agree.
final class SkyFrameTracker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    struct Target: Equatable, Sendable {
        let flightID: String
        /// Where the feed (plus the learned compass correction) puts it, east-north-up.
        let direction: SIMD3<Double>
    }

    var onFix: (@Sendable (VisualFix) -> Void)?

    private let lock = NSLock()
    private var basis: SkyBasis?
    private var fieldOfView: Double = 0
    private var target: Target?
    private var frameCount = 0
    private var candidate: (id: String, direction: SIMD3<Double>, time: Date)?

    func update(basis: SkyBasis) { lock.withLock { self.basis = basis } }
    func update(fieldOfView: Double) { lock.withLock { self.fieldOfView = fieldOfView } }
    func update(target: Target?) {
        lock.withLock {
            if target?.flightID != self.target?.flightID { candidate = nil }
            self.target = target
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let (basis, fieldOfView, target, frame) = lock.withLock { () -> (SkyBasis?, Double, Target?, Int) in
            frameCount += 1
            return (self.basis, self.fieldOfView, self.target, frameCount)
        }
        // Every other frame is plenty, and keeps the phone cool.
        guard frame % 2 == 0, let basis, let target, fieldOfView > 1,
              let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard CVPixelBufferGetPlaneCount(pixels) > 0,
              let base = CVPixelBufferGetBaseAddressOfPlane(pixels, 0) else { return }
        let width = CVPixelBufferGetWidthOfPlane(pixels, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixels, 0)
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixels, 0)

        let projector = SkyProjector(right: basis.right, up: basis.up, forward: basis.forward, focalLength: 1, size: .zero)
            .reframed(to: CGSize(width: width, height: height), longSideFieldOfView: fieldOfView)
        let predicted = projector.project(target.direction)
        guard predicted.isOnScreen(CGSize(width: width, height: height), margin: -8) else { return }
        let pixelsPerDegree = projector.focalLength * .pi / 180
        let radius = min(max(SkyCorrection.gate * 0.8 * pixelsPerDegree, 24), Double(min(width, height)) / 3)

        let luma = base.assumingMemoryBound(to: UInt8.self)
        guard let blob = SkyBlobDetector.detect(luma: luma, width: width, height: height, bytesPerRow: rowBytes,
                                                around: predicted.point, radius: radius) else { return }
        let seen = projector.unproject(blob.point)
        let now = Date()

        // Two frames in a row, close together, before trusting it: one-off specks (a bird,
        // a sensor flicker) don't make it through.
        let confirmed: Bool = lock.withLock {
            defer { candidate = (target.flightID, seen, now) }
            guard let last = candidate, last.id == target.flightID, now.timeIntervalSince(last.time) < 0.35 else { return false }
            let drift = acos(max(-1, min(1, simd_dot(last.direction, seen)))).degrees
            return drift < max(0.6, fieldOfView / 60)
        }
        if confirmed { onFix?(VisualFix(flightID: target.flightID, direction: seen, time: now)) }
    }
}
#endif
