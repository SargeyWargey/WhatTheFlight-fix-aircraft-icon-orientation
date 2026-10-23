//
//  SpotCard.swift
//  WhatTheFlight
//
//  Sky View photos in the app: the boarding-pass card (your photo up top, untouched, a tear
//  line, then the flight as a boarding pass: route, flight, type, tail,
//  altitude, speed, distance, date and where you stood), the page that shows and shares
//  it, and thumbnails. The card is drawn from the logbook's copy of the photo plus the
//  `SpotPhoto` record whenever it's needed, never stored.
//

#if os(iOS) || os(tvOS)
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

/// Decoded photos, smallest size that does the job, cached. Fetches the image from iCloud
/// when the record arrived before its photo (or tvOS purged its copy).
@MainActor
enum SpotPhotoImages {
    /// Decoded photos, bounded by their decoded size: a 1600 px photo page is about 7 MB, a
    /// thumbnail well under 1. NSCache also empties itself under memory pressure.
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 50 << 20
        return cache
    }()

    static func load(_ id: String, store: SpotPhotoStore, maxPixels: Int) async -> UIImage? {
        let key = "\(id)-\(maxPixels)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        var data = await Task.detached(priority: .userInitiated) { store.data(id) }.value
        if data == nil, await LogbookSync.downloadPhoto(id: id, into: store) {
            data = await Task.detached(priority: .userInitiated) { store.data(id) }.value
        }
        guard let data else { return nil }
        let image = await Task.detached(priority: .userInitiated) { decode(data, maxPixels: maxPixels) }.value
        if let image { cache.setObject(image, forKey: key, cost: image.decodedByteCount) }
        return image
    }

    static func forget(_ id: String) {
        // NSCache can't enumerate keys; the sizes in use are few and fixed.
        for size in [160, 400, 1600] { cache.removeObject(forKey: "\(id)-\(size)" as NSString) }
    }

    nonisolated static func decode(_ data: Data, maxPixels: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { UIImage(cgImage: $0) }
    }
}

/// A square thumbnail of one photo, cropped toward the aircraft.
struct SpotPhotoThumbnail: View {
    let photo: SpotPhoto
    let store: SpotPhotoStore
    var size: CGFloat = 84

    @State private var image: UIImage?
    @State private var missing = false

    var body: some View {
        ZStack {
            Palette.paperShade.opacity(0.4)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if missing {
                Image(systemName: "icloud.and.arrow.down")
                    .font(.system(size: size * 0.25, weight: .semibold))
                    .foregroundStyle(Palette.faint)
            } else {
                ProgressView()
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.16, style: .continuous))
        .task(id: photo.id) {
            image = await SpotPhotoImages.load(photo.id, store: store, maxPixels: 400)
            missing = image == nil
        }
        .accessibilityLabel("Photo of \(photo.displayIdentifier), \(photo.takenAt.formatted(date: .abbreviated, time: .shortened))")
    }
}

#if os(iOS)
// MARK: - The card

/// Your photo as the top of a boarding pass. Drawn at a fixed 360 pt width in its own light
/// palette, whatever the app's appearance, so shared cards always look the same.
struct BoardingPassCard: View {
    let photo: SpotPhoto
    let image: UIImage?

    static let width: CGFloat = 360
    static let photoHeight: CGFloat = 300

    private enum Ink {
        static let paper = Color(UIColor(rgb: 0xF7F2E8))
        static let text = Color(UIColor(rgb: 0x1C2140))
        static let accent = Color(UIColor(rgb: 0xE5483B))
        static let route = Color(UIColor(rgb: 0x3A33D6))
        static let muted = Color(UIColor(rgb: 0x6F6A60))
        static let rule = Color(UIColor(rgb: 0xD9D1C2))
    }

    var body: some View {
        VStack(spacing: 0) {
            photoArea
            tearLine
            pass
        }
        .frame(width: Self.width)
        .background(Ink.paper)
        .clipShape(TicketShape(notchY: Self.photoHeight + 14, notchRadius: 14, cornerRadius: 22), style: FillStyle(eoFill: true))
        .environment(\.colorScheme, .light)
    }

    // MARK: Photo

    private var photoArea: some View {
        let frame = CGSize(width: Self.width, height: Self.photoHeight)
        let layout = PhotoCrop(imageSize: image?.size ?? frame, frame: frame, focus: photo.framePoint)
        return ZStack(alignment: .topLeading) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: layout.scaledSize.width, height: layout.scaledSize.height)
                    .offset(x: layout.offset.x, y: layout.offset.y)
            } else {
                LinearGradient(colors: [Color(UIColor(rgb: 0x5B94DB)), Color(UIColor(rgb: 0xBCD9F2))], startPoint: .top, endPoint: .bottom)
                AircraftGlyph(silhouette: AircraftTypeCatalog.silhouette(forTypeCode: photo.typeCode), size: 90, spinsRotor: false)
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: frame.width, height: frame.height)
            }
            HStack {
                chip("\(CameraZoom.label(photo.displayZoom))×" + (photo.visuallyLocked ? " · LOCKED ON" : ""))
                Spacer()
                chip("WHAT THE FLIGHT?")
            }
            .padding(12)
            stamp
                .frame(width: frame.width, height: frame.height, alignment: .bottomTrailing)
        }
        .frame(width: frame.width, height: frame.height, alignment: .topLeading)
        .clipped()
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.mono(10, .heavy))
            .tracking(1)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.45), in: Capsule())
    }

    private var tearLine: some View {
        Line()
            .stroke(Ink.rule, style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
            .frame(height: 1)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
    }

    // MARK: Pass

    private var pass: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("BOARDING PASS")
                    .font(.mono(11, .heavy))
                    .tracking(2.5)
                    .foregroundStyle(Ink.accent)
                Spacer()
                Text(photo.operatorName.uppercased())
                    .font(.mono(10, .bold))
                    .tracking(1)
                    .foregroundStyle(Ink.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            route
            if let miles = photo.routeMiles {
                progress(miles)
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    field("Flight", photo.displayIdentifier)
                    field("Aircraft", photo.typeCode ?? "—")
                    field("Tail", photo.registration ?? "—")
                }
                GridRow {
                    field("Altitude", "\(RadarFormat.wholeNumber(photo.altitudeFeet)) ft")
                    field("Speed", "\(RadarFormat.wholeNumber(photo.speedKnots)) kts")
                    field("Distance", "\(RadarFormat.miles(photo.distanceMiles)) mi")
                }
                GridRow {
                    field("Date", photo.takenAt.formatted(.dateTime.day().month(.abbreviated).year()).uppercased())
                    field("Time", photo.takenAt.formatted(date: .omitted, time: .shortened))
                    field("Look", "\(Int(photo.elevationDegrees.rounded()))° \(GeoMath.cardinal(photo.bearingDegrees))")
                }
            }
            if let type = photo.typeName {
                Text(type)
                    .font(.mono(11, .semibold))
                    .foregroundStyle(Ink.muted)
                    .lineLimit(1)
            }
            Line()
                .stroke(Ink.rule, lineWidth: 1)
                .frame(height: 1)
            HStack(alignment: .bottom, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Barcode(seed: photo.id)
                        .fill(Ink.text)
                        .frame(width: 150, height: 34)
                    Text("WTF·\(photo.id.prefix(8).uppercased())")
                        .font(.mono(8, .semibold))
                        .foregroundStyle(Ink.muted)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 3) {
                    Text("SPOTTED FROM")
                        .font(.mono(8, .bold))
                        .tracking(1.2)
                        .foregroundStyle(Ink.muted)
                    Text(photo.placeName ?? "Under the flight path")
                        .font(.mono(12, .bold))
                        .foregroundStyle(Ink.text)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 22)
    }

    @ViewBuilder
    private var route: some View {
        if photo.originIATA != nil || photo.destinationIATA != nil {
            HStack(alignment: .top) {
                airport(photo.originIATA, city: photo.origin?.city, alignment: .leading)
                Spacer(minLength: 4)
                Image(systemName: "airplane")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Ink.accent)
                    .padding(.top, 12)
                Spacer(minLength: 4)
                airport(photo.destinationIATA, city: photo.destination?.city, alignment: .trailing)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(photo.displayIdentifier)
                    .font(.mono(40, .heavy))
                    .foregroundStyle(Ink.route)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("No route filed")
                    .font(.mono(11, .semibold))
                    .foregroundStyle(Ink.muted)
            }
        }
    }

    private func airport(_ code: String?, city: String?, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(code ?? "???")
                .font(.mono(44, .heavy))
                .foregroundStyle(Ink.route)
            Text(city ?? "Unknown")
                .font(.mono(11, .semibold))
                .foregroundStyle(Ink.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func progress(_ miles: (flown: Double, remaining: Double)) -> some View {
        let fraction = miles.flown / max(1, miles.flown + miles.remaining)
        return VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Ink.rule).frame(height: 4)
                    Capsule().fill(Ink.route).frame(width: geo.size.width * fraction, height: 4)
                    Circle()
                        .fill(Ink.accent)
                        .frame(width: 10, height: 10)
                        .offset(x: geo.size.width * fraction - 5)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 10)
            Text("\(RadarFormat.wholeNumber(Int(miles.flown.rounded()))) mi flown · \(RadarFormat.wholeNumber(Int(miles.remaining.rounded()))) to go")
                .font(.mono(10, .semibold))
                .foregroundStyle(Ink.muted)
        }
    }

    private func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.mono(8, .bold))
                .tracking(1.2)
                .foregroundStyle(Ink.muted)
            Text(value)
                .font(.mono(14, .heavy))
                .foregroundStyle(Ink.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var stamp: some View {
        if let tag = photo.tags.first {
            let color = Palette.color(for: tag)
            // A passport-style stamp in the photo's corner.
            Text(tag.rawValue.uppercased())
                .font(.mono(13, .heavy))
                .tracking(2)
                .foregroundStyle(color)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Ink.paper.opacity(0.85), in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(color, lineWidth: 2))
                .rotationEffect(.degrees(-10))
                .padding(.bottom, 20)
                .padding(.trailing, 16)
        }
    }

    // MARK: Geometry

    /// Fills the frame with the photo, sliding the crop toward where the aircraft should be.
    /// Nothing is drawn on the photo: the predicted spot is rarely exactly on the aircraft.
    struct PhotoCrop {
        let scaledSize: CGSize
        let offset: CGPoint

        init(imageSize: CGSize, frame: CGSize, focus: CGPoint?) {
            let scale = max(frame.width / max(1, imageSize.width), frame.height / max(1, imageSize.height))
            scaledSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
            let fx = focus?.x ?? 0.5, fy = focus?.y ?? 0.5
            func slide(_ length: CGFloat, _ frameLength: CGFloat, _ f: CGFloat) -> CGFloat {
                min(0, max(frameLength - length, frameLength / 2 - f * length))
            }
            offset = CGPoint(x: slide(scaledSize.width, frame.width, fx), y: slide(scaledSize.height, frame.height, fy))
        }
    }
}

/// A rounded ticket with a semicircle bitten out of each side at the tear line (even-odd).
private struct TicketShape: Shape {
    let notchY: CGFloat
    let notchRadius: CGFloat
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect, cornerRadius: cornerRadius, style: .continuous)
        path.addEllipse(in: CGRect(x: rect.minX - notchRadius, y: notchY - notchRadius, width: notchRadius * 2, height: notchRadius * 2))
        path.addEllipse(in: CGRect(x: rect.maxX - notchRadius, y: notchY - notchRadius, width: notchRadius * 2, height: notchRadius * 2))
        return path
    }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}

/// Decorative bars, the same for the same photo.
private struct Barcode: Shape {
    let seed: String

    func path(in rect: CGRect) -> Path {
        var state = seed.utf8.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        var x = rect.minX
        var path = Path()
        var dark = true
        while x < rect.maxX {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let width = CGFloat(1 + (state >> 61)) * 1.2
            if dark { path.addRect(CGRect(x: x, y: rect.minY, width: min(width, rect.maxX - x), height: rect.height)) }
            x += width
            dark.toggle()
        }
        return path
    }
}

// MARK: - Rendering and sharing

@MainActor
enum SpotCardRenderer {
    /// The card on a night-sky backdrop, as an image for sharing or saving.
    static func render(_ photo: SpotPhoto, image: UIImage?) -> UIImage? {
        // Measured at its natural height: left to the renderer's guess, a card without a
        // route came out squashed (shrunken stats, black bands above and below).
        let content = BoardingPassCard(photo: photo, image: image)
            .fixedSize(horizontal: false, vertical: true)
            .compositingGroup()
            .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
            .padding(28)
            .background(LinearGradient(colors: [Color(UIColor(rgb: 0x0E1630)), Color(UIColor(rgb: 0x23305C))],
                                       startPoint: .top, endPoint: .bottom))
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: BoardingPassCard.width + 56, height: nil)
        renderer.scale = 3
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

/// The rendered card as a JPEG for the share sheet ("Save Image" puts it in Photos).
struct SpotCardShare: Transferable {
    let image: UIImage
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .jpeg) { share in
            share.image.jpegData(compressionQuality: 0.9) ?? Data()
        }
        .suggestedFileName { $0.name }
    }
}

// MARK: - Photo page

/// One photo as its boarding pass: share it, save the card, credit a different aircraft
/// that was in the same shot, or delete it.
struct SpotPhotoView: View {
    let photo: SpotPhoto
    let store: SpotPhotoStore
    /// Other aircraft in the same shot (straight after taking it).
    var alternatives: [SpotPhoto] = []
    /// Why it isn't in the logbook (demo traffic, a custom spot), if it isn't.
    var notLoggedReason: String?
    var onReassign: ((SpotPhoto) -> Void)?
    var onDelete: (() -> Void)?

    @State private var card: UIImage?
    @State private var saveState: PhotoLibrarySaver.Outcome?
    @State private var confirmingDelete = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Group {
                    if let card {
                        Image(uiImage: card)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    } else {
                        ProgressView()
                            .frame(height: 420)
                    }
                }
                .frame(maxWidth: 440)

                if let card {
                    ShareLink(item: SpotCardShare(image: card, name: "\(photo.displayIdentifier) boarding pass"),
                              preview: SharePreview("\(photo.displayIdentifier) · What The Flight?", image: Image(uiImage: card))) {
                        Label("Share Boarding Pass", systemImage: "square.and.arrow.up")
                            .font(.mono(15, .bold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        Task { await saveCard(card) }
                    } label: {
                        Label(saveLabel, systemImage: saveState == .saved ? "checkmark" : "square.and.arrow.down")
                            .font(.mono(14, .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(saveState == .saved)
                }

                if !alternatives.isEmpty, let onReassign {
                    Menu {
                        ForEach(alternatives) { other in
                            Button("\(other.displayIdentifier) · \(RadarFormat.miles(other.distanceMiles)) mi") { onReassign(other) }
                        }
                    } label: {
                        Label("Wrong aircraft?", systemImage: "arrow.triangle.swap")
                            .font(.mono(14, .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                if let notLoggedReason {
                    Label(notLoggedReason, systemImage: "info.circle")
                        .font(.mono(12))
                        .foregroundStyle(Palette.caption)
                }

                if onDelete != nil {
                    Button(role: .destructive) { confirmingDelete = true } label: {
                        Label("Delete Photo", systemImage: "trash")
                            .font(.mono(14, .semibold))
                    }
                    .padding(.top, 4)
                }
            }
            .padding(16)
        }
        .background(Palette.paper.ignoresSafeArea())
        .navigationTitle(photo.displayIdentifier)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: photo) {
            let image = await SpotPhotoImages.load(photo.id, store: store, maxPixels: 1600)
            card = SpotCardRenderer.render(photo, image: image)
        }
        .confirmationDialog("Delete this photo?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Photo", role: .destructive) {
                onDelete?()
                dismiss()
            }
        } message: {
            Text("It's removed from the logbook on all your devices. The original stays in your camera roll.")
        }
    }

    private var saveLabel: String {
        switch saveState {
        case .saved: return "Card Saved to Photos"
        case .denied: return "Allow Photos Access in Settings"
        case .failed: return "Couldn't Save · Try Again"
        case nil: return "Save Card to Photos"
        }
    }

    private func saveCard(_ card: UIImage) async {
        guard let data = card.jpegData(compressionQuality: 0.92) else { return }
        saveState = await PhotoLibrarySaver.save(data, location: nil, date: Date())
    }
}
#endif
#endif
