import Foundation

enum ConvertedTranzitPaths {
    static let applicationSupportDirectory: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    }()

    static var activeRoot: URL {
        applicationSupportDirectory.appendingPathComponent("ConvertedTranzit", isDirectory: true)
    }

    static var stagingRoot: URL {
        applicationSupportDirectory.appendingPathComponent("ConvertedTranzit.staging", isDirectory: true)
    }

    static var diagnosticsDirectory: URL {
        activeRoot.appendingPathComponent("diagnostics", isDirectory: true)
    }

    static var importReportURL: URL {
        diagnosticsDirectory.appendingPathComponent("import-report.json", isDirectory: false)
    }

    static var manifestURL: URL {
        activeRoot.appendingPathComponent("manifest.json", isDirectory: false)
    }
}
