import Foundation
import Metal
import MetalKit
import simd

final class Renderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private var uniformsBuffer: MTLBuffer

    private let startTime = CFAbsoluteTimeGetCurrent()

    var params: BlackHoleParameters

    init(mtkView: MTKView, params: BlackHoleParameters) {
        guard let device = mtkView.device ?? MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device.")
        }
        self.device = device
        mtkView.device = device

        guard let queue = device.makeCommandQueue() else {
            fatalError("Could not create Metal command queue.")
        }
        self.commandQueue = queue

        guard let library = device.makeDefaultLibrary() else {
            fatalError("Could not load default Metal library. Did Shaders.metal compile?")
        }
        guard let vertexFn = library.makeFunction(name: "vs_main"),
              let fragmentFn = library.makeFunction(name: "fs_main") else {
            fatalError("Missing vs_main / fs_main in Metal library.")
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
        descriptor.rasterSampleCount = mtkView.sampleCount

        do {
            self.pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            fatalError("Failed to create render pipeline: \(error)")
        }

        let length = MemoryLayout<BHUniforms>.stride
        guard let buffer = device.makeBuffer(length: length, options: [.storageModeShared]) else {
            fatalError("Could not allocate uniforms buffer.")
        }
        self.uniformsBuffer = buffer

        self.params = params

        super.init()
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Resolution is read from the drawable each frame; nothing to do here.
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else { return }

        updateUniforms(view: view)

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(uniformsBuffer, offset: 0, index: 0)
        encoder.setFragmentBuffer(uniformsBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func updateUniforms(view: MTKView) {
        let size = view.drawableSize
        var u = BHUniforms()
        u.resolution = simd_float2(Float(size.width), Float(size.height))
        u.time = Float(CFAbsoluteTimeGetCurrent() - startTime)
        u.mass = params.mass
        u.spin = params.spin
        u.diskDensity = params.diskDensity
        u.diskTemp = params.diskTemp
        u.zoom = params.zoom
        u.mouse = simd_float2(params.yaw, params.pitch)
        u.lensingStrength = params.lensingStrength
        u.diskSize = params.diskSize
        u.maxRaySteps = Int32(params.maxRaySteps)
        u.debug = params.debug ? 1.0 : 0.0
        u.showRedshift = params.showRedshift ? 1.0 : 0.0
        u._pad0 = 0
        memcpy(uniformsBuffer.contents(), &u, MemoryLayout<BHUniforms>.size)
    }
}
