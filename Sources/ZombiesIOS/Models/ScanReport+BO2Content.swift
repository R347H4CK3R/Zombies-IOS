import Foundation

extension ScannedFile {
    var bo2ContentMode: BO2ContentMode {
        BO2ContentClassifier.classify(path: relativePath)
    }
}

extension ScanReport {
    var bo2ContentCatalog: BO2ContentCatalog {
        BO2ContentCatalog(paths: files.map(\.relativePath))
    }

    func files(for mode: BO2ContentMode) -> [ScannedFile] {
        files.filter { $0.bo2ContentMode == mode }
    }
}
