import XCTest
@testable import ZombiesIOS

final class T6RenderableWorldBuilderTests: XCTestCase {
    func testRequiresRealMaterialBoundToSurface() throws {
        let materialID = T6AssetID(zoneName: "fixture", typeID: 6, assetIndex: 1, tableOffset: 0x40)
        let surface = makeSurface(materialID: materialID, rawPointer: 0x1234)
        let set = T6WorldSurfaceSet(
            surfaces: [surface],
            sourceSurfaceTableOffset: 0,
            vertexStreamOffset: 0,
            indexStreamOffset: 0,
            usesDiagnosticGeometry: false
        )

        XCTAssertThrowsError(try T6RenderableWorldBuilder().build(surfaceSet: set, materials: [:])) { error in
            XCTAssertEqual(error as? T6RenderableWorldBuilder.BuildError, .noRealMaterialBindings)
        }
    }

    func testRealMaterialMakesWorldCertifiable() throws {
        let materialID = T6AssetID(zoneName: "fixture", typeID: 6, assetIndex: 1, tableOffset: 0x40)
        let surface = makeSurface(materialID: materialID, rawPointer: 0x1234)
        let set = T6WorldSurfaceSet(
            surfaces: [surface],
            sourceSurfaceTableOffset: 0,
            vertexStreamOffset: 0,
            indexStreamOffset: 0,
            usesDiagnosticGeometry: false
        )
        let material = T6RenderableMaterial(
            materialID: materialID,
            baseColorTexture: nil,
            alphaMode: .opaque,
            isFallback: false
        )

        let world = try T6RenderableWorldBuilder().build(surfaceSet: set, materials: [materialID: material])

        XCTAssertTrue(world.isCertifiable)
        XCTAssertEqual(world.triangleCount, 1)
        XCTAssertEqual(world.nonFallbackMaterialCount, 1)
        XCTAssertTrue(world.diagnostics.unresolvedMaterialPointers.isEmpty)
    }

    func testDiagnosticGeometryCannotBeCertifiable() throws {
        let materialID = T6AssetID(zoneName: "fixture", typeID: 6, assetIndex: 1, tableOffset: 0x40)
        let set = T6WorldSurfaceSet(
            surfaces: [makeSurface(materialID: materialID, rawPointer: 1)],
            sourceSurfaceTableOffset: 0,
            vertexStreamOffset: 0,
            indexStreamOffset: 0,
            usesDiagnosticGeometry: true
        )
        let material = T6RenderableMaterial(materialID: materialID, baseColorTexture: nil, alphaMode: .opaque, isFallback: false)

        let world = try T6RenderableWorldBuilder().build(surfaceSet: set, materials: [materialID: material])

        XCTAssertFalse(world.isCertifiable)
    }

    func testTwoSurfacesRetainDistinctMaterialIDsAndLocalIndices() throws {
        let firstID = T6AssetID(zoneName: "fixture", typeID: 6, assetIndex: 1, tableOffset: 0x40)
        let secondID = T6AssetID(zoneName: "fixture", typeID: 6, assetIndex: 2, tableOffset: 0x40)
        let first = makeSurface(materialID: firstID, rawPointer: 1)
        let second = T6WorldSurface(
            vertices: [SIMD3<Float>(10, 0, 0), SIMD3<Float>(11, 0, 0), SIMD3<Float>(10, 0, 1)],
            normals: Array(repeating: SIMD3<Float>(0, 1, 0), count: 3),
            uvs: [SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(0, 1)],
            indices: [0, 1, 2],
            materialID: secondID,
            rawMaterialPointer: 2,
            sourceSurfaceIndex: 1
        )
        let set = T6WorldSurfaceSet(
            surfaces: [first, second],
            sourceSurfaceTableOffset: 0,
            vertexStreamOffset: 0,
            indexStreamOffset: 0,
            usesDiagnosticGeometry: false
        )
        let materials = [
            firstID: T6RenderableMaterial(materialID: firstID, baseColorTexture: nil, alphaMode: .opaque, isFallback: false),
            secondID: T6RenderableMaterial(materialID: secondID, baseColorTexture: nil, alphaMode: .opaque, isFallback: false)
        ]

        let world = try T6RenderableWorldBuilder().build(surfaceSet: set, materials: materials)

        XCTAssertEqual(world.surfaces.count, 2)
        XCTAssertEqual(world.surfaces[0].materialID, firstID)
        XCTAssertEqual(world.surfaces[1].materialID, secondID)
        XCTAssertEqual(world.surfaces[0].indices, [0, 1, 2])
        XCTAssertEqual(world.surfaces[1].indices, [0, 1, 2])
    }

    private func makeSurface(materialID: T6AssetID?, rawPointer: UInt32) -> T6WorldSurface {
        T6WorldSurface(
            vertices: [SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 0, 1)],
            normals: Array(repeating: SIMD3<Float>(0, 1, 0), count: 3),
            uvs: [SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(0, 1)],
            indices: [0, 1, 2],
            materialID: materialID,
            rawMaterialPointer: rawPointer,
            sourceSurfaceIndex: 0
        )
    }
}
