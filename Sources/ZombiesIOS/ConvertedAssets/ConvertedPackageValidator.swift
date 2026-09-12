import Foundation

enum ConvertedPackageValidationError: Error {
    case missingManifest
    case unsupportedVersion
    case incompletePackage
    case pathTraversal
    case missingRequiredFile(String)
    case invalidMaterialManifest
    case collisionBoundsDoNotOverlap
}

enum ConvertedPackageValidator {
    static func validate(at root: URL) throws -> ConvertedTranzitManifest {
        let fm = FileManager.default
        let manifestURL = root.appendingPathComponent("manifest.json", isDirectory: false)
        guard fm.fileExists(atPath: manifestURL.path) else {
            throw ConvertedPackageValidationError.missingManifest
        }

        let manifestData = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(ConvertedTranzitManifest.self, from: manifestData)
        guard manifest.formatVersion == ConvertedTranzitManifest.packageFormatVersion else {
            throw ConvertedPackageValidationError.unsupportedVersion
        }
        guard manifest.complete else {
            throw ConvertedPackageValidationError.incompletePackage
        }

        let worldURL = try resolvedRelativePath(manifest.worldMeshPath, under: root)
        let collisionURL = try resolvedRelativePath(manifest.collisionMeshPath, under: root)
        let materialURL = try resolvedRelativePath(manifest.materialManifestPath, under: root)
        let weaponURL = try resolvedRelativePath(manifest.weaponMeshPath, under: root)

        for (name, url) in [
            ("world", worldURL),
            ("collision", collisionURL),
            ("materials", materialURL),
            ("weapon", weaponURL)
        ] where !fm.fileExists(atPath: url.path) {
            throw ConvertedPackageValidationError.missingRequiredFile(name)
        }

        let world = try ConvertedMeshFormat.decode(Data(contentsOf: worldURL))
        let collision = try ConvertedMeshFormat.decode(Data(contentsOf: collisionURL))
        guard boundsOverlap(
            minA: world.boundsMin,
            maxA: world.boundsMax,
            minB: collision.boundsMin,
            maxB: collision.boundsMax
        ) else {
            throw ConvertedPackageValidationError.collisionBoundsDoNotOverlap
        }

        let materialData = try Data(contentsOf: materialURL)
        guard (try? JSONSerialization.jsonObject(with: materialData)) != nil else {
            throw ConvertedPackageValidationError.invalidMaterialManifest
        }

        return manifest
    }

    private static func resolvedRelativePath(_ path: String, under root: URL) throws -> URL {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("..") else {
            throw ConvertedPackageValidationError.pathTraversal
        }
        let standardizedRoot = root.standardizedFileURL
        let candidate = standardizedRoot.appendingPathComponent(path, isDirectory: false).standardizedFileURL
        let rootPrefix = standardizedRoot.path.hasSuffix("/") ? standardizedRoot.path : standardizedRoot.path + "/"
        guard candidate.path.hasPrefix(rootPrefix) else {
            throw ConvertedPackageValidationError.pathTraversal
        }
        return candidate
    }

    private static func boundsOverlap(
        minA: SIMD3<Float>,
        maxA: SIMD3<Float>,
        minB: SIMD3<Float>,
        maxB: SIMD3<Float>
    ) -> Bool {
        minA.x <= maxB.x && maxA.x >= minB.x
            && minA.y <= maxB.y && maxA.y >= minB.y
            && minA.z <= maxB.z && maxA.z >= minB.z
    }
}
