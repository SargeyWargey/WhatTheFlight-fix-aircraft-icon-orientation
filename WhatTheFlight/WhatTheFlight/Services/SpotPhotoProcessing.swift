//
//  SpotPhotoProcessing.swift
//  WhatTheFlight
//
//  What happens to a Sky View photo after the shutter: the full-resolution original goes to
//  the camera roll (add-only access, no album) with the flight written into its caption and
//  keywords so Photos search finds "N123DN" or "ATL"; the logbook keeps a 1600 px HEIC copy
//  (about 200–300 KB) that syncs through iCloud and backs the boarding-pass card.
//

#if os(iOS)
import Foundation
import CoreLocation
import ImageIO
import Photos
import UIKit
import UniformTypeIdentifiers

enum SpotPhotoProcessing {
    /// Long side of the logbook's copy, in pixels.
    static let logbookPixels = 1600

    /// The logbook's copy: upright, at most `logbookPixels` on the long side, HEIC (JPEG
    /// where HEIC can't be written). Metadata is left behind; the logbook has it all.
    static func logbookCopy(of data: Data, maxPixels: Int = logbookPixels) -> (data: Data, size: CGSize)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        guard let encoded = encode(image, type: .heic, quality: 0.7) ?? encode(image, type: .jpeg, quality: 0.8) else { return nil }
        return (encoded, CGSize(width: image.width, height: image.height))
    }

    static func encode(_ image: CGImage, type: UTType, quality: Double) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// A decoded image no bigger than `maxPixels`, for thumbnails and the card.
    static func image(from data: Data, maxPixels: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map(UIImage.init(cgImage:))
    }

    // MARK: Metadata

    /// "DAL1234 · Delta Air Lines · Airbus A321neo N123DN · ATL → JFK · 6.2 mi away at 34,000 ft"
    static func caption(for photo: SpotPhoto) -> String {
        var parts = [photo.displayIdentifier, photo.operatorName]
        parts.append([photo.typeName ?? photo.typeCode, photo.registration].compactMap { $0 }.joined(separator: " "))
        if let from = photo.originIATA, let to = photo.destinationIATA { parts.append("\(from) → \(to)") }
        parts.append("\(RadarFormat.miles(photo.distanceMiles)) mi away at \(RadarFormat.wholeNumber(photo.altitudeFeet)) ft")
        return parts.filter { !$0.isEmpty }.joined(separator: " · ") + " · What The Flight?"
    }

    static func keywords(for photo: SpotPhoto) -> [String] {
        var words = ["What The Flight", "aircraft", photo.displayIdentifier, photo.operatorName]
        words += [photo.callsign, photo.registration, photo.typeCode, photo.typeName, photo.originIATA, photo.destinationIATA,
                  photo.origin?.city, photo.destination?.city].compactMap { $0 }
        words += photo.tags.map(\.rawValue)
        var seen = Set<String>()
        return words.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    /// ImageIO dictionaries merged into the original's own metadata at capture.
    static func metadata(for photo: SpotPhoto, observer: CLLocation?) -> [String: Any] {
        let caption = caption(for: photo)
        var metadata: [String: Any] = [
            kCGImagePropertyIPTCDictionary as String: [
                kCGImagePropertyIPTCCaptionAbstract as String: caption,
                kCGImagePropertyIPTCObjectName as String: photo.displayIdentifier,
                kCGImagePropertyIPTCKeywords as String: keywords(for: photo),
            ],
            kCGImagePropertyTIFFDictionary as String: [
                kCGImagePropertyTIFFImageDescription as String: caption,
            ],
            kCGImagePropertyExifDictionary as String: [
                kCGImagePropertyExifUserComment as String: caption,
            ],
        ]
        if let observer { metadata[kCGImagePropertyGPSDictionary as String] = gps(observer) }
        return metadata
    }

    private static func gps(_ location: CLLocation) -> [String: Any] {
        let c = location.coordinate
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd"
        let date = formatter.string(from: location.timestamp)
        formatter.dateFormat = "HH:mm:ss.SS"
        let time = formatter.string(from: location.timestamp)
        var gps: [String: Any] = [
            kCGImagePropertyGPSLatitude as String: abs(c.latitude),
            kCGImagePropertyGPSLatitudeRef as String: c.latitude >= 0 ? "N" : "S",
            kCGImagePropertyGPSLongitude as String: abs(c.longitude),
            kCGImagePropertyGPSLongitudeRef as String: c.longitude >= 0 ? "E" : "W",
            kCGImagePropertyGPSDateStamp as String: date,
            kCGImagePropertyGPSTimeStamp as String: time,
        ]
        if location.verticalAccuracy >= 0 {
            gps[kCGImagePropertyGPSAltitude as String] = abs(location.altitude)
            gps[kCGImagePropertyGPSAltitudeRef as String] = location.altitude < 0 ? 1 : 0
        }
        if location.horizontalAccuracy >= 0 {
            gps[kCGImagePropertyGPSHPositioningError as String] = location.horizontalAccuracy
        }
        return gps
    }
}

/// Puts originals in the camera roll. Add-only access: the app never reads your library.
enum PhotoLibrarySaver {
    enum Outcome: Equatable { case saved, denied, failed }

    static func save(_ data: Data, location: CLLocation?, date: Date) async -> Outcome {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return .denied }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
                request.creationDate = date
                request.location = location
            }
            return .saved
        } catch {
            return .failed
        }
    }
}

#if targetEnvironment(simulator)
/// The simulator has no camera: a painted sky with a dot where each aircraft is, so the
/// whole photo flow (logbook, card, share) can be tried there.
enum SyntheticSkyPhoto {
    static func make(size: CGSize, dots: [CGPoint]) -> Data? {
        let renderer = UIGraphicsImageRenderer(size: size, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
        let image = renderer.image { context in
            let colors = [UIColor(red: 0.35, green: 0.58, blue: 0.86, alpha: 1).cgColor,
                          UIColor(red: 0.74, green: 0.85, blue: 0.95, alpha: 1).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
            UIColor(white: 0.15, alpha: 1).setFill()
            for dot in dots {
                let r = max(3, size.width / 300)
                context.cgContext.fillEllipse(in: CGRect(x: dot.x - r * 2, y: dot.y - r / 2, width: r * 4, height: r))
                context.cgContext.fillEllipse(in: CGRect(x: dot.x - r / 2, y: dot.y - r * 1.5, width: r, height: r * 3))
            }
        }
        return image.cgImage.flatMap { SpotPhotoProcessing.encode($0, type: .jpeg, quality: 0.9) }
    }
}
#endif
#endif
