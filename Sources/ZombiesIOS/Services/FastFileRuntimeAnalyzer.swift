import Foundation

struct FastFileStructureReport: Sendable {
    let sampledBytes: Int
    let nonZeroRatio: Double
    let printableRatio: Double
    let uniqueByteCount: Int
    let signatureHex: String
    let asciiTokens: [String]

    var looksStructured: Bool {
        sampledBytes >= 1024 && nonZeroRatio > 0.10 && uniqueByteCount >= 24
    }

    var summary: String {
        if looksStructured {
            return "STRUCTURE OK"
        }
        return "STRUCTURE WEAK"
    }
}

enum FastFileRuntimeAnalyzer {
    static func analyze(chunks: [FastFileStreamReader.Chunk]) -> FastFileStructureReport {
        let data = chunks.reduce(into: Data()) { partial, chunk in
            partial.append(chunk.data)
        }

        guard !data.isEmpty else {
            return FastFileStructureReport(
                sampledBytes: 0,
                nonZeroRatio: 0,
                printableRatio: 0,
                uniqueByteCount: 0,
                signatureHex: "",
                asciiTokens: []
            )
        }

        var nonZero = 0
        var printable = 0
        var unique = Set<UInt8>()
        for byte in data {
            if byte != 0 { nonZero += 1 }
            if (32...126).contains(byte) { printable += 1 }
            unique.insert(byte)
        }

        let signature = data.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " ")
        let tokens = extractASCIIStrings(from: data, minimumLength: 5, limit: 8)

        return FastFileStructureReport(
            sampledBytes: data.count,
            nonZeroRatio: Double(nonZero) / Double(data.count),
            printableRatio: Double(printable) / Double(data.count),
            uniqueByteCount: unique.count,
            signatureHex: signature,
            asciiTokens: tokens
        )
    }

    private static func extractASCIIStrings(from data: Data, minimumLength: Int, limit: Int) -> [String] {
        var results: [String] = []
        var current: [UInt8] = []

        func flush() {
            guard current.count >= minimumLength, results.count < limit else {
                current.removeAll(keepingCapacity: true)
                return
            }
            if let string = String(bytes: current, encoding: .ascii) {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty && !results.contains(trimmed) {
                    results.append(trimmed)
                }
            }
            current.removeAll(keepingCapacity: true)
        }

        for byte in data {
            if (32...126).contains(byte) {
                current.append(byte)
            } else {
                flush()
                if results.count >= limit { break }
            }
        }
        if results.count < limit { flush() }
        return Array(results.prefix(limit))
    }
}
