//
//  WeatherFogLayer.swift
//  WhatTheFlight
//
//  Clouds and fog drawn where the weather reports put them (`Core/WeatherFog.swift`):
//  `RadarFogLayer` over the radar's backdrop, under the aircraft (it turns with the compass,
//  so cloud to the west sits to the west), and `MapFogOverlay` over `TrafficMap`, pinned to
//  the ground so it pans, zooms and turns with the map. Settings → Radar → Clouds and fog.
//
//  Cheap by design: the cloud texture is tileable noise made once off the main thread
//  (`FogTexture`), with how much of it reads as cloud set by the sky cover; small masks
//  (`FogArt`) place it between stations; the drift is the tiled texture sliding downwind at
//  15 fps. Still under Reduce Motion, in Low Power Mode and off screen.
//

#if os(iOS) || os(tvOS)
import SwiftUI
import CoreLocation
import MapKit
import os

// MARK: - Look

/// How clouds and fog are coloured on each backdrop.
struct FogLook: Equatable {
    var cloud: Color
    var cloudOpacity: Double
    /// Light paper: a faint grey copy offset below each cloud, so white reads on cream.
    var shadowOpacity: Double = 0
    var haze: Color
    var hazeOpacity: Double

    static func radar(_ scheme: ColorScheme) -> FogLook {
        scheme == .dark
            ? FogLook(cloud: night, cloudOpacity: 0.2, haze: night, hazeOpacity: 0.17)
            : FogLook(cloud: .white, cloudOpacity: 0.72, shadowOpacity: 0.09, haze: .white, hazeOpacity: 0.5)
    }

    /// Lighter than the radar's: on a map the fog lies over the aircraft too, and they
    /// mustn't read as the faded ones outside the ring.
    static func map(_ scheme: ColorScheme, imagery: Bool) -> FogLook {
        if imagery { return FogLook(cloud: .white, cloudOpacity: 0.5, shadowOpacity: 0.14, haze: .white, hazeOpacity: 0.26) }
        return scheme == .dark
            ? FogLook(cloud: night, cloudOpacity: 0.17, haze: night, hazeOpacity: 0.13)
            : FogLook(cloud: .white, cloudOpacity: 0.58, shadowOpacity: 0.06, haze: .white, hazeOpacity: 0.32)
    }

    private static let night = Color(red: 0.76, green: 0.81, blue: 0.92)
    static let shadow = Color(red: 0.22, green: 0.24, blue: 0.32)
}

// MARK: - Texture

/// Tileable fractal noise, thresholded into clouds: the more of the sky is covered, the more
/// of the tile is cloud. White, with the cloud in the alpha. The noise is domain-warped (its
/// coordinates nudged by more noise), which reads as cloud rather than blobs.
enum FogTexture {
    static let pixels = 384

    /// The noise (0 … 1) and its values sorted, for thresholds by coverage.
    private static let field: (values: [Float], sorted: [Float]) = {
        let n = pixels
        var values = [Float](repeating: 0, count: n * n)
        for y in 0..<n {
            for x in 0..<n {
                let u = Float(x) / Float(n), v = Float(y) / Float(n)
                let wx = fbm(u, v, base: 2, octaves: 3, seed: 101) - 0.5
                let wy = fbm(u, v, base: 2, octaves: 3, seed: 202) - 0.5
                values[y * n + x] = fbm(u + 0.22 * wx, v + 0.22 * wy, base: 4, octaves: 5, seed: 1)
            }
        }
        return (values, values.sorted())
    }()

    /// A well-mixed hash of a lattice point, 0 … 1.
    private static func lattice(_ x: Int, _ y: Int, _ seed: UInt32) -> Float {
        var h = (UInt32(truncatingIfNeeded: x) &* 0x8DA6_B343) ^ (UInt32(truncatingIfNeeded: y) &* 0xD816_3841) ^ (seed &* 0xCB1A_B31F)
        h ^= h >> 16; h &*= 0x7FEB_352D; h ^= h >> 15; h &*= 0x846C_A68B; h ^= h >> 16
        return Float(h >> 8) / 16_777_215
    }

    /// Value noise at (u, v) in tiles (it wraps at whole tiles), `period` cells a tile.
    private static func noise(_ u: Float, _ v: Float, period p: Int, seed: UInt32) -> Float {
        let fx = u * Float(p), fy = v * Float(p)
        let x0 = fx.rounded(.down), y0 = fy.rounded(.down)
        let tx = fx - x0, ty = fy - y0
        let sx = tx * tx * tx * (tx * (tx * 6 - 15) + 10), sy = ty * ty * ty * (ty * (ty * 6 - 15) + 10)
        let ix = ((Int(x0) % p) + p) % p, iy = ((Int(y0) % p) + p) % p
        let ix1 = (ix + 1) % p, iy1 = (iy + 1) % p
        let a = lattice(ix, iy, seed), b = lattice(ix1, iy, seed), c = lattice(ix, iy1, seed), d = lattice(ix1, iy1, seed)
        let top = a + (b - a) * sx, bottom = c + (d - c) * sx
        return top + (bottom - top) * sy
    }

    private static func fbm(_ u: Float, _ v: Float, base: Int, octaves: Int, seed: UInt32) -> Float {
        var sum: Float = 0, weight: Float = 1, total: Float = 0, period = base
        for o in 0..<octaves {
            sum += noise(u, v, period: period, seed: seed &+ UInt32(o) &* 7_919) * weight
            total += weight
            weight *= 0.5
            period *= 2
        }
        return sum / total
    }

    private static let cache = OSAllocatedUnfairLock(initialState: [Int: CGImage]())

    /// The clouds for this much of the sky covered, in tenths (1 … 10). Slow the first time:
    /// call it off the main thread.
    static func image(tenths: Int) -> CGImage? {
        let tenths = min(10, max(1, tenths))
        if let cached = cache.withLock({ $0[tenths] }) { return cached }
        let (values, sorted) = field
        // The threshold that leaves this share of the tile above it.
        let coverage = Float(tenths) / 10
        let cut = sorted[min(sorted.count - 1, Int((1 - coverage) * Float(sorted.count - 1)))]
        let lo = cut - 0.06, hi = cut + 0.16
        var bytes = [UInt8](repeating: 0, count: values.count * 4)
        for (i, v) in values.enumerated() {
            let t = min(1, max(0, (v - lo) / (hi - lo)))
            // Soft edges, and some body inside: an overcast tile still has texture.
            let alpha = t * t * (3 - 2 * t) * (0.68 + 0.32 * v)
            let b = UInt8(max(0, min(255, alpha * 255)))
            bytes[i * 4] = b; bytes[i * 4 + 1] = b; bytes[i * 4 + 2] = b; bytes[i * 4 + 3] = b
        }
        guard let image = FogArt.image(rgba: bytes, width: pixels, height: pixels) else { return nil }
        cache.withLock { $0[tenths] = image }
        return image
    }
}

// MARK: - Masks

/// Everything one fog field draws, made off the main thread: the cloud texture for the
/// densest cover in view, and masks spreading cloud and fog between the stations.
struct FogArt: @unchecked Sendable {
    let texture: CGImage?
    let cloudMask: CGImage?
    let fogMask: CGImage?
    let maxCloud: Double
    let maxFog: Double

    static let gridCount = 16

    static func make(fog: WeatherFog, center: CLLocationCoordinate2D, halfMiles: Double, edgeFade: Bool) async -> FogArt {
        await Task.detached(priority: .utility) {
            let grid = fog.grid(center: center, halfMiles: halfMiles, count: gridCount)
            let maxCloud = grid.maxCloud, maxFog = grid.maxFog
            let hasCloud = maxCloud >= WeatherFog.threshold, hasFog = maxFog >= WeatherFog.threshold
            return FogArt(
                texture: hasCloud ? FogTexture.image(tenths: Int((maxCloud * 10).rounded())) : nil,
                cloudMask: hasCloud ? mask(grid.cloud, peak: maxCloud, count: grid.count, edgeFade: edgeFade) : nil,
                fogMask: hasFog ? mask(grid.fog, peak: maxFog, count: grid.count, edgeFade: edgeFade) : nil,
                maxCloud: maxCloud, maxFog: maxFog
            )
        }.value
    }

    /// A small white image whose alpha is each sample against the peak, faded to nothing at
    /// the rim on a map (where the field ends on screen).
    private static func mask(_ values: [Double], peak: Double, count: Int, edgeFade: Bool) -> CGImage? {
        var bytes = [UInt8](repeating: 0, count: count * count * 4)
        for row in 0..<count {
            for column in 0..<count {
                var a = values[row * count + column] / max(peak, 0.001)
                if edgeFade {
                    let dx = 2 * Double(column) / Double(count - 1) - 1, dy = 2 * Double(row) / Double(count - 1) - 1
                    let r = (dx * dx + dy * dy).squareRoot()
                    let t = min(1, max(0, (r - 0.6) / 0.35))
                    a *= 1 - t * t * (3 - 2 * t)
                }
                let b = UInt8(max(0, min(255, a * 255)))
                let i = (row * count + column) * 4
                bytes[i] = b; bytes[i + 1] = b; bytes[i + 2] = b; bytes[i + 3] = b
            }
        }
        return image(rgba: bytes, width: count, height: count)
    }

    /// Premultiplied RGBA bytes as an image.
    static func image(rgba bytes: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

// MARK: - Field

/// A square of sky `2 × halfMiles` across, drawn `side` points wide, north up: the haze, then
/// the clouds drifting downwind.
struct WeatherFogField: View {
    let fog: WeatherFog
    let center: CLLocationCoordinate2D
    let halfMiles: Double
    let side: CGFloat
    /// One tile of the cloud texture, in points.
    let tile: CGFloat
    let look: FogLook
    var edgeFade = false
    var isAnimating = true

    @State private var art: FogArt?

    /// What the art depends on, coarsely: GPS wobble doesn't rebuild it.
    private struct ArtKey: Equatable {
        let fog: WeatherFog
        let latitude: Int, longitude: Int, halfMiles: Int
        let edgeFade: Bool
    }

    private var artKey: ArtKey {
        ArtKey(fog: fog, latitude: Int((center.latitude * 100).rounded()), longitude: Int((center.longitude * 100).rounded()),
               halfMiles: Int(halfMiles.rounded()), edgeFade: edgeFade)
    }

    var body: some View {
        ZStack {
            if let art {
                if let mask = art.fogMask {
                    Rectangle()
                        .fill(look.haze.opacity(look.hazeOpacity * min(1, 0.4 + art.maxFog)))
                        .mask { maskImage(mask) }
                }
                if let texture = art.texture, let mask = art.cloudMask {
                    clouds(texture)
                        .opacity(look.cloudOpacity * min(1, 0.5 + art.maxCloud))
                        .mask { maskImage(mask) }
                }
            }
        }
        .frame(width: side, height: side)
        // Fades in once the art is made.
        .animation(.easeInOut(duration: 1.5), value: art == nil)
        .task(id: artKey) {
            let made = await FogArt.make(fog: fog, center: center, halfMiles: halfMiles, edgeFade: edgeFade)
            guard !Task.isCancelled else { return }
            art = made
        }
    }

    private func maskImage(_ image: CGImage) -> some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.high)
            .frame(width: side, height: side)
    }

    /// The tiled texture, a tile bigger than the field each way, slid along the wind and
    /// wrapped every tile.
    private func clouds(_ texture: CGImage) -> some View {
        let image = Image(decorative: texture, scale: CGFloat(FogTexture.pixels) / max(1, tile))
            .renderingMode(.template)
            .resizable(resizingMode: .tile)
        return TimelineView(.animation(minimumInterval: 1.0 / 15, paused: !isAnimating)) { context in
            let drift = fog.drift(after: context.date.timeIntervalSinceReferenceDate)
            let dx = CGFloat(drift.east - drift.east.rounded(.down)) * tile
            let dy = CGFloat(drift.south - drift.south.rounded(.down)) * tile
            ZStack {
                if look.shadowOpacity > 0 {
                    image
                        .foregroundStyle(FogLook.shadow.opacity(look.shadowOpacity / look.cloudOpacity))
                        .offset(x: tile * 0.02, y: tile * 0.035)
                }
                image.foregroundStyle(look.cloud)
            }
            .frame(width: side + 2 * tile, height: side + 2 * tile)
            .offset(x: dx - tile / 2, y: dy - tile / 2)
        }
        .frame(width: side, height: side)
    }
}

// MARK: - Radar

/// The fog over the radar's backdrop: you're at the centre, the radius about half the short
/// side out, turned so the compass direction on screen matches the aircraft's.
struct RadarFogLayer: View {
    let fog: WeatherFog
    let observer: CLLocationCoordinate2D
    let radiusMiles: Double
    /// The compass direction at the top of the screen.
    let heading: Double
    var isActive = true

    /// One tile of cloud spans this many radii: about a screen wide, so its repeat is off
    /// screen.
    static let tileRadii = 1.5

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let pointsPerMile = max(0.01, min(geo.size.width, geo.size.height) / 2 / max(1, radiusMiles))
            // Square and as wide as the diagonal, so turning never shows a corner.
            let side = (geo.size.width * geo.size.width + geo.size.height * geo.size.height).squareRoot()
            WeatherFogField(fog: fog, center: observer, halfMiles: side / 2 / pointsPerMile, side: side,
                            tile: radiusMiles * Self.tileRadii * pointsPerMile, look: .radar(colorScheme),
                            isAnimating: isActive && !reduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled)
                .rotationEffect(.degrees(-heading))
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Map

/// Where the fog's square lands on the map: the affine transform from the field (north up,
/// `MapFogOverlay.side` points) to the map view, from three of its corners. Updated as the
/// camera moves; only the overlay reads it, so the map itself doesn't redraw.
@Observable
final class MapFogPlacement {
    var transform: CGAffineTransform?

    func update(proxy: MapProxy, center: CLLocationCoordinate2D, halfMiles: Double, space: some CoordinateSpaceProtocol) {
        let milesPerDegreeLongitude = max(1, 69.17 * cos(center.latitude * .pi / 180))
        func corner(north: Double, east: Double) -> CGPoint? {
            proxy.convert(CLLocationCoordinate2D(latitude: center.latitude + north / 69.0,
                                                 longitude: center.longitude + east / milesPerDegreeLongitude), to: space)
        }
        guard let nw = corner(north: halfMiles, east: -halfMiles),
              let ne = corner(north: halfMiles, east: halfMiles),
              let sw = corner(north: -halfMiles, east: -halfMiles) else {
            if transform != nil { transform = nil }
            return
        }
        let s = MapFogOverlay.side
        let t = CGAffineTransform(a: (ne.x - nw.x) / s, b: (ne.y - nw.y) / s, c: (sw.x - nw.x) / s, d: (sw.y - nw.y) / s, tx: nw.x, ty: nw.y)
        if t != transform { transform = t }
    }
}

/// The fog over `TrafficMap`, out to `WeatherFog.reachMiles` around home and faded at its rim.
struct MapFogOverlay: View {
    let fog: WeatherFog
    let center: CLLocationCoordinate2D
    let radiusMiles: Double
    let placement: MapFogPlacement
    let look: FogLook
    var isActive = true

    /// The field's size before it's placed: big enough that a zoomed-in map isn't blurry.
    static let side: CGFloat = 900

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let transform = placement.transform {
            let half = WeatherFog.reachMiles(radius: radiusMiles)
            let pointsPerMile = Self.side / 2 / half
            WeatherFogField(fog: fog, center: center, halfMiles: half, side: Self.side,
                            tile: radiusMiles * RadarFogLayer.tileRadii * pointsPerMile, look: look, edgeFade: true,
                            isAnimating: isActive && !reduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled)
                .frame(width: Self.side, height: Self.side)
                .transformEffect(transform)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Debug

#if DEBUG
extension SkyReport {
    /// `-wtf.debugWeather overcast|scattered|fog|mixed`: made-up weather around `observer`, so
    /// the clouds and fog can be seen on a clear day.
    static func debugPreset(_ name: String, around observer: CLLocationCoordinate2D) -> SkyReport {
        func station(_ id: String, north: Double = 0, east: Double = 0, visibility: Double = 10, layers: [(String, Int)],
                     weather: String? = nil, wind: (Double, Double)? = (250, 14)) -> SkyConditions {
            SkyConditions(station: id, stationName: id, latitude: observer.latitude + north / 69,
                          longitude: observer.longitude + east / max(1, 69.17 * cos(observer.latitude * .pi / 180)),
                          elevationFeet: 1_000, observedAt: Date(), visibilityMiles: visibility,
                          layers: layers.map { SkyConditions.Layer(cover: $0.0, baseFeet: $0.1) }, weather: weather,
                          windFromDegrees: wind?.0, windKnots: wind?.1, seesHighCloud: true)
        }
        let all: [SkyConditions]
        switch name {
        case "overcast": all = [station("KOVC", layers: [("OVC", 2_500)])]
        case "fog": all = [station("KFOG", visibility: 0.5, layers: [("VV", 200)], weather: "FG", wind: nil)]
        case "mixed":
            all = [
                station("KWST", east: -18, visibility: 4, layers: [("OVC", 1_500)], weather: "BR"),
                station("KEST", east: 18, layers: []),
                station("KNTH", north: 16, layers: [("SCT", 5_000)]),
                station("KSTH", north: -16, layers: [("BKN", 3_000)]),
            ]
        default: all = [station("KSCT", layers: [("SCT", 3_500), ("FEW", 8_000)])]
        }
        return SkyReport(nearest: SkyConditions.nearest(to: observer, in: all), all: all)
    }
}
#endif
#endif
