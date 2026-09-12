import XCTest
@testable import ZombiesIOS

final class RenderValidationTests: XCTestCase {
    func testBlackOrFallbackOnlySceneIsNotReady() {
        XCTAssertFalse(RenderValidation.accepts(.init(
            submittedTriangles: 1_000,
            drawnSurfaces: 3,
            nonFallbackMaterials: 0,
            residentTextures: 0,
            renderedProps: 0,
            validCamera: true,
            blackPixelRatio: 0.95
        )))
    }

    func testAcceptanceRequiresEveryLoadBearingMetric() {
        let valid = RenderValidationMetrics(
            submittedTriangles: 1_000,
            drawnSurfaces: 3,
            nonFallbackMaterials: 2,
            residentTextures: 2,
            renderedProps: 1,
            validCamera: true,
            blackPixelRatio: 0.35
        )
        XCTAssertTrue(RenderValidation.accepts(valid))

        var copy = valid
        copy.submittedTriangles = 0
        XCTAssertFalse(RenderValidation.accepts(copy))
        copy = valid
        copy.drawnSurfaces = 0
        XCTAssertFalse(RenderValidation.accepts(copy))
        copy = valid
        copy.nonFallbackMaterials = 0
        XCTAssertFalse(RenderValidation.accepts(copy))
        copy = valid
        copy.residentTextures = 0
        XCTAssertFalse(RenderValidation.accepts(copy))
        copy = valid
        copy.validCamera = false
        XCTAssertFalse(RenderValidation.accepts(copy))
        copy = valid
        copy.blackPixelRatio = 0.90
        XCTAssertFalse(RenderValidation.accepts(copy))
    }

    func testStructuralMetricsOnlyCountMaterialsActuallyBoundToSurfaces() throws {
        let used = T6AssetID(zoneName: "fixture", typeID: 6, assetIndex: 1, tableOffset: 0)
        let unused = T6AssetID(zoneName: "fixture", typeID: 6, assetIndex: 2, tableOffset: 0)
        let texture = T6DecodedTexture(
            imageID: T6AssetID(zoneName: "fixture", typeID: 8, assetIndex: 3, tableOffset: 0),
            width: 1,
            height: 1,
            depth: 1,
            mipCount: 1,
            format: .rgba8Unorm,
            hasAlpha: false,
            rgba8: Data([255, 255, 255, 255])
        )
        let surface = T6WorldSurface(
            vertices: [SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 0, 1)],
            normals: Array(repeating: SIMD3<Float>(0, 1, 0), count: 3),
            uvs: [SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(0, 1)],
            indices: [0, 1, 2],
            materialID: used,
            rawMaterialPointer: 1,
            sourceSurfaceIndex: 0
        )
        let world = T6RenderableWorld(
            surfaces: [surface],
            materials: [
                used: T6RenderableMaterial(materialID: used, baseColorTexture: texture, alphaMode: .opaque, isFallback: false),
                unused: T6RenderableMaterial(materialID: unused, baseColorTexture: texture, alphaMode: .opaque, isFallback: false)
            ],
            props: [],
            firstPersonWeapon: nil,
            spawnPosition: SIMD3<Float>(0, 1.7, 0),
            spawnForward: SIMD3<Float>(0, 0, -1),
            usesDiagnosticGeometry: false,
            diagnostics: T6RenderDiagnostics(unresolvedMaterialPointers: [], unsupportedTextureFormats: [], notes: [])
        )

        let metrics = RenderValidation.structuralMetrics(for: world)

        XCTAssertEqual(metrics.submittedTriangles, 1)
        XCTAssertEqual(metrics.drawnSurfaces, 1)
        XCTAssertEqual(metrics.nonFallbackMaterials, 1)
        XCTAssertEqual(metrics.residentTextures, 1)
        XCTAssertTrue(metrics.validCamera)
    }
}
