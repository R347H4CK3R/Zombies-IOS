import Foundation

enum T6MapEntsExtractor {
    /// Extracts the largest null-delimited printable entity lump that contains
    /// BO2 entity key/value syntax. This intentionally returns text only; it does
    /// not invent entities or geometry when MapEnts is absent.
    static func extract(from data: Data) -> String? {
        var best: String?
        var run = [UInt8]()
        run.reserveCapacity(256 * 1024)

        func consider() {
            defer { run.removeAll(keepingCapacity: true) }
            guard run.count >= 128,
                  let text = String(bytes: run, encoding: .utf8),
                  text.contains("\"classname\""),
                  text.contains("{") && text.contains("}") else { return }
            if best == nil || text.utf8.count > best!.utf8.count {
                best = text
            }
        }

        for byte in data {
            if byte == 0 {
                consider()
                continue
            }
            if byte == 9 || byte == 10 || byte == 13 || (byte >= 0x20 && byte <= 0x7E) {
                run.append(byte)
                if run.count > 2 * 1024 * 1024 {
                    run.removeAll(keepingCapacity: true)
                }
            } else {
                consider()
            }
        }
        consider()
        return best
    }
}
