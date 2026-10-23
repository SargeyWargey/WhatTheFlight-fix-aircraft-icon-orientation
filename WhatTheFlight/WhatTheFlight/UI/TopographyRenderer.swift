//
//  TopographyRenderer.swift
//  WhatTheFlight
//
//  Draws the contour map behind the radar with `TopographyShader`. The terrain is built once
//  per style and screen size into a height texture that every screen shares. Most screens
//  get the contours as a still image; the main radar draws them live in an MTKView while
//  Tide runs, which only shifts the line heights, so a frame costs a few texture reads.
//

#if os(iOS) || os(tvOS)
import Combine
import Metal
import MetalKit
import SwiftUI

extension EnvironmentValues {
    /// The chosen contour style, set at the roots so every backdrop follows Settings.
    @Entry var topographyStyle: RadarSettings.TopographyStyle = .survey
}

@MainActor
final class TopographyRenderer {
    /// nil when Metal isn't available: the backdrop is then plain paper.
    static let shared = TopographyRenderer()

    /// Size of the largest hills, in points. The TV is watched from across the room, so its
    /// terrain is the coarsest; the iPhone, held close, gets the finest.
    static var featurePoints: Float {
        #if os(tvOS)
        return 600
        #else
        return UIDevice.current.userInterfaceIdiom == .pad ? 420 : 340
        #endif
    }

    /// The terrain from the design preview.
    private static let seed: Float = 1

    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let heightPipeline: MTLComputePipelineState
    private let shadePipeline: MTLComputePipelineState
    private let contourPipeline: MTLRenderPipelineState
    /// Stands in for the shading texture when a style has none.
    private let blank: MTLTexture

    private var terrains: [Terrain] = []
    private var images: [(key: ImageKey, image: CGImage)] = []

    private init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = Self.compile(on: device),
              let height = library.makeFunction(name: "topographyHeight"),
              let shade = library.makeFunction(name: "topographyShade"),
              let vertex = library.makeFunction(name: "topographyVertex"),
              let fragment = library.makeFunction(name: "topographyContours") else { return nil }
        let pipeline = MTLRenderPipelineDescriptor()
        pipeline.vertexFunction = vertex
        pipeline.fragmentFunction = fragment
        pipeline.colorAttachments[0].pixelFormat = .bgra8Unorm
        let blankDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r16Float, width: 1, height: 1, mipmapped: false)
        blankDescriptor.storageMode = .private
        guard let heightPipeline = try? device.makeComputePipelineState(function: height),
              let shadePipeline = try? device.makeComputePipelineState(function: shade),
              let contourPipeline = try? device.makeRenderPipelineState(descriptor: pipeline),
              let blank = device.makeTexture(descriptor: blankDescriptor) else { return nil }
        self.device = device
        self.queue = queue
        self.heightPipeline = heightPipeline
        self.shadePipeline = shadePipeline
        self.contourPipeline = contourPipeline
        self.blank = blank
    }

    private static func compile(on device: MTLDevice) -> MTLLibrary? {
        do {
            return try device.makeLibrary(source: TopographyShader.source, options: nil)
        } catch {
            // The radar falls back to plain paper.
            Log.ui.fault("Topography shader didn't compile: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: Styles

    /// How each style reads the terrain: line spacing, weights and strength (the numbers
    /// from the design preview).
    struct Look {
        var shaderIndex: Int32
        var levels: Float
        var minorWidth: Float
        var indexWidth: Float
        var minorAlpha: Float
        var indexAlpha: Float
        var hasIndex: Bool
        var shade: Float

        static func of(_ style: RadarSettings.TopographyStyle, dark: Bool) -> Look {
            func pick(_ light: Float, _ night: Float) -> Float { dark ? night : light }
            switch style {
            case .remaster:
                return Look(shaderIndex: 0, levels: 7, minorWidth: 1.5, indexWidth: 1.5,
                            minorAlpha: pick(0.32, 0.17), indexAlpha: pick(0.32, 0.17), hasIndex: false, shade: 0)
            case .survey, .off:
                return Look(shaderIndex: 1, levels: 14, minorWidth: 0.8, indexWidth: 1.7,
                            minorAlpha: pick(0.22, 0.12), indexAlpha: pick(0.36, 0.20), hasIndex: true, shade: 0)
            case .highlands:
                return Look(shaderIndex: 2, levels: 17, minorWidth: 0.75, indexWidth: 1.6,
                            minorAlpha: pick(0.20, 0.11), indexAlpha: pick(0.34, 0.19), hasIndex: true, shade: 0)
            case .relief:
                return Look(shaderIndex: 3, levels: 13, minorWidth: 0.8, indexWidth: 1.6,
                            minorAlpha: pick(0.20, 0.11), indexAlpha: pick(0.33, 0.18), hasIndex: true, shade: pick(0.08, 0.05))
            }
        }
    }

    // MARK: Terrain

    private struct TerrainKey: Equatable {
        let style: RadarSettings.TopographyStyle
        let width: Int
        let height: Int
        let ptPerTexel: Float
        let origin: SIMD2<Float>
    }

    private final class Terrain {
        let key: TerrainKey
        let height: MTLTexture
        let shade: MTLTexture?

        init(key: TerrainKey, height: MTLTexture, shade: MTLTexture?) {
            self.key = key
            self.height = height
            self.shade = shade
        }
    }

    /// Matches `TerrainUniforms` in TopographyShader.
    private struct TerrainUniforms {
        var originPt: SIMD2<Float>
        var ptPerTexel: Float
        var featurePt: Float
        var seed: Float
        var style: Int32
    }

    /// Matches `ContourUniforms` in TopographyShader.
    private struct ContourUniforms {
        var paper: SIMD4<Float>
        var ink: SIMD4<Float>
        var shadeTint: SIMD4<Float>
        var heightSize: SIMD2<Float>
        var pxPerPt: Float
        var levels: Float
        var minorWidthPt: Float
        var indexWidthPt: Float
        var minorAlpha: Float
        var indexAlpha: Float
        var shift: Float
        var thinFloor: Float
        var shadeStrength: Float
        var hasIndex: Int32
        var dark: Int32
    }

    /// Full-screen terrain is stored at half the screen's pixel density (the lines are still
    /// drawn at full resolution): 1920 × 1080 floats on a 4K TV, about 8 MB.
    private static func texelsPerPoint(scale: CGFloat) -> CGFloat { max(1, scale / 2) }

    /// The terrain under a `region`-point view, centred on its middle so it stays put when an
    /// iPad rotates. Full-screen terrains are kept (two at most); small ones are built and dropped.
    private func terrain(style: RadarSettings.TopographyStyle, region: CGSize, texelsPerPt: CGFloat, keep: Bool) -> Terrain? {
        let key = TerrainKey(style: style,
                             width: max(1, Int((region.width * texelsPerPt).rounded(.up))),
                             height: max(1, Int((region.height * texelsPerPt).rounded(.up))),
                             ptPerTexel: Float(1 / texelsPerPt),
                             origin: SIMD2(Float(-region.width / 2), Float(-region.height / 2)))
        if let index = terrains.firstIndex(where: { $0.key == key }) {
            let hit = terrains.remove(at: index)
            terrains.insert(hit, at: 0)
            return hit
        }
        guard let built = build(key) else { return nil }
        if keep {
            terrains.insert(built, at: 0)
            if terrains.count > 2 { terrains.removeLast() }
        }
        return built
    }

    private func build(_ key: TerrainKey) -> Terrain? {
        let look = Look.of(key.style, dark: false)
        let heightDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float, width: key.width, height: key.height, mipmapped: false)
        heightDescriptor.usage = [.shaderRead, .shaderWrite]
        heightDescriptor.storageMode = .private
        guard let height = device.makeTexture(descriptor: heightDescriptor),
              let commands = queue.makeCommandBuffer(),
              let encoder = commands.makeComputeCommandEncoder() else { return nil }
        var uniforms = TerrainUniforms(originPt: key.origin, ptPerTexel: key.ptPerTexel,
                                       featurePt: Self.featurePoints, seed: Self.seed, style: look.shaderIndex)
        encoder.setComputePipelineState(heightPipeline)
        encoder.setTexture(height, index: 0)
        encoder.setBytes(&uniforms, length: MemoryLayout<TerrainUniforms>.stride, index: 0)
        dispatch(encoder, heightPipeline, width: key.width, height: key.height)

        var shade: MTLTexture?
        if look.shade > 0 {
            let shadeDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r16Float, width: key.width, height: key.height, mipmapped: false)
            shadeDescriptor.usage = [.shaderRead, .shaderWrite]
            shadeDescriptor.storageMode = .private
            shade = device.makeTexture(descriptor: shadeDescriptor)
            if let shade {
                encoder.setComputePipelineState(shadePipeline)
                encoder.setTexture(height, index: 0)
                encoder.setTexture(shade, index: 1)
                encoder.setBytes(&uniforms, length: MemoryLayout<TerrainUniforms>.stride, index: 0)
                dispatch(encoder, shadePipeline, width: key.width, height: key.height)
            }
        }
        encoder.endEncoding()
        commands.commit()
        // A one-off: tens of milliseconds, and only when the style or screen size changes.
        commands.waitUntilCompleted()
        return Terrain(key: key, height: height, shade: shade)
    }

    private func dispatch(_ encoder: MTLComputeCommandEncoder, _ pipeline: MTLComputePipelineState, width: Int, height: Int) {
        let w = pipeline.threadExecutionWidth
        let h = max(1, pipeline.maxTotalThreadsPerThreadgroup / w)
        encoder.dispatchThreadgroups(MTLSize(width: (width + w - 1) / w, height: (height + h - 1) / h, depth: 1),
                                     threadsPerThreadgroup: MTLSize(width: w, height: h, depth: 1))
    }

    // MARK: Contours

    private func encodeContours(_ encoder: MTLRenderCommandEncoder, terrain: Terrain, style: RadarSettings.TopographyStyle,
                                dark: Bool, pxPerPt: Float, shift: Float, thinFloor: Float) {
        let look = Look.of(style, dark: dark)
        var uniforms = ContourUniforms(
            paper: Self.paper(dark: dark),
            ink: dark ? SIMD4(0.66, 0.72, 0.86, 1) : SIMD4(0.30, 0.28, 0.25, 1),
            shadeTint: SIMD4(0.55, 0.62, 0.78, 1),
            heightSize: SIMD2(Float(terrain.key.width), Float(terrain.key.height)),
            pxPerPt: pxPerPt,
            levels: look.levels,
            minorWidthPt: look.minorWidth,
            indexWidthPt: look.indexWidth,
            minorAlpha: look.minorAlpha,
            indexAlpha: look.indexAlpha,
            shift: shift,
            thinFloor: thinFloor,
            shadeStrength: terrain.shade == nil ? 0 : look.shade,
            hasIndex: look.hasIndex ? 1 : 0,
            dark: dark ? 1 : 0
        )
        encoder.setRenderPipelineState(contourPipeline)
        encoder.setFragmentTexture(terrain.height, index: 0)
        encoder.setFragmentTexture(terrain.shade ?? blank, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ContourUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }

    /// `Palette.paper`, so the contours sit on exactly the app's paper.
    private static func paper(dark: Bool) -> SIMD4<Float> {
        let color = UIColor(Palette.paper).resolvedColor(with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD4(Float(r), Float(g), Float(b), 1)
    }

    /// One live frame into `view` (see `TopographyMetalView`).
    func draw(in view: MTKView, style: RadarSettings.TopographyStyle, dark: Bool, shift: Float) {
        let size = view.bounds.size
        guard size.width > 0, size.height > 0,
              let terrain = terrain(style: style, region: size, texelsPerPt: Self.texelsPerPoint(scale: view.contentScaleFactor), keep: true),
              let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commands = queue.makeCommandBuffer(),
              let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        encodeContours(encoder, terrain: terrain, style: style, dark: dark,
                       pxPerPt: Float(view.drawableSize.width / size.width), shift: shift, thinFloor: 0)
        encoder.endEncoding()
        commands.present(drawable)
        commands.commit()
    }

    // MARK: Still images

    private struct ImageKey: Equatable {
        let style: RadarSettings.TopographyStyle
        let dark: Bool
        let width: Int
        let height: Int
        let zoom: CGFloat
    }

    /// The contours for a `size`-point view as an image, cached. `zoom` above 1 fits more
    /// terrain in, for thumbnails and the tour's miniature screens.
    func image(style: RadarSettings.TopographyStyle, dark: Bool, size: CGSize, scale: CGFloat, zoom: CGFloat = 1) -> CGImage? {
        guard style != .off, size.width >= 1, size.height >= 1 else { return nil }
        let key = ImageKey(style: style, dark: dark, width: Int((size.width * scale).rounded()),
                           height: Int((size.height * scale).rounded()), zoom: zoom)
        if let index = images.firstIndex(where: { $0.key == key }) {
            let hit = images.remove(at: index)
            images.insert(hit, at: 0)
            return hit.image
        }
        let isLarge = key.width * key.height > 1_000_000
        let region = CGSize(width: size.width * zoom, height: size.height * zoom)
        guard let terrain = terrain(style: style, region: region,
                                    texelsPerPt: isLarge ? Self.texelsPerPoint(scale: scale) : scale / zoom, keep: isLarge),
              let image = render(terrain, style: style, dark: dark, width: key.width, height: key.height,
                                 pxPerPt: Float(scale / zoom), thinFloor: zoom > 1.5 ? 1 : 0) else { return nil }
        images.insert((key, image), at: 0)
        // A full-screen image is 33 MB on a 4K TV, so keep two of those and plenty of small ones.
        var large = 0, small = 0
        images = images.filter { entry in
            if entry.key.width * entry.key.height > 1_000_000 {
                large += 1
                return large <= 2
            }
            small += 1
            return small <= 16
        }
        return image
    }

    private func render(_ terrain: Terrain, style: RadarSettings.TopographyStyle, dark: Bool,
                        width: Int, height: Int, pxPerPt: Float, thinFloor: Float) -> CGImage? {
        let targetDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        targetDescriptor.usage = [.renderTarget]
        targetDescriptor.storageMode = .private
        // The simulator can't read shared textures back, so copy through a buffer.
        let bytesPerRow = (width * 4 + 255) / 256 * 256
        guard let target = device.makeTexture(descriptor: targetDescriptor),
              let readback = device.makeBuffer(length: bytesPerRow * height, options: .storageModeShared),
              let commands = queue.makeCommandBuffer() else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        encodeContours(encoder, terrain: terrain, style: style, dark: dark, pxPerPt: pxPerPt, shift: 0, thinFloor: thinFloor)
        encoder.endEncoding()
        guard let blit = commands.makeBlitCommandEncoder() else { return nil }
        blit.copy(from: target, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: width, height: height, depth: 1),
                  to: readback, destinationOffset: 0, destinationBytesPerRow: bytesPerRow,
                  destinationBytesPerImage: bytesPerRow * height)
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        let data = Data(bytes: readback.contents(), count: bytesPerRow * height)
        guard let provider = CGDataProvider(data: data as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                       space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

// MARK: - Views

/// The contours behind one screen: live on the main radar while Tide runs, otherwise (and
/// with Reduce Motion) a still image. Low Power Mode and a backgrounded app pause the motion.
struct TopographyLayer: View {
    let style: RadarSettings.TopographyStyle
    var motion: RadarSettings.TopographyMotion = .off
    var isActive = true
    /// Terrain points per view point; above 1 fits a whole screen's worth into a miniature.
    var zoom: CGFloat = 1

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    var body: some View {
        if let renderer = TopographyRenderer.shared, style != .off {
            GeometryReader { geo in
                if motion != .off && !reduceMotion && zoom == 1 {
                    TopographyMetalView(renderer: renderer, style: style, dark: colorScheme == .dark,
                                        speed: motion.speed, isRunning: isActive && !lowPower)
                } else if let image = renderer.image(style: style, dark: colorScheme == .dark, size: geo.size,
                                                     scale: displayScale, zoom: zoom) {
                    Image(decorative: image, scale: displayScale)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange).receive(on: RunLoop.main)) { _ in
                lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }
    }
}

/// Tide: an MTKView redrawing the contours at 20–30 fps as their heights creep.
struct TopographyMetalView: UIViewRepresentable {
    let renderer: TopographyRenderer
    let style: RadarSettings.TopographyStyle
    let dark: Bool
    let speed: Double
    let isRunning: Bool

    func makeCoordinator() -> Coordinator { Coordinator(renderer: renderer) }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: renderer.device)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.isOpaque = true
        view.isUserInteractionEnabled = false
        view.autoResizeDrawable = true
        if let layer = view.layer as? CAMetalLayer {
            layer.maximumDrawableCount = 2
            layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        }
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        let coordinator = context.coordinator
        coordinator.style = style
        coordinator.dark = dark
        coordinator.speed = speed
        // This slow, 20 fps is as smooth as 30.
        view.preferredFramesPerSecond = speed < 1 ? 20 : 30
        // Paused (backgrounded, Low Power Mode), it still redraws on demand, so a style change
        // or the first layout shows up; a draw() before the view has a size would be lost.
        view.enableSetNeedsDisplay = !isRunning
        view.isPaused = !isRunning
        if !isRunning {
            coordinator.lastFrame = nil
            view.setNeedsDisplay()
        }
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        let renderer: TopographyRenderer
        var style: RadarSettings.TopographyStyle = .survey
        var dark = false
        var speed: Double = 1
        /// In contour levels. 1× creeps 0.05 a second: one line spacing every 20 seconds.
        private var shift: Double = 0
        var lastFrame: CFTimeInterval?

        init(renderer: TopographyRenderer) {
            self.renderer = renderer
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            if view.isPaused { view.setNeedsDisplay() }
        }

        func draw(in view: MTKView) {
            let now = CACurrentMediaTime()
            if !view.isPaused, let lastFrame {
                // Every fifth line is an index line, so the pattern repeats every five levels.
                shift = (shift + min(0.1, now - lastFrame) * 0.05 * speed).truncatingRemainder(dividingBy: 5)
            }
            lastFrame = view.isPaused ? nil : now
            MainActor.assumeIsolated {
                renderer.draw(in: view, style: style, dark: dark, shift: Float(shift))
            }
        }
    }
}
#endif
