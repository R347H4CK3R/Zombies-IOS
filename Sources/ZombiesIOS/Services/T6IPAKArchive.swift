import Foundation

struct T6IPAKSegment: Sendable, Equatable {
    let type: UInt32
    let offset: UInt32
    let size: UInt32
    let entryCount: UInt32
}

struct T6IPAKEntry: Sendable, Equatable, Identifiable {
    let index: Int
    let key: UInt64
    let offset: UInt32
    let compressedSize: UInt32

    var id: UInt64 { key }
    var keyHex: String { String(format: "%016llx", key) }
}

struct T6IPAKIndex: Sendable {
    enum ByteOrder: String, Sendable {
        case big
        case little
    }

    let url: URL
    let byteOrder: ByteOrder
    let version: UInt32
    let declaredSize: UInt32
    let segments: [T6IPAKSegment]
    let entries: [T6IPAKEntry]
    let dataSegment: T6IPAKSegment
}

enum T6IPAKArchive {
    enum ArchiveError: LocalizedError {
        case unreadable
        case invalidMagic
        case invalidLayout
        case missingSegments
        case truncated(String)
        case invalidEntry(Int)
        case invalidCommandCount(Int)
        case lzo(String)
        case outputLimit

        var errorDescription: String? {
            switch self {
            case .unreadable: return "Unable to read IPAK archive."
            case .invalidMagic: return "File is not a T6 IPAK archive."
            case .invalidLayout: return "No plausible T6 IPAK layout was found."
            case .missingSegments: return "IPAK is missing entry/data segments."
            case .truncated(let whereAt): return "IPAK is truncated at \(whereAt)."
            case .invalidEntry(let index): return "IPAK entry \(index) is outside the data segment."
            case .invalidCommandCount(let count): return "Invalid IPAK command count \(count)."
            case .lzo(let message): return "LZO decode failed: \(message)"
            case .outputLimit: return "Decoded IPAK entry exceeded the output safety limit."
            }
        }
    }

    private static let maxLZOOutput = 64 * 1024 * 1024
    private static let maxEntryOutput = 128 * 1024 * 1024

    static func open(_ url: URL) throws -> T6IPAKIndex {
        guard let handle = try? FileHandle(forReadingFrom: url) else { throw ArchiveError.unreadable }
        defer { try? handle.close() }
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        let head = try handle.read(upToCount: Int(min(fileSize, 4096))) ?? Data()
        guard head.count >= 48 else { throw ArchiveError.truncated("header") }
        let magic = String(data: head.prefix(4), encoding: .ascii) ?? ""
        guard magic == "IPAK" else { throw ArchiveError.invalidMagic }

        struct Candidate {
            let order: T6IPAKIndex.ByteOrder
            let version: UInt32
            let declaredSize: UInt32
            let segments: [T6IPAKSegment]
            let score: Int
        }

        var candidates: [Candidate] = []
        for order in [T6IPAKIndex.ByteOrder.big, .little] {
            guard let version = read32(head, 4, order),
                  let declaredSize = read32(head, 8, order),
                  let segmentCountRaw = read32(head, 12, order) else { continue }
            let segmentCount = Int(segmentCountRaw)
            guard (1...32).contains(segmentCount), 16 + segmentCount * 16 <= head.count else { continue }

            let segments = parseSegments(head, count: segmentCount, order: order)
            guard segments.count == segmentCount else { continue }
            var score = 0
            var plausibleCount = 0
            for segment in segments {
                let start = UInt64(segment.offset)
                let size = UInt64(segment.size)
                let plausible = segment.type <= 8 && start <= fileSize && size <= fileSize && start + size <= fileSize && segment.entryCount < 10_000_000
                if plausible {
                    score += 3
                    plausibleCount += 1
                }
            }
            let types = Set(segments.filter {
                UInt64($0.offset) + UInt64($0.size) <= fileSize
            }.map(\.type))
            if types.contains(1) { score += 5 }
            if types.contains(2) { score += 5 }
            if version < 0x0100_0000 { score += 1 }
            if UInt64(declaredSize) == fileSize { score += 2 }
            if plausibleCount == segmentCount {
                candidates.append(Candidate(order: order, version: version, declaredSize: declaredSize, segments: segments, score: score))
            }
        }

        guard let best = candidates.max(by: { $0.score < $1.score }), best.score >= 10 else {
            throw ArchiveError.invalidLayout
        }
        guard let entrySegment = best.segments.first(where: { $0.type == 1 }),
              let dataSegment = best.segments.first(where: { $0.type == 2 }) else {
            throw ArchiveError.missingSegments
        }

        let entries = try parseEntries(handle: handle, segment: entrySegment, dataSegment: dataSegment, fileSize: fileSize, order: best.order)
        return T6IPAKIndex(
            url: url,
            byteOrder: best.order,
            version: best.version,
            declaredSize: best.declaredSize,
            segments: best.segments,
            entries: entries,
            dataSegment: dataSegment
        )
    }

    static func parseSegments(_ data: Data, count: Int, order: T6IPAKIndex.ByteOrder) -> [T6IPAKSegment] {
        guard count > 0 else { return [] }
        var result: [T6IPAKSegment] = []
        result.reserveCapacity(count)
        for index in 0..<count {
            let offset = 16 + index * 16
            guard let type = read32(data, offset, order),
                  let start = read32(data, offset + 4, order),
                  let size = read32(data, offset + 8, order),
                  let entries = read32(data, offset + 12, order) else { break }
            result.append(T6IPAKSegment(type: type, offset: start, size: size, entryCount: entries))
        }
        return result
    }

    static func parseEntries(
        handle: FileHandle,
        segment: T6IPAKSegment,
        dataSegment: T6IPAKSegment,
        fileSize: UInt64,
        order: T6IPAKIndex.ByteOrder
    ) throws -> [T6IPAKEntry] {
        try handle.seek(toOffset: UInt64(segment.offset))
        var result: [T6IPAKEntry] = []
        result.reserveCapacity(Int(segment.entryCount))
        for index in 0..<Int(segment.entryCount) {
            guard let raw = try handle.read(upToCount: 16), raw.count == 16 else {
                throw ArchiveError.truncated("entry table")
            }
            guard let key = read64(raw, 0, order),
                  let offset = read32(raw, 8, order),
                  let compressedSize = read32(raw, 12, order) else {
                throw ArchiveError.truncated("entry \(index)")
            }
            let absoluteStart = UInt64(dataSegment.offset) + UInt64(offset)
            guard absoluteStart >= UInt64(dataSegment.offset), absoluteStart <= fileSize else {
                throw ArchiveError.invalidEntry(index)
            }
            result.append(T6IPAKEntry(index: index, key: key, offset: offset, compressedSize: compressedSize))
        }
        return result
    }

    static func decodeEntry(_ entry: T6IPAKEntry, from index: T6IPAKIndex, maxOutput: Int = maxEntryOutput) throws -> Data {
        guard let handle = try? FileHandle(forReadingFrom: index.url) else { throw ArchiveError.unreadable }
        defer { try? handle.close() }
        let attrs = try FileManager.default.attributesOfItem(atPath: index.url.path)
        let fileSize = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        let start = UInt64(index.dataSegment.offset) + UInt64(entry.offset)
        guard start < fileSize else { throw ArchiveError.invalidEntry(entry.index) }
        try handle.seek(toOffset: start)

        let target = UInt64(entry.compressedSize)
        var consumed: UInt64 = 0
        var output = Data()
        output.reserveCapacity(min(Int(target), maxOutput))

        while consumed < target {
            let headerPosition = try handle.offset()
            guard let header = try handle.read(upToCount: 128), header.count == 128 else {
                throw ArchiveError.truncated(String(format: "block header 0x%llx", headerPosition))
            }
            let (count, commands) = try parseBlockHeader(header, order: index.byteOrder)
            guard (1...31).contains(count) else { throw ArchiveError.invalidCommandCount(count) }
            consumed += 128

            for commandIndex in 0..<count {
                let command = commands[commandIndex]
                let blockSize = Int(command & 0x00FF_FFFF)
                let flag = UInt8((command >> 24) & 0xFF)
                if blockSize == 0 { continue }
                let position = try handle.offset()
                guard position + UInt64(blockSize) <= fileSize else { throw ArchiveError.truncated("data block") }
                guard let block = try handle.read(upToCount: blockSize), block.count == blockSize else {
                    throw ArchiveError.truncated("data block")
                }

                switch flag {
                case 0:
                    guard output.count + block.count <= maxOutput else { throw ArchiveError.outputLimit }
                    output.append(block)
                case 1:
                    let decoded = try lzo1xDecompress(block, maxOutput: min(maxLZOOutput, maxOutput - output.count))
                    guard output.count + decoded.count <= maxOutput else { throw ArchiveError.outputLimit }
                    output.append(decoded)
                default:
                    break
                }

                if commandIndex + 1 == count {
                    let now = try handle.offset()
                    let aligned = (now + 0x7F) & ~UInt64(0x7F)
                    let padding = aligned - now
                    if padding > 0 { try handle.seek(toOffset: aligned) }
                    consumed += UInt64(blockSize) + padding
                } else {
                    consumed += UInt64(blockSize)
                }
                if consumed >= target { break }
            }
        }
        return output
    }

    static func lzo1xDecompress(_ data: Data, maxOutput: Int = maxLZOOutput) throws -> Data {
        let src = [UInt8](data)
        guard !src.isEmpty else { throw ArchiveError.lzo("empty stream") }
        var ip = 0
        var out = [UInt8]()
        out.reserveCapacity(min(maxOutput, max(256, src.count * 2)))
        let m2MaxOffset = 0x0800

        func need(_ count: Int) throws {
            guard count >= 0, ip + count <= src.count else {
                throw ArchiveError.lzo("truncated stream at input offset \(ip), need \(count) byte(s)")
            }
        }
        func ensureOutput(_ count: Int) throws {
            guard count >= 0, out.count + count <= maxOutput else { throw ArchiveError.outputLimit }
        }
        func get1() throws -> Int {
            try need(1)
            let value = Int(src[ip])
            ip += 1
            return value
        }
        func get16LE() throws -> Int {
            try need(2)
            let value = Int(src[ip]) | (Int(src[ip + 1]) << 8)
            ip += 2
            return value
        }
        func copyLiterals(_ count: Int) throws {
            try need(count)
            try ensureOutput(count)
            if count > 0 {
                out.append(contentsOf: src[ip..<(ip + count)])
                ip += count
            }
        }
        func copyMatch(distance: Int, length: Int) throws {
            guard distance > 0, distance <= out.count else {
                throw ArchiveError.lzo("invalid match distance \(distance) with output size \(out.count)")
            }
            try ensureOutput(length)
            for _ in 0..<length { out.append(out[out.count - distance]) }
        }
        func extended(_ base: Int) throws -> Int {
            var total = 0
            while true {
                let byte = try get1()
                if byte != 0 { return total + byte + base }
                total += 255
                if total > maxOutput { throw ArchiveError.lzo("unreasonable extended length") }
            }
        }

        enum State { case main, firstLiteralRun, match }
        let first = try get1()
        var state: State = .main
        var t = first

        if first > 17 {
            t = first - 17
            if t < 4 {
                try copyLiterals(t)
                t = try get1()
                state = .match
            } else {
                try copyLiterals(t)
                state = .firstLiteralRun
            }
        } else {
            ip -= 1
            state = .main
        }

        while true {
            switch state {
            case .main:
                guard ip < src.count else { throw ArchiveError.lzo("EOF marker not found") }
                t = try get1()
                if t >= 16 {
                    state = .match
                    continue
                }
                if t == 0 { t = try extended(15) }
                try copyLiterals(t + 3)
                state = .firstLiteralRun

            case .firstLiteralRun:
                t = try get1()
                if t >= 16 {
                    state = .match
                    continue
                }
                let byte = try get1()
                let distance = 1 + m2MaxOffset + (t >> 2) + (byte << 2)
                try copyMatch(distance: distance, length: 3)
                let trailing = t & 3
                if trailing != 0 {
                    try copyLiterals(trailing)
                    t = try get1()
                    state = .match
                } else {
                    state = .main
                }

            case .match:
                let trailing: Int
                if t >= 64 {
                    let byte = try get1()
                    let distance = 1 + ((t >> 2) & 7) + (byte << 3)
                    let length = (t >> 5) + 1
                    try copyMatch(distance: distance, length: length)
                    trailing = t & 3
                } else if t >= 32 {
                    var lengthCode = t & 31
                    if lengthCode == 0 { lengthCode = try extended(31) }
                    let descriptor = try get16LE()
                    let distance = 1 + (descriptor >> 2)
                    try copyMatch(distance: distance, length: lengthCode + 2)
                    trailing = descriptor & 3
                } else if t >= 16 {
                    let high = (t & 8) << 11
                    var lengthCode = t & 7
                    if lengthCode == 0 { lengthCode = try extended(7) }
                    let descriptor = try get16LE()
                    let rawDistance = high + (descriptor >> 2)
                    if rawDistance == 0 {
                        if ip < src.count, src[ip...].contains(where: { $0 != 0 }) {
                            throw ArchiveError.lzo("input not fully consumed (\(src.count - ip) trailing byte(s))")
                        }
                        return Data(out)
                    }
                    try copyMatch(distance: rawDistance + 0x4000, length: lengthCode + 2)
                    trailing = descriptor & 3
                } else {
                    let byte = try get1()
                    let distance = 1 + (t >> 2) + (byte << 2)
                    try copyMatch(distance: distance, length: 2)
                    trailing = t & 3
                }

                if trailing != 0 {
                    try copyLiterals(trailing)
                    t = try get1()
                    state = .match
                } else {
                    state = .main
                }
            }
        }
    }

    private static func parseBlockHeader(_ data: Data, order: T6IPAKIndex.ByteOrder) throws -> (Int, [UInt32]) {
        guard data.count >= 128, let first = read32(data, 0, order) else { throw ArchiveError.truncated("block header") }
        let count: Int
        if order == .little {
            count = Int((first >> 24) & 0xFF)
        } else {
            let high = Int((first >> 24) & 0xFF)
            let low = Int(first & 0xFF)
            count = (1...31).contains(high) ? high : low
        }
        var commands: [UInt32] = []
        commands.reserveCapacity(31)
        for index in 0..<31 {
            guard let command = read32(data, 4 + index * 4, order) else { throw ArchiveError.truncated("commands") }
            commands.append(command)
        }
        return (count, commands)
    }

    private static func read32(_ data: Data, _ offset: Int, _ order: T6IPAKIndex.ByteOrder) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        if order == .big {
            return (UInt32(data[offset]) << 24) | (UInt32(data[offset + 1]) << 16) | (UInt32(data[offset + 2]) << 8) | UInt32(data[offset + 3])
        }
        return UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8) | (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
    }

    private static func read64(_ data: Data, _ offset: Int, _ order: T6IPAKIndex.ByteOrder) -> UInt64? {
        guard offset >= 0, offset + 8 <= data.count else { return nil }
        var value: UInt64 = 0
        if order == .big {
            for i in 0..<8 { value = (value << 8) | UInt64(data[offset + i]) }
        } else {
            for i in stride(from: 7, through: 0, by: -1) { value = (value << 8) | UInt64(data[offset + i]) }
        }
        return value
    }
}
