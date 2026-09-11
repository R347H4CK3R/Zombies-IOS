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
                  imageOffset + 40 <= payload.count else {
                warnings.append("GfxImage \(index): serialized pointer is unresolved; texture left as fallback.")
                continue
            }

            // T6 is a 32-bit target. OpenAssetTools' T6 layout gives:
            // 0x00 GfxTexture/loadDef pointer, 0x04 MapType,
            // 0x08 semantic, 0x09 category, 0x0A delayLoadPixels,
            // 0x0B Picmip[2], 0x0D noPicmip, 0x0E track, 0x0F padding,
            // 0x10 CardMemory[2], 0x18 width, 0x1A height, 0x1C depth,
            // 0x1E levelCount, 0x1F streaming, 0x20 baseSize, 0x24 pixels pointer.
            let width = Int(be16(payload, imageOffset + 0x18))
            let height = Int(be16(payload, imageOffset + 0x1A))
            guard width > 0, height > 0, width <= 16_384, height <= 16_384 else {
                warnings.append("GfxImage \(index): invalid dimensions \(width)x\(height); texture left as fallback.")
                continue
            }

            let baseName = String(format: "gfximage_%05d", index)
            var converted = false

            // Preferred path: the GfxTexture union points at a GfxImageLoadDef.
            // T6 loadDef = levelCount:u8, flags:u8, pad[2], format:i32,
            // resourceSize:i32, data[]. The format is DXGI on T6.
            let loadDefPointer = be32(payload, imageOffset)
            if let loadDefOffset = payloadOffset(loadDefPointer, count: payload.count),
               loadDefOffset + 12 <= payload.count {
                let format = Int(be32(payload, loadDefOffset + 4))
                let resourceSize = Int(be32(payload, loadDefOffset + 8))
                if resourceSize > 0,
                   resourceSize <= 256 * 1024 * 1024,
                   loadDefOffset + 12 + resourceSize <= payload.count {
                    let textureBytes = payload.subdata(in: (loadDefOffset + 12)..<(loadDefOffset + 12 + resourceSize))
                    if let rgba = decodeDXGI(format: format, bytes: textureBytes, width: width, height: height),
                       let png = rgbaPNG(rgba[...], width: width, height: height) {
                        try png.write(to: destination.appendingPathComponent(baseName + ".png"), options: .atomic)
                        converted = true
                    } else if let copied = copyEncodedImageIfPossible(textureBytes, baseName: baseName, destination: destination) {
                        _ = copied
                        converted = true
                    } else if isKnownDXGI(format) {
                        warnings.append("GfxImage \(index): DXGI \(format) payload could not be decoded safely.")
                    }
                }
            }

            // Some PS3 zones expose a direct pixel pointer instead of a usable
            // loadDef. This path handles pre-decoded RGBA and encoded PNG/JPEG data.
            if !converted {
                let baseSize = Int(be32(payload, imageOffset + 0x20))
                let pixelsPointer = be32(payload, imageOffset + 0x24)
                if baseSize > 0,
                   baseSize <= 256 * 1024 * 1024,
                   let pixelOffset = payloadOffset(pixelsPointer, count: payload.count),
                   pixelOffset + baseSize <= payload.count {
                    let bytes = payload.subdata(in: pixelOffset..<(pixelOffset + baseSize))
                    if let copied = copyEncodedImageIfPossible(bytes, baseName: baseName, destination: destination) {
                        _ = copied
                        converted = true
                    } else if baseSize >= width * height * 4,
                              let png = rgbaPNG(bytes.prefix(width * height * 4), width: width, height: height) {
                        try png.write(to: destination.appendingPathComponent(baseName + ".png"), options: .atomic)
                        converted = true
                    }
                }
            }

            if converted {
                succeeded += 1
            } else {
                warnings.append("GfxImage \(index): no supported resident texture payload was resolved; renderer fallback retained.")
            }
        }

        return T6TextureConversionReport(
            total: records.count,
            succeeded: succeeded,
            failed: max(0, records.count - succeeded),
            warnings: warnings
        )
    }

    // MARK: - T6/DXGI decoding

    private static func isKnownDXGI(_ format: Int) -> Bool {
        [28, 29, 71, 72, 74, 75, 77, 78, 80, 81, 83, 84, 87, 91].contains(format)
    }

    private static func decodeDXGI(format: Int, bytes: Data, width: Int, height: Int) -> Data? {
        switch format {
        case 28, 29: // R8G8B8A8_UNORM / SRGB
            guard bytes.count >= width * height * 4 else { return nil }
            return Data(bytes.prefix(width * height * 4))
        case 87, 91: // B8G8R8A8_UNORM / SRGB
            guard bytes.count >= width * height * 4 else { return nil }
            var rgba = Data(count: width * height * 4)
            for pixel in 0..<(width * height) {
                let src = pixel * 4
                rgba[src] = bytes[src + 2]
                rgba[src + 1] = bytes[src + 1]
                rgba[src + 2] = bytes[src]
                rgba[src + 3] = bytes[src + 3]
            }
            return rgba
        case 71, 72: return decodeBC1(bytes, width: width, height: height)
        case 74, 75: return decodeBC2(bytes, width: width, height: height)
        case 77, 78: return decodeBC3(bytes, width: width, height: height)
        case 80, 81: return decodeBC4(bytes, width: width, height: height)
        case 83, 84: return decodeBC5(bytes, width: width, height: height)
        default: return nil
        }
    }

    private static func decodeBC1(_ data: Data, width: Int, height: Int) -> Data? {
        decodeBlocks(data, width: width, height: height, bytesPerBlock: 8) { block in
            decodeColorBlock(block, offset: 0, allowTransparent: true)
        }
    }

    private static func decodeBC2(_ data: Data, width: Int, height: Int) -> Data? {
        decodeBlocks(data, width: width, height: height, bytesPerBlock: 16) { block in
            var colors = decodeColorBlock(block, offset: 8, allowTransparent: false)
            var alphaBits: UInt64 = 0
            for i in 0..<8 { alphaBits |= UInt64(block[i]) << UInt64(i * 8) }
            for i in 0..<16 {
                let nibble = UInt8((alphaBits >> UInt64(i * 4)) & 0xF)
                colors[i * 4 + 3] = nibble &* 17
            }
            return colors
        }
    }

    private static func decodeBC3(_ data: Data, width: Int, height: Int) -> Data? {
        decodeBlocks(data, width: width, height: height, bytesPerBlock: 16) { block in
            var colors = decodeColorBlock(block, offset: 8, allowTransparent: false)
            let alpha = decodeAlphaBlock(block, offset: 0)
            for i in 0..<16 { colors[i * 4 + 3] = alpha[i] }
            return colors
        }
    }

    private static func decodeBC4(_ data: Data, width: Int, height: Int) -> Data? {
        decodeBlocks(data, width: width, height: height, bytesPerBlock: 8) { block in
            let channel = decodeAlphaBlock(block, offset: 0)
            var rgba = [UInt8](repeating: 255, count: 64)
            for i in 0..<16 {
                rgba[i * 4] = channel[i]
                rgba[i * 4 + 1] = channel[i]
                rgba[i * 4 + 2] = channel[i]
            }
            return rgba
        }
    }

    private static func decodeBC5(_ data: Data, width: Int, height: Int) -> Data? {
        decodeBlocks(data, width: width, height: height, bytesPerBlock: 16) { block in
            let red = decodeAlphaBlock(block, offset: 0)
            let green = decodeAlphaBlock(block, offset: 8)
            var rgba = [UInt8](repeating: 255, count: 64)
            for i in 0..<16 {
                let x = Float(red[i]) / 127.5 - 1
                let y = Float(green[i]) / 127.5 - 1
                let z = sqrt(max(0, 1 - x * x - y * y))
                rgba[i * 4] = red[i]
                rgba[i * 4 + 1] = green[i]
                rgba[i * 4 + 2] = UInt8(max(0, min(255, Int((z * 0.5 + 0.5) * 255))))
            }
            return rgba
        }
    }

    private static func decodeBlocks(
        _ data: Data,
        width: Int,
        height: Int,
        bytesPerBlock: Int,
        decoder: ([UInt8]) -> [UInt8]
    ) -> Data? {
        let blocksX = max(1, (width + 3) / 4)
        let blocksY = max(1, (height + 3) / 4)
        let required = blocksX * blocksY * bytesPerBlock
        guard data.count >= required else { return nil }
        var output = Data(count: width * height * 4)
        var cursor = 0
        for by in 0..<blocksY {
            for bx in 0..<blocksX {
                let block = [UInt8](data[cursor..<(cursor + bytesPerBlock)])
                cursor += bytesPerBlock
                let pixels = decoder(block)
                guard pixels.count == 64 else { return nil }
                for py in 0..<4 {
                    for px in 0..<4 {
                        let x = bx * 4 + px, y = by * 4 + py
                        guard x < width, y < height else { continue }
                        let src = (py * 4 + px) * 4
                        let dst = (y * width + x) * 4
                        output[dst] = pixels[src]
                        output[dst + 1] = pixels[src + 1]
                        output[dst + 2] = pixels[src + 2]
                        output[dst + 3] = pixels[src + 3]
                    }
                }
            }
        }
        return output
    }

    private static func decodeColorBlock(_ block: [UInt8], offset: Int, allowTransparent: Bool) -> [UInt8] {
        let c0 = UInt16(block[offset]) | (UInt16(block[offset + 1]) << 8)
        let c1 = UInt16(block[offset + 2]) | (UInt16(block[offset + 3]) << 8)
        let p0 = rgb565(c0), p1 = rgb565(c1)
        var palette = [[UInt8]]()
        palette.append([p0.0, p0.1, p0.2, 255])
        palette.append([p1.0, p1.1, p1.2, 255])
        if c0 > c1 || !allowTransparent {
            palette.append([mix(p0.0, p1.0, 2, 1, 3), mix(p0.1, p1.1, 2, 1, 3), mix(p0.2, p1.2, 2, 1, 3), 255])
            palette.append([mix(p0.0, p1.0, 1, 2, 3), mix(p0.1, p1.1, 1, 2, 3), mix(p0.2, p1.2, 1, 2, 3), 255])
        } else {
            palette.append([mix(p0.0, p1.0, 1, 1, 2), mix(p0.1, p1.1, 1, 1, 2), mix(p0.2, p1.2, 1, 1, 2), 255])
            palette.append([0, 0, 0, 0])
        }
        var bits: UInt32 = 0
        for i in 0..<4 { bits |= UInt32(block[offset + 4 + i]) << UInt32(i * 8) }
        var rgba = [UInt8](repeating: 0, count: 64)
        for i in 0..<16 {
            let code = Int((bits >> UInt32(i * 2)) & 3)
            for c in 0..<4 { rgba[i * 4 + c] = palette[code][c] }
        }
        return rgba
    }

    private static func decodeAlphaBlock(_ block: [UInt8], offset: Int) -> [UInt8] {
        let a0 = block[offset], a1 = block[offset + 1]
        var palette = [UInt8](repeating: 0, count: 8)
        palette[0] = a0; palette[1] = a1
        if a0 > a1 {
            for i in 1...6 {
                palette[i + 1] = UInt8((Int(7 - i) * Int(a0) + i * Int(a1)) / 7)
            }
        } else {
            for i in 1...4 {
                palette[i + 1] = UInt8((Int(5 - i) * Int(a0) + i * Int(a1)) / 5)
            }
            palette[6] = 0; palette[7] = 255
        }
        var bits: UInt64 = 0
        for i in 0..<6 { bits |= UInt64(block[offset + 2 + i]) << UInt64(i * 8) }
        return (0..<16).map { palette[Int((bits >> UInt64($0 * 3)) & 7)] }
    }

    private static func rgb565(_ value: UInt16) -> (UInt8, UInt8, UInt8) {
        let r = UInt8((value >> 11) & 31)
        let g = UInt8((value >> 5) & 63)
        let b = UInt8(value & 31)
        return (
            UInt8((Int(r) * 255 + 15) / 31),
            UInt8((Int(g) * 255 + 31) / 63),
            UInt8((Int(b) * 255 + 15) / 31)
        )
    }

    private static func mix(_ a: UInt8, _ b: UInt8, _ aw: Int, _ bw: Int, _ divisor: Int) -> UInt8 {
        UInt8((Int(a) * aw + Int(b) * bw) / divisor)
    }

    // MARK: - Image output and endian helpers

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
