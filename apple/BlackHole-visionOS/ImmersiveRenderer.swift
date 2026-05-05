import Foundation
import Metal
import CompositorServices
import ARKit
import simd
import QuartzCore

/// Stereo-renders the Kerr black hole into both eyes of the Vision Pro.
///
/// Per-eye separate render passes (NOT vertex amplification) — visionOS
/// simulator doesn't support amplification, and a sequential per-eye loop
/// runs fine on real device too. Roughly 2× the cost of an amplified path
/// at 90 Hz; acceptable for v1.
final class ImmersiveRenderer {

    private let layerRenderer: LayerRenderer
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let library: MTLLibrary
    private var pipelineState: MTLRenderPipelineState!

    private let arSession = ARKitSession()
    private let worldTracking = WorldTrackingProvider()

    private weak var params: BlackHoleParameters?
    private let startTime = CFAbsoluteTimeGetCurrent()
    private var frameIndex: Int32 = 0

    /// Black hole sits this many meters in front of the user. The user is
    /// free to walk around it (head tracking provides parallax).
    private let blackHoleAnchorDistance: Float = 3.0

    init(layerRenderer: LayerRenderer, params: BlackHoleParameters) {
        self.layerRenderer = layerRenderer
        self.params = params
        self.device = layerRenderer.device
        guard let q = device.makeCommandQueue() else {
            fatalError("CompositorServices: command queue unavailable.")
        }
        self.commandQueue = q
        guard let lib = device.makeDefaultLibrary() else {
            fatalError("CompositorServices: default Metal library unavailable.")
        }
        self.library = lib

        // Pipeline is built lazily in renderFrame using the *actual* drawable
        // texture format so the descriptor matches whatever Compositor chose
        // for this device/sim. Building eagerly with `layerRenderer.configuration.colorFormat`
        // tripped a hard validation assert in the simulator.
        Task { try? await arSession.run([worldTracking]) }
    }

    private func ensurePipeline(for drawable: LayerRenderer.Drawable) {
        if pipelineState != nil { return }
        guard let vfn = library.makeFunction(name: "immersive_vs"),
              let ffn = library.makeFunction(name: "immersive_fs") else {
            fatalError("CompositorServices: missing immersive shaders.")
        }

        // Diagnostic: log every value we're feeding the pipeline descriptor.
        // Visible in `xcrun simctl spawn ... log show --predicate ...`.
        let colorFmt = drawable.colorTextures[0].pixelFormat
        let depthFmt = drawable.depthTextures[0].pixelFormat
        let samples = drawable.colorTextures[0].sampleCount
        let viewCount = layerRenderer.properties.viewCount
        NSLog("BH PIPELINE: color=\(colorFmt.rawValue) depth=\(depthFmt.rawValue) samples=\(samples) viewCount=\(viewCount)")

        let desc = MTLRenderPipelineDescriptor()
        desc.label = "Immersive Black Hole"
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.colorAttachments[0].pixelFormat = colorFmt
        desc.colorAttachments[0].writeMask = .all
        desc.depthAttachmentPixelFormat = depthFmt
        if depthFmt == .depth32Float_stencil8 || depthFmt == .x32_stencil8 {
            desc.stencilAttachmentPixelFormat = depthFmt
        }
        desc.rasterSampleCount = samples
        // CompositorServices pipelines must declare amplification count ==
        // properties.viewCount even when each eye is rendered in its own pass
        // — Metal's validator otherwise refuses the descriptor on visionOS.
        desc.maxVertexAmplificationCount = viewCount

        do {
            self.pipelineState = try device.makeRenderPipelineState(descriptor: desc)
            NSLog("BH PIPELINE: built successfully")
        } catch {
            fatalError("CompositorServices: pipeline build failed: \(error)")
        }
    }

    // MARK: - Render loop

    func startRenderLoop() {
        Task.detached(priority: .userInitiated) { [weak self] in
            await self?.renderLoop()
        }
    }

    private func renderLoop() async {
        while true {
            switch layerRenderer.state {
            case .paused:
                layerRenderer.waitUntilRunning()
            case .running:
                guard let frame = layerRenderer.queryNextFrame() else { continue }
                renderFrame(frame: frame)
            case .invalidated:
                return
            @unknown default:
                continue
            }
        }
    }

    private func renderFrame(frame: LayerRenderer.Frame) {
        frame.startUpdate()
        frame.endUpdate()

        guard let timing = frame.predictTiming() else { return }
        LayerRenderer.Clock().wait(until: timing.optimalInputTime)

        frame.startSubmission()
        defer { frame.endSubmission() }

        guard let drawable = frame.queryDrawable() else { return }
        ensurePipeline(for: drawable)

        let predictedTime = CACurrentMediaTime() + 1.0 / 90.0
        let deviceAnchor = worldTracking.queryDeviceAnchor(atTimestamp: predictedTime)
        drawable.deviceAnchor = deviceAnchor

        guard let cb = commandQueue.makeCommandBuffer() else { return }
        cb.label = "Immersive frame \(frameIndex)"

        let headTransform = deviceAnchor?.originFromAnchorTransform ?? matrix_identity_float4x4

        // One render pass per eye. drawable.colorTextures may be a single
        // array texture (slice per eye) or one texture per eye — `view.textureMap`
        // tells us which slice/viewport this view belongs in either case.
        for (idx, view) in drawable.views.enumerated() {
            let renderPass = MTLRenderPassDescriptor()
            // Pick the texture corresponding to this view. With separate-texture
            // mode (sim) we have one per index; with array-texture mode (device)
            // they're all slices of textures[0].
            let colorTex = drawable.colorTextures.count > idx
                ? drawable.colorTextures[idx]
                : drawable.colorTextures[0]
            let depthTex = drawable.depthTextures.count > idx
                ? drawable.depthTextures[idx]
                : drawable.depthTextures[0]
            renderPass.colorAttachments[0].texture = colorTex
            renderPass.colorAttachments[0].slice = view.textureMap.sliceIndex
            renderPass.colorAttachments[0].loadAction = .clear
            renderPass.colorAttachments[0].storeAction = .store
            renderPass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            renderPass.depthAttachment.texture = depthTex
            renderPass.depthAttachment.slice = view.textureMap.sliceIndex
            renderPass.depthAttachment.loadAction = .clear
            renderPass.depthAttachment.storeAction = .store
            renderPass.depthAttachment.clearDepth = 1.0
            renderPass.rasterizationRateMap = idx < drawable.rasterizationRateMaps.count
                ? drawable.rasterizationRateMaps[idx] : nil

            guard let encoder = cb.makeRenderCommandEncoder(descriptor: renderPass) else { continue }
            encoder.label = "Immersive eye \(idx)"
            encoder.setRenderPipelineState(pipelineState)
            encoder.setViewport(view.textureMap.viewport)

            var eye = makeSingleEyeUniforms(view: view, headTransform: headTransform)
            encoder.setVertexBytes(&eye, length: MemoryLayout<SingleEyeUniforms>.stride, index: 0)
            encoder.setFragmentBytes(&eye, length: MemoryLayout<SingleEyeUniforms>.stride, index: 0)

            var bh = makeBlackHoleUniforms()
            encoder.setFragmentBytes(&bh, length: MemoryLayout<BHUniforms>.stride, index: 1)

            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }

        drawable.encodePresent(commandBuffer: cb)
        cb.commit()

        frameIndex &+= 1
    }

    // MARK: - Uniform composition

    private func makeSingleEyeUniforms(view: LayerRenderer.Drawable.View,
                                       headTransform: simd_float4x4) -> SingleEyeUniforms {
        // visionOS gives us "world from view" (the eye's transform relative
        // to the head). Combine with head world transform to get eye world.
        let eyeWorldFromView = headTransform * view.transform
        let t = view.tangents
        var u = SingleEyeUniforms()
        u.eyeWorldFromView = eyeWorldFromView
        u.tangents = simd_float4(t.x, t.y, t.z, t.w)
        u.blackHolePosition = simd_float3(0, 0, -blackHoleAnchorDistance)
        return u
    }

    private func makeBlackHoleUniforms() -> BHUniforms {
        let p = params ?? BlackHoleParameters()
        var u = BHUniforms()
        u.resolution = simd_float2(2048, 2048)
        u.time = Float(CFAbsoluteTimeGetCurrent() - startTime)
        u.mass = p.mass
        u.spin = p.spin
        u.diskDensity = p.diskDensity
        u.diskTemp = p.diskTemp
        u.zoom = p.zoom
        u.mouse = simd_float2(0.5, 0.539)
        u.lensingStrength = p.lensingStrength
        u.diskSize = p.diskSize
        u.maxRaySteps = Int32(p.preset.maxRaySteps)
        u.enableDoppler = p.enableDoppler ? 1 : 0
        u.enableJets = p.enableJets ? 1 : 0
        u.enableLensing = p.enableLensing ? 1 : 0
        u.enableDisk = p.enableDisk ? 1 : 0
        u.enableStars = p.enableStars ? 1 : 0
        u.enablePhotonGlow = p.enablePhotonGlow ? 1 : 0
        u.enableRedshiftView = 0
        u.jitter = simd_float2(0, 0)
        u.diskScaleHeight = p.diskScaleHeight
        u.bloomThreshold = p.bloomThreshold
        u.bloomIntensity = p.bloomIntensity
        u.taaFeedback = 0
        u.frameDragStrength = p.frameDragStrength
        u.frameIndex = frameIndex
        return u
    }
}

// MARK: - Single-eye uniforms (Swift mirror — matches struct in MSL)

struct SingleEyeUniforms {
    /// World-from-view transform for this eye. Last column is camera world pos.
    var eyeWorldFromView: simd_float4x4 = matrix_identity_float4x4
    /// (left, right, top, bottom) tangents. Used to reconstruct view-space
    /// ray direction from each pixel's NDC.
    var tangents: simd_float4 = simd_float4(-1, 1, 1, -1)
    /// World-space anchor where the black hole simulation lives.
    var blackHolePosition: simd_float3 = .zero
    var _pad0: Float = 0
}
