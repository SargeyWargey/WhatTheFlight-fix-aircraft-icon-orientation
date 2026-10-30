//
//  RecapVideo.swift
//  WhatTheFlight
//
//  A recap's story cards as a video to share: each card held a few seconds while it slowly
//  pushes in, then a cross-fade into the next. 1080 × 1920 H.264 at 30 fps, no sound.
//  Frames are composed with Core Image on the GPU, so six cards take a second or two.
//

#if os(iOS)
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

enum RecapVideo {
    static let secondsPerCard = 3.0
    /// The last part of each card's time, while the next one fades in over it.
    static let fadeSeconds = 0.6
    static let framesPerSecond = 30
    /// How much bigger a card has grown by the time the next has faded in.
    static let pushIn = 0.03

    enum Failure: Error { case noCards, writer }

    /// Writes the cards (all one size, opaque) to `<tmp>/Recap/<name>.mp4`, replacing any
    /// earlier one, and returns its URL. `progress` hears 0…1 now and then.
    static func make(cards: [CGImage], name: String, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> URL {
        guard let first = cards.first else { throw Failure.noCards }
        let width = first.width, height = first.height
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Recap", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name).appendingPathExtension("mp4")
        try? FileManager.default.removeItem(at: url)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            // About 13 MB for six cards: small enough for Messages, sharp enough for text.
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000],
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? Failure.writer }
        writer.startSession(atSourceTime: .zero)

        let images = cards.map { CIImage(cgImage: $0) }
        let extent = CGRect(x: 0, y: 0, width: width, height: height)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let context = CIContext(options: [.workingColorSpace: space])
        let total = Int((Double(cards.count) * secondsPerCard * Double(framesPerSecond)).rounded())
        do {
            for frame in 0..<total {
                try Task.checkCancellation()
                while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
                var buffer: CVPixelBuffer?
                if let pool = adaptor.pixelBufferPool { CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) }
                guard let buffer else { throw writer.error ?? Failure.writer }
                let image = compose(images, at: Double(frame) / Double(framesPerSecond), extent: extent)
                context.render(image, to: buffer, bounds: extent, colorSpace: space)
                guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(framesPerSecond))) else {
                    throw writer.error ?? Failure.writer
                }
                if frame % 15 == 0 || frame == total - 1 { progress(Double(frame + 1) / Double(total)) }
            }
        } catch {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? Failure.writer }
        return url
    }

    /// The frame `t` seconds in: card `i` from `i × secondsPerCard`, with card `i + 1`
    /// dissolving in over its last `fadeSeconds`.
    private static func compose(_ cards: [CIImage], at t: Double, extent: CGRect) -> CIImage {
        let index = min(cards.count - 1, Int(t / secondsPerCard))
        let current = pushed(cards[index], number: index, at: t, extent: extent)
        let intoNext = t - (Double(index + 1) * secondsPerCard - fadeSeconds)
        guard index + 1 < cards.count, intoNext > 0 else { return current }
        let dissolve = CIFilter.dissolveTransition()
        dissolve.inputImage = current
        dissolve.targetImage = pushed(cards[index + 1], number: index + 1, at: t, extent: extent)
        dissolve.time = Float(smooth(intoNext / fadeSeconds))
        return dissolve.outputImage?.cropped(to: extent) ?? current
    }

    /// Card `number` grown about its centre by how far through its time on screen `t` is
    /// (fading in included), cropped back to the frame.
    private static func pushed(_ card: CIImage, number: Int, at t: Double, extent: CGRect) -> CIImage {
        let shown = (t - (Double(number) * secondsPerCard - fadeSeconds)) / (secondsPerCard + fadeSeconds)
        let scale = 1 + pushIn * smooth(shown)
        let transform = CGAffineTransform(translationX: extent.midX, y: extent.midY)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -extent.midX, y: -extent.midY)
        return card.transformed(by: transform).cropped(to: extent)
    }

    /// Ease in and out, clamped to 0…1.
    private static func smooth(_ x: Double) -> Double {
        let x = min(1, max(0, x))
        return x * x * (3 - 2 * x)
    }

    /// The system share sheet over whatever is on screen, for a file made after the tap
    /// (a `ShareLink` needs its items up front). On iPad it points at the top-right corner,
    /// where the Share button is.
    @MainActor
    static func presentShareSheet(for url: URL) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first,
              var top = scene.keyWindow?.rootViewController else { return }
        while let presented = top.presentedViewController, !presented.isBeingDismissed { top = presented }
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.maxX - 44, y: top.view.safeAreaInsets.top + 22, width: 1, height: 1)
            popover.permittedArrowDirections = .up
        }
        top.present(sheet, animated: true)
    }
}
#endif
