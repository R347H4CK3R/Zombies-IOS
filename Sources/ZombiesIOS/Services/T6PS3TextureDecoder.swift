import Foundation

struct T6PS3TextureDecoder {
    enum DecodeError: LocalizedError, Equatable {
        case headerTooSmall
        case invalidDimensions(width: Int, height: Int, depth: Int)
        case invalidResourceSize(Int)
        case truncatedResource(expected: Int, available: Int)
        case unsupportedFormat(Int32)

        var errorDescription: String? {
            switch self {
            case .headerTooSmall:
                return "T6 GfxImageLoadDef header is truncated."
            case .invalidDimensions(let width, let height, let depth):
                return "T6 image has invalid dimensions \(width)x\(height)x\(depth)."
            case .invalidResourceSize(let size):
                return "T6 image has invalid resource size \(size)."
            case .truncatedResource(let expected, let available):
                return "T6 image resource requires \(expected) bytes but only \(available) are available."
            case .unsupportedFormat(let format):
                return "T6 image uses unsupported DXGI format \(format)."
            }
        }
    }

    // T6 GfxImageLoadDef (32-bit layout):
    // u8 levelCount, u8 flags, u16 dimensions[3], i32 format,
    // i32 resourceSize, followed immediately by resource bytes.
    private static let headerSize = 16
    private static let dxgiR8G8B8A8Unorm: Int32 = 28
    private static let dxgiBC1Unorm: Int32 = 71

    func decode(imageID: T6AssetID, loadDefData: Data) throws -> T6DecodedTexture {
        guard loadDefData.count >= Self.headerSize else { throw DecodeError.headerTooSmall }

        let mipCount = max(1, Int(loadDefData[0]))
        let width = Int(le16(loadDefData, 2))
        let height = Int(le16(loadDefData, 4))
        let depth = Int(le16(loadDefData, 6))
        let format = Int32(bitPattern: le32(loadDefData, 8))
        let resourceSize = Int(Int32(bitPattern: le32(loadDefData, 12)))

        guard width > 0, height > 0, depth > 0,
              width <= 16_384, height <= 16_384, depth <= 2_048 else {
            throw DecodeError.invalidDimensions(width: width, height: height, depth: depth)
        }
        guard resourceSize > 0 else { throw DecodeError.invalidResourceSize(resourceSize) }
        let available = loadDefData.count - Self.headerSize
        guard resourceSize <= available else {
            throw DecodeError.truncatedResource(expected: resourceSize, available: available)
        }

        let resource = loadDefData.subdata(in: Self.headerSize..<(Self.headerSize + resourceSize))
        switch format {
        case Self.dxgiR8G8B8A8Unorm:
            let firstMipBytes = width * height * depth * 4
            guard firstMipBytes <= resource.count else {
                throw DecodeError.truncatedResource(expected: firstMipBytes, available: resource.count)
            }
            let rgba = resource.prefix(firstMipBytes)
            return T6DecodedTexture(
                imageID: imageID,
                width: width,
                height: height,
                depth: depth,
                mipCount: mipCount,
                format: .rgba8Unorm,
                hasAlpha: stride(from: 3, to: rgba.count, by: 4).contains { rgba[rgba.index(rgba.startIndex, offsetBy: $0)] != 255 },
                rgba8: Data(rgba)
            )

        case Self.dxgiBC1Unorm:
            guard depth == 1 else { throw DecodeError.unsupportedFormat(format) }
            let firstMipBytes = max(1, (width + 3) / 4) * max(1, (height + 3) / 4) * 8
            guard firstMipBytes <= resource.count else {
                throw DecodeError.truncatedResource(expected: firstMipBytes, available: resource.count)
            }
            let decoded = decodeBC1(resource.prefix(firstMipBytes), width: width, height: height)
            return T6DecodedTexture(
                imageID: imageID,
                width: width,
                height: height,
                depth: depth,
                mipCount: mipCount,
                format: .bc1Unorm,
                hasAlpha: stride(from: 3, to: decoded.count, by: 4).contains { decoded[$0] != 255 },
                rgba8: Data(decoded)
            )

        default:
            throw DecodeError.unsupportedFormat(format)
        }
    }

    private func decodeBC1(_ data: Data.SubSequence, width: Int, height: Int) -> [UInt8] {
        let bytes = Array(data)
        var output = Array(repeating: UInt8(0), count: width * height * 4)
        let blocksWide = max(1, (width + 3) / 4)
        let blocksHigh = max(1, (height + 3) / 4)

        for blockY in 0..<blocksHigh {
            for blockX in 0..<blocksWide {
                let offset = (blockY * blocksWide + blockX) * 8
                guard offset + 8 <= bytes.count else { continue }
                let c0 = UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
                let c1 = UInt16(bytes[offset + 2]) | (UInt16(bytes[offset + 3]) << 8)
                let a = rgba565(c0)
                let b = rgba565(c1)
                let palette: [[UInt8]]
                if c0 > c1 {
                    palette = [
                        a,
                        b,
                        mix(a, b, lhsWeight: 2, rhsWeight: 1, divisor: 3, alpha: 255),
                        mix(a, b, lhsWeight: 1, rhsWeight: 2, divisor: 3, alpha: 255)
                    ]
                } else {
                    palette = [
                        a,
                        b,
                        mix(a, b, lhsWeight: 1, rhsWeight: 1, divisor: 2, alpha: 255),
                        [0, 0, 0, 0]
                    ]
                }

                let selectors = UInt32(bytes[offset + 4]) |
                    (UInt32(bytes[offset + 5]) << 8) |
                    (UInt32(bytes[offset + 6]) << 16) |
                    (UInt32(bytes[offset + 7]) << 24)

                for py in 0..<4 {
                    for px in 0..<4 {
                        let x = blockX * 4 + px
                        let y = blockY * 4 + py
                        guard x < width, y < height else { continue }
                        let pixelIndex = py * 4 + px
                        let selector = Int((selectors >> UInt32(pixelIndex * 2)) & 0x3)
                        let color = palette[selector]
                        let out = (y * width + x) * 4
                        output[out] = color[0]
                        output[out + 1] = color[1]
                        output[out + 2] = color[2]
                        output[out + 3] = color[3]
                    }
                }
            }
        }
        return output
    }

    private func rgba565(_ value: UInt16) -> [UInt8] {
        let r5 = Int((value >> 11) & 0x1F)
        let g6 = Int((value >> 5) & 0x3F)
        let b5 = Int(value & 0x1F)
        return [
            UInt8((r5 * 255 + 15) / 31),
            UInt8((g6 * 255 + 31) / 63),
            UInt8((b5 * 255 + 15) / 31),
            255
        ]
    }

    private func mix(_ lhs: [UInt8], _ rhs: [UInt8], lhsWeight: Int, rhsWeight: Int, divisor: Int, alpha: UInt8) -> [UInt8] {
        [
            UInt8((Int(lhs[0]) * lhsWeight + Int(rhs[0]) * rhsWeight) / divisor),
            UInt8((Int(lhs[1]) * lhsWeight + Int(rhs[1]) * rhsWeight) / divisor),
            UInt8((Int(lhs[2]) * lhsWeight + Int(rhs[2]) * rhsWeight) / divisor),
            alpha
        ]
    }

    private func le16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private func le32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset]) |
            (UInt32(data[offset + 1]) << 8) |
            (UInt32(data[offset + 2]) << 16) |
            (UInt32(data[offset + 3]) << 24)
    }
}
