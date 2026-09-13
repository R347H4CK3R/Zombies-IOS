import Foundation

enum BO2MapTarget: String, CaseIterable, Identifiable, Sendable {
    case hijacked

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hijacked: return "Hijacked"
        }
    }

    var fastFileName: String {
        switch self {
        case .hijacked: return "mp_hijacked.ff"
        }
    }

    var ipakName: String {
        switch self {
        case .hijacked: return "mp_hijacked.ipak"
        }
    }

    var audioBankName: String {
        switch self {
        case .hijacked: return "mpl_hijacked.all.sabs"
        }
    }

    var requiredFileNames: Set<String> {
        [fastFileName, ipakName, audioBankName]
    }

    static func recognizes(_ path: String) -> Bool {
        let name = (path.replacingOccurrences(of: "\\", with: "/") as NSString)
            .lastPathComponent
            .lowercased()
        return allCases.contains { $0.requiredFileNames.contains(name) }
    }

    func resources(in report: ScanReport) -> [ScannedFile] {
        report.files.filter { requiredFileNames.contains($0.name.lowercased()) }
    }

    func isComplete(in report: ScanReport) -> Bool {
        let names = Set(resources(in: report).map { $0.name.lowercased() })
        return requiredFileNames.isSubset(of: names)
    }
}
