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
    /// `.fill` crops to the frame; `.fit` shows the whole photo, with a blurred copy of it
    /// filling any space left over. Either way the caller clips to its shape.
    var contentMode: ContentMode = .fill
    /// Shown while loading, and if the image can't be fetched.
    let placeholder: () -> Placeholder

    @State private var image: UIImage?

    init(photo: AircraftPhoto, contentMode: ContentMode = .fill, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.photo = photo
        self.contentMode = contentMode
        self.placeholder = placeholder
        _image = State(initialValue: ProviderPhotoCache.image(for: photo.imageURL))
    }

    var body: some View {
        ZStack {
            if let image {
                PhotoImage(image: image, contentMode: contentMode)
                    .transition(.opacity)
            } else {
                placeholder()
            }
        }
        .task(id: photo.imageURL) {
            image = ProviderPhotoCache.image(for: photo.imageURL)
            guard image == nil, let decoded = await ProviderPhotoCache.load(photo), !Task.isCancelled else { return }
            withAnimation(.smooth) { image = decoded }
        }
    }
}

/// An aircraft's Planespotters photo as a rounded tile with the photographer's credit, for
/// the flight cards (the radar's centre, the map card, Sky View). Nothing at all shows until
/// the photo has arrived, or if there isn't one. `gap`, the space before it on `edge`, comes
/// with the photo, so a card without one keeps its own spacing.
struct AircraftPhotoTile: View {
    let registration: String?
    let hex: String?
    let width: CGFloat
    /// Nil: as tall as the row it sits in.
    let height: CGFloat?
    let gap: CGFloat
    let edge: Edge.Set
    /// The hairline round it: light on glass, ink on paper.
    let outline: Color

    @State private var loaded: Loaded?

    init(registration: String?, hex: String?, width: CGFloat, height: CGFloat? = nil,
         gap: CGFloat = 0, edge: Edge.Set = .leading, outline: Color = .white.opacity(0.2)) {
        self.registration = registration
        self.hex = hex
        self.width = width
        self.height = height
        self.gap = gap
        self.edge = edge
        self.outline = outline
        // An aircraft shown recently (refocused, or a card rebuilt) gets its photo back at once.
        if let key = Self.key(registration, hex), let photo = Self.found.object(forKey: key as NSString)?.photo,
           let image = ProviderPhotoCache.image(for: photo.imageURL) {
            _loaded = State(initialValue: Loaded(key: key, photo: photo, image: image))
        }
    }

    var body: some View {
        let key = Self.key(registration, hex)
        ZStack {
            if let loaded, loaded.key == key {
                tile(loaded)
                    .padding(edge, gap)
                    .transition(.opacity)
            }
        }
        .task(id: key) {
            guard let key, loaded?.key != key else { return }
            loaded = nil
            guard let photo = await AircraftPhotoProvider.shared.photo(registration: registration, hex: hex),
                  let image = await ProviderPhotoCache.load(photo), !Task.isCancelled else { return }
            Self.found.setObject(Found(photo), forKey: key as NSString)
            withAnimation(.smooth) { loaded = Loaded(key: key, photo: photo, image: image) }
        }
    }

    private func tile(_ loaded: Loaded) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return Color.clear
            .frame(width: width, height: height)
            .frame(maxHeight: height == nil ? .infinity : nil)
            // The whole photo, nose to tail.
            .overlay { PhotoImage(image: loaded.image, contentMode: .fit) }
            .overlay(alignment: .bottom) { credit(loaded.photo) }
            .clipShape(shape)
            .overlay(shape.strokeBorder(outline, lineWidth: 0.5))
            .accessibilityHidden(true)
    }

    /// Planespotters asks for the photographer's name wherever a photo is shown.
    private func credit(_ photo: AircraftPhoto) -> some View {
        Text("© \(photo.photographer ?? "Planespotters.net")")
            .font(.mono(8, .semibold))
            .foregroundStyle(.white.opacity(0.9))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 7)
            .padding(.top, 10)
            .padding(.bottom, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom))
    }

    private struct Loaded {
        let key: String
        let photo: AircraftPhoto
        let image: UIImage
    }

    private final class Found {
        let photo: AircraftPhoto
        init(_ photo: AircraftPhoto) { self.photo = photo }
    }

    /// Photos found for recent aircraft, so a rebuilt card doesn't wait on the provider.
    private static let found: NSCache<NSString, Found> = {
        let cache = NSCache<NSString, Found>()
        cache.countLimit = 50
        return cache
    }()

    private static func key(_ registration: String?, _ hex: String?) -> String? {
        let key = (registration ?? hex ?? "").uppercased()
        return key.isEmpty ? nil : key
    }
}

/// A decoded photo in whatever frame it's given: `.fill` crops to it; `.fit` shows the whole
/// photo, with a blurred copy of it filling any space left over. Callers clip.
private struct PhotoImage: View {
    let image: UIImage
    let contentMode: ContentMode

    var body: some View {
        if contentMode == .fit {
            Color.clear
                .overlay { Image(uiImage: image).resizable().scaledToFill().blur(radius: 12) }
                .overlay { Image(uiImage: image).resizable().scaledToFit() }
        } else {
            Image(uiImage: image).resizable().scaledToFill()
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

    /// The decoded photo: from memory, or fetched and decoded off the main thread.
    static func load(_ photo: AircraftPhoto) async -> UIImage? {
        if let cached = image(for: photo.imageURL) { return cached }
        guard let data = await AircraftPhotoProvider.shared.imageData(for: photo),
              let decoded = await UIImage(data: data)?.byPreparingForDisplay() else { return nil }
        store(decoded, for: photo.imageURL)
        return decoded
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
