import Foundation
import Metal
import MetalKit
import simd

/// Multipass renderer:
///   1. scene  -> sceneRT       (HDR rgba16float, fullscreen quad raymarcher)
///   2. taa    -> history[i]    (neighborhood-clamped temporal AA)
///   3. bright -> bloomBright   (luminance threshold, half-res)
///   4. blurH  -> bloomScratch
///   5. blurV  -> bloomBright
///   6. comp   -> drawable      (additive bloom + ACES + gamma)
///
/// Performance levers:
///   - Scene fragment uses Metal function constants for feature flags so toggles
///     fold to compile-time and disappear from the inner ray loop. Pipelines
///     are cached per 7-bit flag mask in `scenePipelines`.
///   - PID-driven adaptive resolution multiplies `preset.renderScale` by
///     `dynamicScale` to hold ~60 FPS without visible quality cuts.
///   - Camera pose (yaw / pitch / zoom) is exponentially blended toward the
///     user-set target each frame so drag, pinch, and preset changes feel
///     soft instead of snappy.
final class Renderer: NSObject, MTKViewDelegate {

    // Plumbing
    let device: MTLDevice
    private let library: MTLLibrary
    private let queue: MTLCommandQueue
    private let bilinearSampler: MTLSamplerState

    // Scene pipeline cache (function-constant specialized) + post pipelines
    private var scenePipelines: [UInt8: MTLRenderPipelineState] = [:]
    private let taaPipeline: MTLRenderPipelineState
    private let brightPipeline: MTLRenderPipelineState
    private let blurHPipeline: MTLRenderPipelineState
    private let blurVPipeline: MTLRenderPipelineState
    private let compositePipeline: MTLRenderPipelineState
    private let copyPipeline: MTLRenderPipelineState
    private let drawableFormat: MTLPixelFormat

    // Resources
    private var uniformsBuffer: MTLBuffer
    private var sceneRT: MTLTexture?
    private var history: [MTLTexture] = []
    private var historyIdx: Int = 0
    private var bloomBright: MTLTexture?
    private var bloomScratch: MTLTexture?
    private var rtSize: CGSize = .zero
    private var rtScale: Float = 1.0   // The scale used to allocate current RTs.

    // State
    private let startTime = CFAbsoluteTimeGetCurrent()
    private var lastFrameTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    private var frameIndex: Int32 = 0
    private var historyValid: Bool = false
    private var lastParamsSnapshot: BHUniforms = BHUniforms()
    private var smoothedFPS: Double = 0

    // Camera smoothing
    private var displayedYaw: Float = 0.5
    private var displayedPitch: Float = 0.539
    private var displayedZoom: Float = 100.0
    private var cameraInitialized: Bool = false
    /// Critical-damping exponent. Larger = stiffer; ~12 settles in ~250 ms.
    private let cameraDamping: Float = 12.0

    // Adaptive resolution PID (matches web's `useAdaptiveResolution` constants)
    private var dynamicScale: Float = 1.0
    private var pidIntegral: Double = 0
    private var pidPrevError: Double = 0
    private let pidKp: Double = 0.025
    private let pidKi: Double = 0.005
    private let pidKd: Double = 0.04
    /// Target FPS. PID acts on the error in Hz.
    private let pidTargetFPS: Double = 60.0
    /// Don't react to errors smaller than this — avoids flapping.
    private let pidDeadzoneFPS: Double = 5.0
    private let dynamicScaleMin: Float = 0.5
    private let dynamicScaleMax: Float = 1.0

    // External params
    var params: BlackHoleParameters

    init(mtkView: MTKView, params: BlackHoleParameters) {
        guard let device = mtkView.device ?? MTLCreateSystemDefaultDevice() else {
            fatalError("Metal not supported on this device.")
        }
        self.device = device
        mtkView.device = device

        guard let queue = device.makeCommandQueue() else {
            fatalError("Could not create command queue.")
        }
        self.queue = queue

        guard let library = device.makeDefaultLibrary() else {
            fatalError("Default Metal library missing.")
        }
        self.library = library
        self.drawableFormat = mtkView.colorPixelFormat

        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: samplerDesc) else {
            fatalError("Could not create sampler.")
        }
        self.bilinearSampler = sampler

        // Post pipelines (no function constants).
        self.taaPipeline = Renderer.makePipeline(
            device: device, library: library,
            vertex: "pp_vs", fragment: "taa_fs",
            colorFormat: .rgba16Float, label: "taa")
        self.brightPipeline = Renderer.makePipeline(
            device: device, library: library,
            vertex: "pp_vs", fragment: "bright_fs",
            colorFormat: .rgba16Float, label: "bright")
        self.blurHPipeline = Renderer.makePipeline(
            device: device, library: library,
            vertex: "pp_vs", fragment: "blur_h_fs",
            colorFormat: .rgba16Float, label: "blurH")
        self.blurVPipeline = Renderer.makePipeline(
            device: device, library: library,
            vertex: "pp_vs", fragment: "blur_v_fs",
            colorFormat: .rgba16Float, label: "blurV")
        self.compositePipeline = Renderer.makePipeline(
            device: device, library: library,
            vertex: "pp_vs", fragment: "composite_fs",
            colorFormat: drawableFormat, label: "composite")
        self.copyPipeline = Renderer.makePipeline(
            device: device, library: library,
            vertex: "pp_vs", fragment: "copy_fs",
            colorFormat: .rgba16Float, label: "copy")

        // Uniforms buffer
        let length = MemoryLayout<BHUniforms>.stride
        guard let buffer = device.makeBuffer(length: length, options: [.storageModeShared]) else {
            fatalError("Failed to allocate uniforms buffer.")
        }
        self.uniformsBuffer = buffer

        self.params = params
        super.init()
    }

    private static func makePipeline(device: MTLDevice,
                                     library: MTLLibrary,
                                     vertex: String,
                                     fragment: String,
                                     colorFormat: MTLPixelFormat,
                                     label: String) -> MTLRenderPipelineState
    {
        guard let vfn = library.makeFunction(name: vertex),
              let ffn = library.makeFunction(name: fragment) else {
            fatalError("Missing function \(vertex) / \(fragment) in default library.")
        }
        let desc = MTLRenderPipelineDescriptor()
        desc.label = label
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.colorAttachments[0].pixelFormat = colorFormat
        do {
            return try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            fatalError("Failed to build pipeline \(label): \(error)")
        }
    }

    /// Build (or fetch) the scene pipeline specialized for the given flag mask.
    private func scenePipeline(forMask mask: UInt8) -> MTLRenderPipelineState {
        if let cached = scenePipelines[mask] { return cached }

        let cv = MTLFunctionConstantValues()
        for (idx, bit) in (0..<7).enumerated() {
            var on = (mask >> bit) & 1 == 1
            cv.setConstantValue(&on, type: .bool, index: idx)
        }

        let vfn: MTLFunction
        let ffn: MTLFunction
        do {
            vfn = library.makeFunction(name: "bh_vs")!  // bh_vs has no function constants
            ffn = try library.makeFunction(name: "bh_fs", constantValues: cv)
        } catch {
            fatalError("Failed to specialize scene fragment: \(error)")
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.label = "scene-\(mask)"
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.colorAttachments[0].pixelFormat = .rgba16Float
        do {
            let pso = try device.makeRenderPipelineState(descriptor: desc)
            scenePipelines[mask] = pso
            return pso
        } catch {
            fatalError("Failed to build scene pipeline (mask=\(mask)): \(error)")
        }
    }

    private func currentSceneMask() -> UInt8 {
        // Bit positions match function_constant indices in BlackHole.metal.
        var m: UInt8 = 0
        if params.enableLensing     { m |= 1 << 0 }
        if params.enableDisk        { m |= 1 << 1 }
        if params.enableDoppler     { m |= 1 << 2 }
        if params.enablePhotonGlow  { m |= 1 << 3 }
        if params.enableStars       { m |= 1 << 4 }
        if params.enableJets        { m |= 1 << 5 }
        if params.showRedshift      { m |= 1 << 6 }
        return m
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        rebuildOffscreenTargets(for: size)
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor
        else { return }

        // Frame timing & smoothed FPS for HUD + adaptive scale + auto-spin.
        let now = CFAbsoluteTimeGetCurrent()
        let dt = max(1.0 / 240.0, min(now - lastFrameTime, 1.0 / 15.0))
        lastFrameTime = now
        smoothedFPS = smoothedFPS * 0.92 + (1.0 / dt) * 0.08
        params.fps = smoothedFPS
        params.frameTimeMs = dt * 1000.0
        params.effectiveRenderScale = rtScale

        // Auto-spin: pause while user is interacting with the camera.
        let interacting = (now - params.lastInteraction) < 0.6
        if !interacting && abs(params.autoSpin) > 1e-5 {
            let next = params.yaw + Float(dt) * params.autoSpin / (2.0 * .pi)
            var wrapped = next.truncatingRemainder(dividingBy: 1.0)
            if wrapped < 0 { wrapped += 1.0 }
            params.yaw = wrapped
        }

        // Camera smoothing — exponential blend toward user targets.
        if !cameraInitialized {
            displayedYaw = params.yaw
            displayedPitch = params.pitch
            displayedZoom = params.zoom
            cameraInitialized = true
        }
        let blend = 1.0 - exp(-cameraDamping * Float(dt))
        displayedPitch += (params.pitch - displayedPitch) * blend
        displayedZoom  += (params.zoom  - displayedZoom)  * blend
        var dyaw = (params.yaw - displayedYaw).truncatingRemainder(dividingBy: 1.0)
        if dyaw >  0.5 { dyaw -= 1.0 }
        if dyaw < -0.5 { dyaw += 1.0 }
        var nextYaw = displayedYaw + dyaw * blend
        nextYaw = nextYaw.truncatingRemainder(dividingBy: 1.0)
        if nextYaw < 0 { nextYaw += 1.0 }
        displayedYaw = nextYaw

        // Adaptive resolution PID (after FPS smooths in).
        if smoothedFPS > 5 {
            updateDynamicScale(dt: dt)
        }

        let drawableSize = view.drawableSize
        if drawableSize != rtSize { rebuildOffscreenTargets(for: drawableSize) }
        guard let sceneRT = sceneRT,
              let bloomBright = bloomBright,
              let bloomScratch = bloomScratch,
              history.count == 2 else { return }

        let preset = params.preset
        let bloomEnabled = preset.bloomEnabled
        let taaEnabled = preset.taaEnabled

        // Snapshot uniforms (also used to drive history-reset detection).
        let u = makeUniforms(view: view)
        let resetHistory = !historyValid || cameraChangedSignificantly(prev: lastParamsSnapshot, curr: u)
        var uMutable = u
        if !taaEnabled || resetHistory {
            uMutable.taaFeedback = 0.0
        }
        memcpy(uniformsBuffer.contents(), &uMutable, MemoryLayout<BHUniforms>.size)
        lastParamsSnapshot = uMutable

        guard let cb = queue.makeCommandBuffer() else { return }
        cb.label = "BlackHole frame \(frameIndex)"

        // 1. Scene pass -> sceneRT (function-constant specialized pipeline).
        let scenePSO = scenePipeline(forMask: currentSceneMask())
        renderToTexture(commandBuffer: cb, target: sceneRT, label: "scene") { enc in
            enc.setRenderPipelineState(scenePSO)
            enc.setVertexBuffer(uniformsBuffer, offset: 0, index: 0)
            enc.setFragmentBuffer(uniformsBuffer, offset: 0, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }

        // 2. TAA pass (or pass-through copy when disabled).
        let resolvedHistoryIdx = historyIdx
        let prevHistoryIdx = 1 - historyIdx
        let resolved = history[resolvedHistoryIdx]

        if taaEnabled {
            renderToTexture(commandBuffer: cb, target: resolved, label: "taa") { enc in
                enc.setRenderPipelineState(taaPipeline)
                enc.setFragmentBuffer(uniformsBuffer, offset: 0, index: 0)
                enc.setFragmentTexture(sceneRT, index: 0)
                enc.setFragmentTexture(history[prevHistoryIdx], index: 1)
                enc.setFragmentSamplerState(bilinearSampler, index: 0)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            }
        } else {
            renderToTexture(commandBuffer: cb, target: resolved, label: "copy") { enc in
                enc.setRenderPipelineState(copyPipeline)
                enc.setFragmentTexture(sceneRT, index: 0)
                enc.setFragmentSamplerState(bilinearSampler, index: 0)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            }
        }
        historyIdx = 1 - historyIdx
        historyValid = true

        // 3-5. Bloom (skipped on low presets).
        if bloomEnabled {
            renderToTexture(commandBuffer: cb, target: bloomBright, label: "bright") { enc in
                enc.setRenderPipelineState(brightPipeline)
                enc.setFragmentBuffer(uniformsBuffer, offset: 0, index: 0)
                enc.setFragmentTexture(resolved, index: 0)
                enc.setFragmentSamplerState(bilinearSampler, index: 0)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            }
            renderToTexture(commandBuffer: cb, target: bloomScratch, label: "blurH") { enc in
                enc.setRenderPipelineState(blurHPipeline)
                enc.setFragmentTexture(bloomBright, index: 0)
                enc.setFragmentSamplerState(bilinearSampler, index: 0)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            }
            renderToTexture(commandBuffer: cb, target: bloomBright, label: "blurV") { enc in
                enc.setRenderPipelineState(blurVPipeline)
                enc.setFragmentTexture(bloomScratch, index: 0)
                enc.setFragmentSamplerState(bilinearSampler, index: 0)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            }
        }

        // 6. Composite -> drawable.
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        guard let enc = cb.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        enc.label = "composite"
        enc.setRenderPipelineState(compositePipeline)
        enc.setFragmentBuffer(uniformsBuffer, offset: 0, index: 0)
        enc.setFragmentTexture(resolved, index: 0)
        enc.setFragmentTexture(bloomEnabled ? bloomBright : sceneRT, index: 1)
        enc.setFragmentSamplerState(bilinearSampler, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()

        cb.present(drawable)
        cb.commit()

        frameIndex &+= 1
    }

    // MARK: - Adaptive resolution

    private func updateDynamicScale(dt: TimeInterval) {
        let error = pidTargetFPS - smoothedFPS
        guard abs(error) > pidDeadzoneFPS else { return }
        pidIntegral += error * dt
        // Anti-windup
        pidIntegral = min(max(pidIntegral, -100.0), 100.0)
        let derivative = (error - pidPrevError) / max(dt, 1e-3)
        pidPrevError = error
        // Positive error = below target → reduce scale.
        let correction = pidKp * error + pidKi * pidIntegral + pidKd * derivative
        let nextScale = Float(Double(dynamicScale) - correction * 0.02)
        let clamped = min(max(nextScale, dynamicScaleMin), dynamicScaleMax)
        dynamicScale = clamped

        // Reallocate RTs only when crossing a 0.05 quantization band, so we
        // don't thrash the texture allocator.
        let effective = quantize(dynamicScale * params.preset.renderScale)
        if abs(effective - rtScale) > 0.001 {
            rebuildOffscreenTargets(for: rtSize)
        }
    }

    private func quantize(_ x: Float) -> Float {
        return (x * 20.0).rounded() / 20.0   // 0.05 step
    }

    // MARK: - Helpers

    private func renderToTexture(commandBuffer: MTLCommandBuffer,
                                 target: MTLTexture,
                                 label: String,
                                 _ body: (MTLRenderCommandEncoder) -> Void)
    {
        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = target
        // Use `.clear` (not `.dontCare`) so any pixel the fullscreen triangle
        // doesn't cover (e.g., during a drawable resize while SwiftUI animates
        // the host view) shows clean black instead of stale frame data — which
        // was causing the tiled / displaced multi-frame artifact on iPhone
        // when the bottom sheet animation toggled.
        desc.colorAttachments[0].loadAction = .clear
        desc.colorAttachments[0].storeAction = .store
        desc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: desc) {
            enc.label = label
            body(enc)
            enc.endEncoding()
        }
    }

    private func rebuildOffscreenTargets(for size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        rtSize = size
        let effectiveScale = quantize(dynamicScale * params.preset.renderScale)
        rtScale = effectiveScale
        let scaledW = max(1, Int(Float(size.width)  * effectiveScale))
        let scaledH = max(1, Int(Float(size.height) * effectiveScale))

        sceneRT = makeRT(w: scaledW, h: scaledH, label: "sceneRT")
        history = [
            makeRT(w: scaledW, h: scaledH, label: "history0"),
            makeRT(w: scaledW, h: scaledH, label: "history1")
        ]
        bloomBright  = makeRT(w: max(1, scaledW / 2), h: max(1, scaledH / 2), label: "bloomBright")
        bloomScratch = makeRT(w: max(1, scaledW / 2), h: max(1, scaledH / 2), label: "bloomScratch")

        historyValid = false
    }

    private func makeRT(w: Int, h: Int, label: String) -> MTLTexture {
        let desc = MTLTextureDescriptor()
        desc.pixelFormat = .rgba16Float
        desc.width = w
        desc.height = h
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        guard let tex = device.makeTexture(descriptor: desc) else {
            fatalError("Could not allocate \(label).")
        }
        tex.label = label
        return tex
    }

    private func makeUniforms(view: MTKView) -> BHUniforms {
        let size = view.drawableSize
        let effectiveScale = rtScale
        let renderW = max(1.0, Float(size.width)  * effectiveScale)
        let renderH = max(1.0, Float(size.height) * effectiveScale)

        let h = halton(index: Int(frameIndex) + 1)
        let jitter = simd_float2((h.x - 0.5), (h.y - 0.5)) * 0.8

        var u = BHUniforms()
        u.resolution         = simd_float2(renderW, renderH)
        u.time               = Float(CFAbsoluteTimeGetCurrent() - startTime)
        u.mass               = params.mass
        u.spin               = params.spin
        u.diskDensity        = params.diskDensity
        u.diskTemp           = params.diskTemp
        u.zoom               = displayedZoom
        u.mouse              = simd_float2(displayedYaw, displayedPitch)
        u.lensingStrength    = params.lensingStrength
        u.diskSize           = params.diskSize
        u.maxRaySteps        = Int32(params.preset.maxRaySteps)
        // Feature flags now live in function constants; the int fields stay as
        // documentation only (some shaders still read them in non-hot paths).
        u.enableDoppler      = params.enableDoppler ? 1 : 0
        u.enableJets         = params.enableJets ? 1 : 0
        u.enableLensing      = params.enableLensing ? 1 : 0
        u.enableDisk         = params.enableDisk ? 1 : 0
        u.enableStars        = params.enableStars ? 1 : 0
        u.enablePhotonGlow   = params.enablePhotonGlow ? 1 : 0
        u.enableRedshiftView = params.showRedshift ? 1 : 0
        u.jitter             = jitter
        u.diskScaleHeight    = params.diskScaleHeight
        u.bloomThreshold     = params.bloomThreshold
        u.bloomIntensity     = params.bloomIntensity
        u.taaFeedback        = params.preset.taaEnabled ? 0.92 : 0.0
        u.frameDragStrength  = params.frameDragStrength
        u.frameIndex         = frameIndex
        return u
    }

    private func cameraChangedSignificantly(prev: BHUniforms, curr: BHUniforms) -> Bool {
        let dyaw   = abs(prev.mouse.x - curr.mouse.x)
        let dpitch = abs(prev.mouse.y - curr.mouse.y)
        let dzoom  = abs(prev.zoom - curr.zoom)
        return dyaw > 0.005 || dpitch > 0.005 || dzoom > 0.05
    }

    private func halton(index: Int) -> simd_float2 {
        return simd_float2(haltonAt(index, base: 2), haltonAt(index, base: 3))
    }

    // MARK: - Intro camera curves

    /// Pitch curve over t ∈ [0,1]: cinematic → top pole → bottom pole → cinematic.
    /// Uses cosine easing for smooth in/out at every keyframe.
    private func introPitchCurve(t: Double) -> Double {
        let pCinematic: Double = 0.539
        let pTop: Double = 0.05
        let pBot: Double = 0.95
        if t < 0.30 {
            // Default → top
            let s = ease(t / 0.30)
            return pCinematic + (pTop - pCinematic) * s
        } else if t < 0.65 {
            // Top → bottom (slow sweep through equator)
            let s = ease((t - 0.30) / 0.35)
            return pTop + (pBot - pTop) * s
        } else {
            // Bottom → cinematic
            let s = ease((t - 0.65) / 0.35)
            return pBot + (pCinematic - pBot) * s
        }
    }

    /// Slight yaw drift during the intro for parallax — full cycle over the
    /// intro length, ±0.10 around params.yaw.
    private func introYawCurve(t: Double) -> Double {
        let base = Double(params.yaw)
        return base + 0.10 * sin(t * 2.0 * .pi)
    }

    private func ease(_ x: Double) -> Double {
        let c = max(0.0, min(1.0, x))
        return 0.5 - 0.5 * cos(.pi * c)
    }

    private func haltonAt(_ index: Int, base: Int) -> Float {
        var f: Float = 1.0
        var r: Float = 0.0
        var i = index
        while i > 0 {
            f /= Float(base)
            r += f * Float(i % base)
            i /= base
        }
        return r
    }
}
