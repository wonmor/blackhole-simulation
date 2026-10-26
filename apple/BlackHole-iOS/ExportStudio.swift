#if os(iOS)
import SwiftUI
import UIKit
import MetalKit
import Photos
import AVFoundation

/// Pro exports: a supersampled 4K poster and a 360° orbit video, rendered
/// offscreen by `Renderer` at a fixed resolution independent of the screen.
@MainActor
final class ExportStudio: ObservableObject {
    static let shared = ExportStudio()

    enum State: Equatable {
        case idle
        case rendering(label: String, progress: Double)
        case saving
        case done(String)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    weak var renderer: Renderer?
    weak var mtkView: MTKView?
    private var cancelRequested = false

    var isBusy: Bool {
        switch state {
        case .rendering, .saving: return true
        default: return false
        }
    }

    static let posterLongSide = 3840
    static let posterPasses = 16
    static let videoLongSide = 1920
    static let videoSeconds = 12
    static let videoFPS = 30

    private init() {}

    func cancel() { cancelRequested = true }
    func reset() { if !isBusy { state = .idle } }

    /// Output size matching the on-screen aspect ratio, long side `longSide`,
    /// both dimensions even (required by the H.264 encoder).
    private func exportSize(longSide: Int) -> (Int, Int) {
        let ds = mtkView?.drawableSize ?? CGSize(width: 1170, height: 2532)
        let aspect = max(0.2, min(5.0, ds.width / max(ds.height, 1)))
        var w: Int, h: Int
        if aspect >= 1 { w = longSide; h = Int(Double(longSide) / aspect) }
        else { h = longSide; w = Int(Double(longSide) * aspect) }
        return (w & ~1, h & ~1)
    }

    private func photosAuthorized() async -> Bool {
        let s = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        return s == .authorized || s == .limited
    }

    private func begin() {
        cancelRequested = false
        mtkView?.isPaused = true
        UIApplication.shared.isIdleTimerDisabled = true
    }

    private func end() {
        mtkView?.isPaused = false
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: - 4K poster

    func exportPoster() async {
        guard !isBusy, let r = renderer else { state = .failed("The renderer isn't ready yet."); return }
        guard await photosAuthorized() else {
            state = .failed("Photos access is off. Enable it in Settings, BlackHole, Photos.")
            return
        }
        let (w, h) = exportSize(longSide: Self.posterLongSide)
        guard let targets = Renderer.ExportTargets(renderer: r, width: w, height: h) else {
            state = .failed("Not enough GPU memory for a \(w)x\(h) render."); return
        }
        begin(); defer { end() }
        state = .rendering(label: "Ray tracing \(w) x \(h)", progress: 0.1)
        let cam = r.currentExportCamera()
        await r.renderExportFrame(into: targets, camera: cam, raySteps: 500, passes: Self.posterPasses)
        state = .saving
        guard let cg = r.exportImage(from: targets),
              let png = UIImage(cgImage: cg).pngData() else {
            state = .failed("Couldn't encode the image."); return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: png, options: nil)
            }
            state = .done("Saved a \(w) x \(h) poster to Photos.")
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Orbit video

    func exportOrbitVideo() async {
        guard !isBusy, let r = renderer else { state = .failed("The renderer isn't ready yet."); return }
        guard await photosAuthorized() else {
            state = .failed("Photos access is off. Enable it in Settings, BlackHole, Photos.")
            return
        }
        let (w, h) = exportSize(longSide: Self.videoLongSide)
        guard let targets = Renderer.ExportTargets(renderer: r, width: w, height: h) else {
            state = .failed("Not enough GPU memory for a \(w)x\(h) render."); return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlackHole-orbit-\(Int(Date().timeIntervalSince1970)).mp4")
        try? FileManager.default.removeItem(at: url)

        let writer: AVAssetWriter
        do { writer = try AVAssetWriter(outputURL: url, fileType: .mp4) }
        catch { state = .failed(error.localizedDescription); return }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: w,
            AVVideoHeightKey: h,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 16_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: w,
            kCVPixelBufferHeightKey as String: h,
        ])
        guard writer.canAdd(input) else { state = .failed("Video encoder unavailable."); return }
        writer.add(input)
        guard writer.startWriting() else {
            state = .failed(writer.error?.localizedDescription ?? "Video encoder failed to start."); return
        }
        writer.startSession(atSourceTime: .zero)

        begin(); defer { end() }
        let frames = Self.videoSeconds * Self.videoFPS
        let start = r.currentExportCamera()
        let label = "Rendering \(w) x \(h) orbit"
        for i in 0..<frames {
            if cancelRequested {
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: url)
                state = .idle
                return
            }
            var cam = start
            let t = Float(i) / Float(frames)
            cam.yaw = (start.yaw + t).truncatingRemainder(dividingBy: 1.0)
            cam.time = start.time + Float(i) / Float(Self.videoFPS)
            await r.renderExportFrame(into: targets, camera: cam, raySteps: 256, passes: 2)

            while !input.isReadyForMoreMediaData { await Task.yield() }
            guard let pool = adaptor.pixelBufferPool else { break }
            var pbOut: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pbOut)
            guard let pb = pbOut else { continue }
            CVPixelBufferLockBaseAddress(pb, [])
            if let dst = CVPixelBufferGetBaseAddress(pb) {
                let dstStride = CVPixelBufferGetBytesPerRow(pb)
                let src = targets.readback.contents()
                for row in 0..<h {
                    memcpy(dst + row * dstStride, src + row * targets.bytesPerRow, targets.bytesPerRow)
                }
            }
            CVPixelBufferUnlockBaseAddress(pb, [])
            adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: CMTimeScale(Self.videoFPS)))
            state = .rendering(label: label, progress: Double(i + 1) / Double(frames))
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            state = .failed(writer.error?.localizedDescription ?? "Video encoding failed."); return
        }
        state = .saving
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: url, options: nil)
            }
            try? FileManager.default.removeItem(at: url)
            state = .done("Saved a \(Self.videoSeconds)-second \(w) x \(h) orbit video to Photos.")
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

/// Save / export sheet. The screen-frame save is free; the 4K poster and the
/// orbit video are Pro.
struct ExportSheet: View {
    @ObservedObject var subscription: SubscriptionManager
    @ObservedObject var studio = ExportStudio.shared
    /// Free still save (current screen frame) handled by the container.
    var onSaveFrame: () -> Void
    @Environment(\.dismiss) private var dismiss

    private let cyan = Color(red: 0.55, green: 0.95, blue: 1.0)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Save and export")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Exports render offscreen at a fixed resolution with the current settings and camera.")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(8)
                }
                .buttonStyle(.plain)
                .disabled(studio.isBusy)
                .accessibilityLabel("Close")
            }

            option(icon: "square.and.arrow.down", title: "Save screen frame",
                   sub: "What's on screen now, at screen resolution. Free.", pro: false) {
                dismiss()
                onSaveFrame()
            }
            option(icon: "photo", title: "4K poster",
                   sub: "3840 px, 500 ray steps, 16-pass supersampling.", pro: true) {
                Task { await studio.exportPoster() }
            }
            option(icon: "film", title: "Orbit video",
                   sub: "12 s, 1080p, 30 fps, a full 360° fly-around.", pro: true) {
                Task { await studio.exportOrbitVideo() }
            }

            status
            Spacer(minLength: 0)
        }
        .padding(22)
        .background(Color.black.opacity(0.94))
        .colorScheme(.dark)
        .interactiveDismissDisabled(studio.isBusy)
        .onAppear { studio.reset() }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var status: some View {
        switch studio.state {
        case .idle:
            EmptyView()
        case .rendering(let label, let progress):
            VStack(alignment: .leading, spacing: 6) {
                Text(label).font(.system(size: 12, weight: .medium)).foregroundColor(.white.opacity(0.8))
                ProgressView(value: progress).tint(cyan)
                Button("Cancel") { studio.cancel() }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(cyan)
            }
        case .saving:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Saving to Photos…").font(.system(size: 12)).foregroundColor(.white.opacity(0.8))
            }
        case .done(let msg):
            Label(msg, systemImage: "checkmark")
                .font(.system(size: 12, weight: .medium)).foregroundColor(cyan)
        case .failed(let msg):
            Label(msg, systemImage: "exclamationmark.triangle")
                .font(.system(size: 12)).foregroundColor(.orange)
        }
    }

    private func option(icon: String, title: String, sub: String, pro: Bool,
                        action: @escaping () -> Void) -> some View {
        let locked = pro && !subscription.isProUnlocked
        return Button {
            if locked {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    subscription.showPaywall(title)
                }
            } else {
                action()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(cyan)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                        if locked { ProBadge() }
                    }
                    Text(sub).font(.system(size: 11)).foregroundColor(.white.opacity(0.6))
                }
                Spacer()
                Image(systemName: locked ? "lock" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.45))
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(studio.isBusy)
    }
}
#endif
