import Foundation
import UIKit
import CoreGraphics

struct T6TextureConversionReport: Sendable {
    let total: Int
    let succeeded: Int
    let failed: Int
    let warnings: [String]
}

enum T6TextureConverter {
    static func convert(payload: Data, assets: T6ResolvedAssetIndex, destination: URL) throws -> T6TextureConversionReport {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        let records = assets.all(.gfxImage)
        var succeeded = 0
        var warnings: [String] = []

        for (index, record) in records.enumerated() {
            guard let imageOffset = T6AssetResolver.payloadOffset(for: record, payloadCount: payload.count),
                  imageOffset + 36 <= payload.count else {
                warnings.append("GfxImage \(index): serialized pointer is unresolved; texture left as fallback.")
                continue
            }

            // T6 PS3 is 32-bit big-endian. The stable prefix of GfxImage is:
            // texture ptr(4), map/semantic/category/delay(4), picmip/noPicmip/track(4),
            // cardMemory[2](8), width/height/depth(6), level/streaming(2),
            // baseSize(4), pixels ptr(4).
            let width = Int(be16(payload, imageOffset + 20))
            let height = Int(be16(payload, imageOffset + 22))
            let baseSize = Int(be32(payload, imageOffset + 28))
            let pixelsPointer = be32(payload, imageOffset + 32)

            guard width > 0, height > 0, width <= 16_384, height <= 16_384,
                  baseSize > 0, baseSize <= 256 * 1024 * 1024,
                  let pixelOffset = payloadOffset(pixelsPointer, count: payload.count),
                  pixelOffset + baseSize <= payload.count else {
                warnings.append("GfxImage \(index): invalid dimensions/pixel range; texture left as fallback.")
                continue
            }

            let bytes = payload.subdata(in: pixelOffset..<(pixelOffset + baseSize))
            let baseName = String(format: "gfximage_%05d", index)

            if let copied = copyEncodedImageIfPossible(bytes, baseName: baseName, destination: destination) {
                _ = copied
                succeeded += 1
                continue
            }

            if baseSize >= width * height * 4,
               let png = rgbaPNG(bytes.prefix(width * height * 4), width: width, height: height) {
                try png.write(to: destination.appendingPathComponent(baseName + ".png"), options: .atomic)
                succeeded += 1
            } else {
                warnings.append("GfxImage \(index): compressed/streamed PS3 encoding is not safely identifiable from the serialized prefix; texture left as fallback.")
            }
        }

        return T6TextureConversionReport(
            total: records.count,
            succeeded: succeeded,
            failed: max(0, records.count - succeeded),
            warnings: warnings
        )
    }

    private static func copyEncodedImageIfPossible(_ data: Data, baseName: String, destination: URL) -> URL? {
        let signature = [UInt8](data.prefix(12))
        let ext: String?
        if signature.starts(with: [0x89, 0x50, 0x4e, 0x47]) { ext = "png" }
        else if signature.starts(with: [0xff, 0xd8, 0xff]) { ext = "jpg" }
        else { ext = nil }
        guard let ext else { return nil }
        let url = destination.appendingPathComponent(baseName + "." + ext)
        do { try data.write(to: url, options: .atomic); return url } catch { return nil }
    }

    private static func rgbaPNG(_ bytes: Data.SubSequence, width: Int, height: Int) -> Data? {
        let data = Data(bytes)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: info,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else { return nil }
        return UIImage(cgImage: image).pngData()
    }

    private static func payloadOffset(_ pointer: UInt32, count: Int) -> Int? {
        guard pointer != .max, pointer != 0xfffffffe, Int(pointer) >= 0, Int(pointer) < count else { return nil }
        return Int(pointer)
    }

    private static func be16(_ data: Data, _ offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= data.count else { return .max }
        return (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
    }

    private static func be32(_ data: Data, _ offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { return .max }
        return (UInt32(data[offset]) << 24) | (UInt32(data[offset + 1]) << 16) | (UInt32(data[offset + 2]) << 8) | UInt32(data[offset + 3])
    }
}
