#if os(iOS)
import UIKit
import Metal
import MetalKit
import Photos

/// iOS-only utility that grabs the current MTKView frame, converts it to a
/// UIImage, and writes it to the user's Photos library as a still wallpaper.
///
/// True animated/Live wallpapers from third-party apps were removed by Apple
/// in iOS 16, so the canonical path is: save a still PNG → user picks it in
/// Photos → "Use as Wallpaper".
@MainActor
final class WallpaperSaver: ObservableObject {

    static let shared = WallpaperSaver()

    enum Status: Equatable {
        case idle
        case saving
        case saved
        case denied
        case failed(String)
    }

    @Published private(set) var status: Status = .idle

    weak var mtkView: MTKView?

    private init() {}

    func capture() async {
        guard let mtkView = mtkView,
              let device = mtkView.device,
              let queue = device.makeCommandQueue() else {
            status = .failed("Metal view not ready.")
            return
        }
        guard let drawable = mtkView.currentDrawable else {
            status = .failed("No frame to capture yet.")
            return
        }

        status = .saving
        let perm = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard perm == .authorized || perm == .limited else {
            status = .denied
            return
        }

        // Drawable textures are private-storage and framebuffer-only on iOS,
        // so blit into a shared staging texture before reading bytes.
        let src = drawable.texture
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: src.pixelFormat,
            width: src.width, height: src.height,
            mipmapped: false
        )
        desc.storageMode = .shared
        desc.usage = [.shaderRead]
        guard let staging = device.makeTexture(descriptor: desc),
              let cb = queue.makeCommandBuffer(),
              let blit = cb.makeBlitCommandEncoder() else {
            status = .failed("Couldn't allocate staging texture.")
            return
        }
        blit.copy(from: src,
                  sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: src.width, height: src.height, depth: 1),
                  to: staging,
                  destinationSlice: 0, destinationLevel: 0,
                  destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()

        guard let image = makeUIImage(from: staging) else {
            status = .failed("Couldn't decode frame.")
            return
        }
        do {
            try await saveToPhotos(image: image)
            status = .saved
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func reset() { status = .idle }

    // MARK: - Helpers

    private func makeUIImage(from texture: MTLTexture) -> UIImage? {
        let width = texture.width
        let height = texture.height
        let bytesPerRow = 4 * width
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        let region = MTLRegionMake2D(0, 0, width, height)
        texture.getBytes(&bytes,
                         bytesPerRow: bytesPerRow,
                         from: region, mipmapLevel: 0)

        // BGRA → RGBA swizzle (drawable is bgra8Unorm).
        for i in stride(from: 0, to: bytes.count, by: 4) {
            let b = bytes[i]
            let r = bytes[i + 2]
            bytes[i] = r
            bytes[i + 2] = b
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo: CGBitmapInfo = [
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            .byteOrder32Big
        ]
        return bytes.withUnsafeMutableBufferPointer { buf -> UIImage? in
            guard let ctx = CGContext(
                data: buf.baseAddress,
                width: width, height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            ), let cg = ctx.makeImage() else { return nil }
            return UIImage(cgImage: cg)
        }
    }

    private func saveToPhotos(image: UIImage) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }) { success, error in
                if let error = error {
                    cont.resume(throwing: error)
                } else if success {
                    cont.resume(returning: ())
                } else {
                    cont.resume(throwing: NSError(
                        domain: "Wallpaper", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Photos write failed."]
                    ))
                }
            }
        }
    }
}
#endif
