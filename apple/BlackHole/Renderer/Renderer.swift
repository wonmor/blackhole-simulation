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
final class Renderer: NSObject, MTKViewDelegate {

    // Plumbing
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let bilinearSampler: MTLSamplerState

    // Pipelines
    private let scenePipeline: MTLRenderPipelineState
    private let taaPipeline: MTLRenderPipelineState
    private let brightPipeline: MTLRenderPipelineState
    private let blurHPipeline: MTLRenderPipelineState
    private let blurVPipeline: MTLRenderPipelineState
    private let compositePipeline: MTLRenderPipelineState
    private let copyPipeline: MTLRenderPipelineState

    // Resources
    private var uniformsBuffer: MTLBuffer
    private var sceneRT: MTLTexture?
    private var history: [MTLTexture] = []
    private var historyIdx: Int = 0
    private var bloomBright: MTLTexture?
    private var bloomScratch: MTLTexture?
    private var rtSize: CGSize = .zero

    // State
    private let startTime = CFAbsoluteTimeGetCurrent()
    private var frameIndex: Int32 = 0
    private var historyValid: Bool = false
    private var lastParamsSnapshot: BHUniforms = BHUniforms()
    private var renderScale: Float = 1.0

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

        // Sampler used by every post-processing pass that needs bilinear sampling.
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: samplerDesc) else {
            fatalError("Could not create sampler.")
        }
        self.bilinearSampler = sampler

        // Build pipelines
        self.scenePipeline = Renderer.makePipeline(
            device: device, library: library,
            vertex: "bh_vs", fragment: "bh_fs",
            colorFormat: .rgba16Float, label: "scene")
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
            colorFormat: mtkView.colorPixelFormat, label: "composite")
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

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        rebuildOffscreenTargets(for: size)
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor
        else { return }

        let drawableSize = view.drawableSize
        if drawableSize != rtSize { rebuildOffscreenTargets(for: drawableSize) }
        guard let sceneRT = sceneRT,
              let bloomBright = bloomBright,
              let bloomScratch = bloomScratch,
              history.count == 2 else { return }

        let preset = params.preset
        renderScale = preset.renderScale
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

        // 1. Scene pass -> sceneRT
        renderToTexture(commandBuffer: cb, target: sceneRT, label: "scene") { enc in
            enc.setRenderPipelineState(scenePipeline)
            enc.setVertexBuffer(uniformsBuffer, offset: 0, index: 0)
            enc.setFragmentBuffer(uniformsBuffer, offset: 0, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }

        // 2. TAA pass (or pass-through copy when disabled)
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

        // 3-5. Bloom (skipped on low presets)
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

        // 6. Composite -> drawable
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

    // MARK: - Helpers

    private func renderToTexture(commandBuffer: MTLCommandBuffer,
                                 target: MTLTexture,
                                 label: String,
                                 _ body: (MTLRenderCommandEncoder) -> Void)
    {
        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = target
        desc.colorAttachments[0].loadAction = .dontCare
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
        let scaledW = max(1, Int(Float(size.width)  * params.preset.renderScale))
        let scaledH = max(1, Int(Float(size.height) * params.preset.renderScale))

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
        let renderW = max(1.0, Float(size.width)  * params.preset.renderScale)
        let renderH = max(1.0, Float(size.height) * params.preset.renderScale)

        // Halton(2,3) jitter for sub-pixel TAA sampling.
        let h = halton(index: Int(frameIndex) + 1)
        let jitter = simd_float2((h.x - 0.5), (h.y - 0.5)) * 0.8

        var u = BHUniforms()
        u.resolution         = simd_float2(renderW, renderH)
        u.time               = Float(CFAbsoluteTimeGetCurrent() - startTime)
        u.mass               = params.mass
        u.spin               = params.spin
        u.diskDensity        = params.diskDensity
        u.diskTemp           = params.diskTemp
        u.zoom               = params.zoom
        u.mouse              = simd_float2(params.yaw, params.pitch)
        u.lensingStrength    = params.lensingStrength
        u.diskSize           = params.diskSize
        u.maxRaySteps        = Int32(params.preset.maxRaySteps)
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
