//
//  ProviderPhoto.swift
//  WhatTheFlight
//
//  A Planespotters photo loaded through `AircraftPhotoProvider`, whose session carries the
//  descriptive User-Agent their terms ask for and a disk cache. Decoded off the main thread
//  and kept in memory, so reopening a flight shows its photo at once.
//

#if os(iOS) || os(tvOS)
import SwiftUI
import UIKit

extension EnvironmentValues {
    /// The "Aircraft photos" setting, for screens that don't hold the settings (the logbook).
    @Entry var showsAircraftPhotos = true
}

struct ProviderPhoto<Placeholder: View>: View {
    let photo: AircraftPhoto
    /// Shown while loading, and if the image can't be fetched.
    let placeholder: () -> Placeholder

    @State private var image: UIImage?

    init(photo: AircraftPhoto, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.photo = photo
        self.placeholder = placeholder
        _image = State(initialValue: ProviderPhotoCache.image(for: photo.imageURL))
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                placeholder()
            }
        }
        .task(id: photo.imageURL) {
            let url = photo.imageURL
            image = ProviderPhotoCache.image(for: url)
            guard image == nil,
                  let data = await AircraftPhotoProvider.shared.imageData(for: photo),
                  let decoded = await UIImage(data: data)?.byPreparingForDisplay(),
                  !Task.isCancelled else { return }
            ProviderPhotoCache.store(decoded, for: url)
            withAnimation(.smooth) { image = decoded }
        }
    }
}

/// Decoded photos by URL, bounded by their decoded size. NSCache is thread-safe and also
/// empties itself under memory pressure.
private enum ProviderPhotoCache {
    private static let images: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.totalCostLimit = 30 << 20
        return cache
    }()

    static func image(for url: URL) -> UIImage? { images.object(forKey: url as NSURL) }
    static func store(_ image: UIImage, for url: URL) {
        images.setObject(image, forKey: url as NSURL, cost: image.decodedByteCount)
    }
}

extension UIImage {
    /// Roughly what the decoded bitmap takes in memory, for cache costs.
    var decodedByteCount: Int {
        if let cgImage { return cgImage.bytesPerRow * cgImage.height }
        return Int(size.width * scale * size.height * scale * 4)
    }
}
#endif
