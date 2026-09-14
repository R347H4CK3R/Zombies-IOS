import Foundation

struct BO2LaunchDescriptor: Codable, Hashable, Sendable {
    let mode: BO2ContentMode
    let zone: String
    let resources: [String]

    var fastFiles: [String] {
        resources.filter { $0.lowercased().hasSuffix(".ff") }
    }

    var imageArchives: [String] {
        resources.filter { $0.lowercased().hasSuffix(".ipak") }
    }

    var audioBanks: [String] {
        resources.filter {
            let value = $0.lowercased()
            return value.hasSuffix(".sabs") || value.hasSuffix(".sabl")
        }
    }
}
