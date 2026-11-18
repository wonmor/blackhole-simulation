import Foundation
import Metal
import CompositorServices
import ARKit
import SwiftUI
import Spatial
import simd
import QuartzCore

/// Stereo-renders the Kerr black hole for Apple Vision Pro.
///
/// Per eye: pass A integrates geodesics through the black hole's bounding sphere
/// into a reduced-resolution offscreen target; pass B upsamples it into the
/// Compositor drawable with the system foveation map, adds the lensed sky in
/// full immersion and writes depth. A GPU-time governor scales pass A's
/// resolution and step budget so the frame stays inside the 90 Hz budget.
final class ImmersiveRenderer: @unchecked Sendable {

    private let layerRenderer: LayerRenderer
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let library: MTLLibrary
    private var marchPipeline: MTLRenderPipelineState?
    private var compositePipeline: MTLRenderPipelineState?
    private let depthState: MTLDepthStencilState

    private let arSession = ARKitSession()
    private let worldTracking = WorldTrackingProvider()

    private weak var params: BlackHoleParameters?
    private let control = ImmersiveController.shared
    private let startTime = CACurrentMediaTime()
    private let frameSemaphore = DispatchSemaphore(value: 3)

    // Offscreen pass-A targets, one pair per view.
    private var colorTargets: [MTLTexture] = []
    private var dirTargets: [MTLTexture] = []
    private let maxScale: Float = 1.0

    // Governor (GPU milliseconds, exponential moving average).
    private var gpuMs: Double = 6
    private var scale: Float = 0.7
    private var stepFactor: Float = 1.0
    private let gpuLock = NSLock()
    private var lastGpu: Double = 6

    // FPS bookkeeping.
    private var fpsFrames = 0
    private var fpsStart = CACurrentMediaTime()
    private var fpsLog: [Double] = []
    private let logFPS = UserDefaults.standard.bool(forKey: "bhFpsLog")

    // Placement of the black hole in the immersive space.
    private var center = SIMD3<Float>(0, 1.35, -1.4)
    private var forward = SIMD3<Float>(0, 0, -1)
    private var placed = false

    // Spatial gesture tracking (main actor).
    private var touches: [SpatialEventCollection.Event.ID: SIMD3<Float>] = [:]
    private var pinchStartDist: Float = 0
    private var pinchStartSize: Float = 1

    init(layerRenderer: LayerRenderer, params: BlackHoleParameters) {
        self.layerRenderer = layerRenderer
        self.params = params
        self.device = layerRenderer.device
        self.queue = device.makeCommandQueue()!
        self.library = device.makeDefaultLibrary()!
        let ds = MTLDepthStencilDescriptor()
        ds.depthCompareFunction = .always
        ds.isDepthWriteEnabled = true
        self.depthState = device.makeDepthStencilState(descriptor: ds)!
        Task { try? await arSession.run([worldTracking]) }
    }

    // MARK: - Gestures

    /// Pinch and drag orbits the black hole; pinching with both hands and
    /// pulling them apart scales it. Called on the main actor.
    @MainActor
    func handle(_ events: SpatialEventCollection) {
        for e in events {
            let p = e.inputDevicePose?.pose3D.position ?? e.location3D
            var pos = SIMD3<Float>(Float(p.x), Float(p.y), Float(p.z))
            // Compositor events arrive in metres; guard against point units.
            if simd_length(pos) > 30 { pos /= 1360 }
            switch e.phase {
            case .active:
                if let prev = touches[e.id] {
                    if touches.count == 1 {
                        let d = pos - prev
                        let right = simd_normalize(simd_cross(forward, SIMD3<Float>(0, 1, 0)))
                        control.orbit(dYaw: simd_dot(d, right) * 4.0, dTilt: -d.y * 4.0)
                    }
                } else if touches.count == 1 {
                    // Second hand joined: start a two-hand magnify.
                    let other = touches.values.first!
                    pinchStartDist = max(simd_distance(other, pos), 0.02)
                    pinchStartSize = control.size
                }
                touches[e.id] = pos
                if touches.count == 2 {
                    let v = Array(touches.values)
                    let dist = simd_distance(v[0], v[1])
                    control.size = pinchStartSize * dist / pinchStartDist
                }
            case .ended, .cancelled:
                touches[e.id] = nil
            @unknown default:
                touches[e.id] = nil
            }
        }
    }

    // MARK: - Pipelines

    private func buildPipelines(_ drawable: LayerRenderer.Drawable) {
        guard compositePipeline == nil else { return }
        let vs = library.makeFunction(name: "imm_vs")

        let a = MTLRenderPipelineDescriptor()
        a.label = "BH march"
        a.vertexFunction = vs
        a.fragmentFunction = library.makeFunction(name: "bh_march_fs")
        a.colorAttachments[0].pixelFormat = .rgba16Float
        a.colorAttachments[1].pixelFormat = .rgba16Float
        marchPipeline = try? device.makeRenderPipelineState(descriptor: a)

        let b = MTLRenderPipelineDescriptor()
        b.label = "BH composite"
        b.vertexFunction = vs
        b.fragmentFunction = library.makeFunction(name: "bh_composite_fs")
        b.colorAttachments[0].pixelFormat = drawable.colorTextures[0].pixelFormat
        b.depthAttachmentPixelFormat = drawable.depthTextures[0].pixelFormat
        b.rasterSampleCount = drawable.colorTextures[0].sampleCount
        b.maxVertexAmplificationCount = layerRenderer.properties.viewCount
        do { compositePipeline = try device.makeRenderPipelineState(descriptor: b) }
        catch { NSLog("BH composite pipeline failed: \(error)") }
    }

    private func ensureTargets(count: Int, size: MTLSize) {
        let w = Int((Float(size.width) * maxScale).rounded(.up))
        let h = Int((Float(size.height) * maxScale).rounded(.up))
        if colorTargets.count == count, let t = colorTargets.first, t.width == w, t.height == h { return }
        colorTargets = []; dirTargets = []
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: w, height: h, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        for _ in 0..<count {
            colorTargets.append(device.makeTexture(descriptor: d)!)
            dirTargets.append(device.makeTexture(descriptor: d)!)
        }
    }

    // MARK: - Loop

    func startRenderLoop() {
        Task { @MainActor in
            layerRenderer.onSpatialEvent = { [weak self] events in self?.handle(events) }
        }
        control.setOpen(true)
        let thread = Thread { [self] in
            self.renderLoop()
        }
        thread.name = "BlackHole render"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    private func renderLoop() {
        while true {
            switch layerRenderer.state {
            case .paused:
                layerRenderer.waitUntilRunning()
            case .running:
                autoreleasepool {
                    if let frame = layerRenderer.queryNextFrame() { renderFrame(frame) }
                }
            case .invalidated:
                control.setOpen(false)
                return
            @unknown default:
                continue
            }
        }
    }

    private func renderFrame(_ frame: LayerRenderer.Frame) {
        frame.startUpdate()
        let snap = control.takeSnapshot()
        frame.endUpdate()

        guard let timing = frame.predictTiming() else { return }
        LayerRenderer.Clock().wait(until: timing.optimalInputTime)
        frameSemaphore.wait()

        frame.startSubmission()
        guard let drawable = frame.queryDrawable() else {
            frame.endSubmission(); frameSemaphore.signal(); return
        }
        buildPipelines(drawable)

        let dur = LayerRenderer.Clock.Instant.epoch.duration(to: timing.presentationTime)
        let t = Double(dur.components.seconds) + Double(dur.components.attoseconds) * 1e-18
        let anchor = worldTracking.queryDeviceAnchor(atTimestamp: t)
        drawable.deviceAnchor = anchor
        let head = anchor?.originFromAnchorTransform ?? matrix_identity_float4x4

        if (!placed && anchor != nil) || snap.recenter {
            place(head: anchor != nil ? head : nil)
        }

        guard let cb = queue.makeCommandBuffer(),
              let march = marchPipeline, let comp = compositePipeline else {
            frame.endSubmission(); frameSemaphore.signal(); return
        }

        let viewCount = drawable.views.count
        let screen: MTLSize = drawable.rasterizationRateMaps.first?.screenSize
            ?? MTLSize(width: drawable.colorTextures[0].width, height: drawable.colorTextures[0].height, depth: 1)
        ensureTargets(count: viewCount, size: screen)

        var scene = makeScene(snap)
        let s = scale
        let vpW = Double(Float(screen.width) * s).rounded(), vpH = Double(Float(screen.height) * s).rounded()
        let texW = Double(colorTargets[0].width), texH = Double(colorTargets[0].height)
        let encodeGamma: Float = Self.needsGamma(drawable.colorTextures[0].pixelFormat) ? 1 : 0

        for (i, view) in drawable.views.enumerated() {
            let proj = drawable.computeProjection(convention: .rightUpBack, viewIndex: i)
            let worldFromView = head * view.transform
            let viewFromWorld = worldFromView.inverse
            let c = proj * viewFromWorld * SIMD4<Float>(center, 1)
            let centreDepth = c.w > 0 ? min(max(c.z / c.w, 0), 1) : 0

            var eye = ImmEye(viewFromClip: proj.inverse, worldFromView: worldFromView,
                             misc: SIMD4<Float>(centreDepth, encodeGamma, Float(vpW / texW), Float(vpH / texH)))

            // Pass A
            let pa = MTLRenderPassDescriptor()
            pa.colorAttachments[0].texture = colorTargets[i]
            pa.colorAttachments[0].loadAction = .clear
            pa.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            pa.colorAttachments[0].storeAction = .store
            pa.colorAttachments[1].texture = dirTargets[i]
            pa.colorAttachments[1].loadAction = .clear
            pa.colorAttachments[1].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            pa.colorAttachments[1].storeAction = .store
            if let enc = cb.makeRenderCommandEncoder(descriptor: pa) {
                enc.label = "march eye \(i)"
                enc.setRenderPipelineState(march)
                enc.setViewport(MTLViewport(originX: 0, originY: 0, width: vpW, height: vpH, znear: 0, zfar: 1))
                enc.setFragmentBytes(&eye, length: MemoryLayout<ImmEye>.stride, index: 0)
                enc.setFragmentBytes(&scene, length: MemoryLayout<ImmScene>.stride, index: 1)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                enc.endEncoding()
            }

            // Pass B
            let pb = MTLRenderPassDescriptor()
            pb.colorAttachments[0].texture = drawable.colorTextures.count > i ? drawable.colorTextures[i] : drawable.colorTextures[0]
            pb.colorAttachments[0].slice = view.textureMap.sliceIndex
            pb.colorAttachments[0].loadAction = .clear
            pb.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            pb.colorAttachments[0].storeAction = .store
            pb.depthAttachment.texture = drawable.depthTextures.count > i ? drawable.depthTextures[i] : drawable.depthTextures[0]
            pb.depthAttachment.slice = view.textureMap.sliceIndex
            pb.depthAttachment.loadAction = .clear
            pb.depthAttachment.clearDepth = 0
            pb.depthAttachment.storeAction = .store
            if i < drawable.rasterizationRateMaps.count {
                pb.rasterizationRateMap = drawable.rasterizationRateMaps[i]
            }
            if let enc = cb.makeRenderCommandEncoder(descriptor: pb) {
                enc.label = "composite eye \(i)"
                enc.setRenderPipelineState(comp)
                enc.setDepthStencilState(depthState)
                enc.setViewport(view.textureMap.viewport)
                enc.setFragmentBytes(&eye, length: MemoryLayout<ImmEye>.stride, index: 0)
                enc.setFragmentBytes(&scene, length: MemoryLayout<ImmScene>.stride, index: 1)
                enc.setFragmentTexture(colorTargets[i], index: 0)
                enc.setFragmentTexture(dirTargets[i], index: 1)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                enc.endEncoding()
            }
        }

        let sem = frameSemaphore
        cb.addCompletedHandler { [weak self] buf in
            let ms = (buf.gpuEndTime - buf.gpuStartTime) * 1000
            if let self, ms > 0 {
                self.gpuLock.lock(); self.lastGpu = ms; self.gpuLock.unlock()
            }
            sem.signal()
        }
        drawable.encodePresent(commandBuffer: cb)
        cb.commit()
        frame.endSubmission()

        govern()
    }

    // MARK: - Placement and scene

    private func place(head: simd_float4x4?) {
        guard let head else {
            center = SIMD3<Float>(0, 1.35, -1.4); forward = SIMD3<Float>(0, 0, -1)
            placed = true; return
        }
        let pos = SIMD3<Float>(head.columns.3.x, head.columns.3.y, head.columns.3.z)
        var f = -SIMD3<Float>(head.columns.2.x, 0, head.columns.2.z)
        if simd_length(f) < 1e-3 { f = SIMD3<Float>(0, 0, -1) }
        f = simd_normalize(f)
        forward = f
        center = pos + f * 1.35 + SIMD3<Float>(0, -0.08, 0)
        placed = true
    }

    private func makeScene(_ snap: ImmersiveController.Snapshot) -> ImmScene {
        let p = params
        let spin = max(-0.9999, min(0.9999, p?.spin ?? 0.5))
        // The shader's lensing model gives a shadow of about 7.5 M x lensing
        // strength (5.2 M, the Schwarzschild value, at the default 0.7). Keep the
        // disk reaching well past it so strong-lensing scenarios still show a disk.
        let lensing = (p?.enableLensing ?? true) ? (p?.lensingStrength ?? 0.7) : 0
        let diskEff = max(8, min(30, (p?.diskSize ?? 50) * 0.4), 7.5 * max(lensing, 0.5) * 2.4)
        let R = max(diskEff * 1.2, 16)
        // Disk's outer edge is 0.55 m from the centre at size 1.
        let unitsPerMetre = diskEff / (0.55 * snap.size)

        let pitch = p?.pitch ?? 0.539
        let tilt = (pitch - 0.5) * .pi + snap.tilt
        let f = forward
        let right = simd_normalize(simd_cross(f, SIMD3<Float>(0, 1, 0)))
        let back = -f
        let basis = simd_float4x4(SIMD4<Float>(right, 0), SIMD4<Float>(0, 1, 0, 0), SIMD4<Float>(back, 0), SIMD4<Float>(center, 1))
        let worldFromBH = basis * Self.rotX(tilt) * Self.rotY(snap.yaw)

        var flags: UInt32 = 0
        if p?.enableLensing ?? true { flags |= 1 }
        if p?.enableDisk ?? true { flags |= 2 }
        if p?.enableDoppler ?? true { flags |= 4 }
        if p?.enablePhotonGlow ?? true { flags |= 8 }
        if p?.enableStars ?? true { flags |= 16 }
        if p?.enableJets ?? false { flags |= 32 }

        let time = Float(CACurrentMediaTime() - startTime)
        let steps = Float(Self.steps(for: p?.preset ?? .high)) * stepFactor

        return ImmScene(
            bhFromWorld: worldFromBH.inverse,
            worldFromBH: worldFromBH,
            a: SIMD4<Float>(unitsPerMetre, 1.0, spin, R),
            b: SIMD4<Float>(time, time * max(0, p?.diskSpeed ?? 1), p?.lensingStrength ?? 0.7, p?.frameDragStrength ?? 2),
            c: SIMD4<Float>(p?.diskDensity ?? 4, p?.diskTemp ?? 9500, diskEff, p?.diskScaleHeight ?? 0.2),
            d: SIMD4<Float>(max(32, steps), snap.mode == .space ? 1 : 0, Float(flags), 1.0))
    }

    /// Geodesic step budget per quality preset (Ultra and Cinematic are Pro).
    static func steps(for preset: QualityPreset) -> Int {
        switch preset {
        case .low: return 110
        case .medium: return 140
        case .high: return 180
        case .ultra: return 240
        case .cinematic: return 320
        }
    }

    /// Upper bound of pass A's resolution per preset.
    static func maxScale(for preset: QualityPreset) -> Float {
        switch preset {
        case .low: return 0.55
        case .medium: return 0.65
        case .high: return 0.75
        case .ultra: return 0.85
        case .cinematic: return 1.0
        }
    }

    /// Keeps GPU time per frame under ~8.5 ms (90 Hz leaves 11.1 ms).
    private func govern() {
        gpuLock.lock(); let ms = lastGpu; gpuLock.unlock()
        gpuMs = gpuMs * 0.9 + ms * 0.1
        let cap = Self.maxScale(for: params?.preset ?? .high)
        if gpuMs > 8.5 {
            if scale > 0.42 { scale = max(0.42, scale * 0.97) }
            else { stepFactor = max(0.55, stepFactor * 0.97) }
        } else if gpuMs < 6.0 {
            if stepFactor < 1 { stepFactor = min(1, stepFactor * 1.02) }
            else { scale = min(cap, scale * 1.01) }
        }
        scale = min(scale, cap)

        fpsFrames += 1
        let now = CACurrentMediaTime()
        if now - fpsStart >= 1 {
            let fps = Double(fpsFrames) / (now - fpsStart)
            fpsFrames = 0; fpsStart = now
            control.publish(fps: fps, scale: scale)
            if logFPS {
                fpsLog.append(fps)
                Self.writeFPSLog(fpsLog, gpuMs: gpuMs, scale: scale, steps: stepFactor)
            }
        }
    }

    private static func writeFPSLog(_ log: [Double], gpuMs: Double, scale: Float, steps: Float) {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let sorted = log.sorted()
        let avg = log.reduce(0, +) / Double(max(log.count, 1))
        let p5 = sorted.isEmpty ? 0 : sorted[Int(Double(sorted.count - 1) * 0.05)]
        let obj: [String: Any] = ["seconds": log.count, "avg": avg, "p5": p5, "gpuMsEMA": gpuMs,
                                  "passAScale": scale, "stepFactor": steps]
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: dir.appendingPathComponent("fps.json"))
        }
    }

    private static func needsGamma(_ f: MTLPixelFormat) -> Bool {
        switch f {
        case .bgra8Unorm, .rgba8Unorm, .bgr10a2Unorm, .rgb10a2Unorm: return true
        default: return false
        }
    }

    private static func rotX(_ a: Float) -> simd_float4x4 {
        let c = cos(a), s = sin(a)
        return simd_float4x4(SIMD4<Float>(1, 0, 0, 0), SIMD4<Float>(0, c, s, 0), SIMD4<Float>(0, -s, c, 0), SIMD4<Float>(0, 0, 0, 1))
    }

    private static func rotY(_ a: Float) -> simd_float4x4 {
        let c = cos(a), s = sin(a)
        return simd_float4x4(SIMD4<Float>(c, 0, -s, 0), SIMD4<Float>(0, 1, 0, 0), SIMD4<Float>(s, 0, c, 0), SIMD4<Float>(0, 0, 0, 1))
    }
}

// MARK: - Shader layouts (match ImmersiveScene.metal)

struct ImmEye {
    var viewFromClip: simd_float4x4
    var worldFromView: simd_float4x4
    var misc: SIMD4<Float>
}

struct ImmScene {
    var bhFromWorld: simd_float4x4
    var worldFromBH: simd_float4x4
    var a: SIMD4<Float>
    var b: SIMD4<Float>
    var c: SIMD4<Float>
    var d: SIMD4<Float>
}
