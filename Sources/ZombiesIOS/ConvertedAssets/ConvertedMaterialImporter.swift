import Foundation
import UIKit

struct ConvertedMaterialImportResult {
    let manifestPath: String
    let manifest: ConvertedMaterialManifest
}

enum ConvertedMaterialImportError: LocalizedError {
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .writeFailed(let reason):
            return "Converted materials could not be written: \(reason)"
        }
    }
}

struct ConvertedMaterialImporter {
    func convert(
        sources: [ConvertedMaterialSource],
        stagingURL: URL
    ) throws -> ConvertedMaterialImportResult {
        let fm = FileManager.default
        let textureDirectory = stagingURL.appendingPathComponent("textures", isDirectory: true)
        let materialDirectory = stagingURL.appendingPathComponent("materials", isDirectory: true)
        try fm.createDirectory(at: textureDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(at: materialDirectory, withIntermediateDirectories: true)

        var records: [ConvertedMaterialRecord] = []
        records.reserveCapacity(sources.count)

        for source in sources.sorted(by: { $0.id < $1.id }) {
            var texturePath: String?
            var fallbackReason: String?

            if let imageData = source.encodedImageData,
               let image = UIImage(data: imageData),
               let pngData = image.pngData() {
                let fileName = sanitizedFileName(source.name, id: source.id) + ".png"
                let relative = "textures/\(fileName)"
                let target = stagingURL.appendingPathComponent(relative, isDirectory: false)
                do {
                    try pngData.write(to: target, options: .atomic)
                    texturePath = relative
                } catch {
                    fallbackReason = "texture write failed: \(error.localizedDescription)"
                }
            } else if source.encodedImageData != nil {
                fallbackReason = "source texture encoding is not currently decodable by UIImage"
            } else {
                fallbackReason = "source diffuse texture was not resolved"
            }

            records.append(
                ConvertedMaterialRecord(
                    id: source.id,
                    name: source.name,
                    diffuseTexturePath: texturePath,
                    fallbackReason: fallbackReason,
                    doubleSided: source.doubleSided
                )
            )
        }

        let manifest = ConvertedMaterialManifest(
            materials: records,
            fullFidelity: records.allSatisfy { $0.diffuseTexturePath != nil && $0.fallbackReason == nil }
        )
        let manifestPath = "materials/materials.json"
        let target = stagingURL.appendingPathComponent(manifestPath, isDirectory: false)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(manifest).write(to: target, options: .atomic)
        } catch {
            throw ConvertedMaterialImportError.writeFailed(error.localizedDescription)
        }

        return ConvertedMaterialImportResult(manifestPath: manifestPath, manifest: manifest)
    }

    private func sanitizedFileName(_ name: String, id: Int) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = name.lowercased().unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "_" }
        let base = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return base.isEmpty ? "material_\(id)" : "\(id)_\(base)"
    }
}
