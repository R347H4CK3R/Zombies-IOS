import Foundation

struct T6RenderableWorldBuilder {
    enum BuildError: LocalizedError, Equatable {
        case noRenderableSurfaces
        case noRealMaterialBindings

        var errorDescription: String? {
            switch self {
            case .noRenderableSurfaces:
                return "The decoded T6 world contains no renderable surfaces."
            case .noRealMaterialBindings:
                return "The decoded T6 world has geometry but no real material is bound to a surface."
            }
        }
    }

    func build(
        surfaceSet: T6WorldSurfaceSet,
        materials: [T6AssetID: T6RenderableMaterial],
        props: [T6RenderableProp] = [],
        firstPersonWeapon: T6RenderableWeapon? = nil,
        requireCertifiableMaterials: Bool = true
    ) throws -> T6RenderableWorld {
        guard !surfaceSet.surfaces.isEmpty, surfaceSet.triangleCount > 0 else {
            throw BuildError.noRenderableSurfaces
        }

        var unresolvedPointers = Set<UInt32>()
        var realBoundMaterials = Set<T6AssetID>()
        for surface in surfaceSet.surfaces {
            guard let id = surface.materialID else {
                if surface.rawMaterialPointer != 0 {
                    unresolvedPointers.insert(surface.rawMaterialPointer)
                }
                continue
            }
            guard let material = materials[id] else {
                if surface.rawMaterialPointer != 0 {
                    unresolvedPointers.insert(surface.rawMaterialPointer)
                }
                continue
            }
            if !material.isFallback {
                realBoundMaterials.insert(id)
            }
        }

        if requireCertifiableMaterials && realBoundMaterials.isEmpty {
            throw BuildError.noRealMaterialBindings
        }

        let spawn = chooseSpawn(surfaces: surfaceSet.surfaces)
        let diagnostics = T6RenderDiagnostics(
            unresolvedMaterialPointers: unresolvedPointers.sorted(),
            unsupportedTextureFormats: [],
            notes: surfaceSet.usesDiagnosticGeometry ? ["World uses diagnostic recovery geometry."] : []
        )

        return T6RenderableWorld(
            surfaces: surfaceSet.surfaces,
            materials: materials,
            props: props,
            firstPersonWeapon: firstPersonWeapon,
            spawnPosition: spawn,
            spawnForward: SIMD3<Float>(0, 0, -1),
            usesDiagnosticGeometry: surfaceSet.usesDiagnosticGeometry,
            diagnostics: diagnostics
        )
    }

    private func chooseSpawn(surfaces: [T6WorldSurface]) -> SIMD3<Float> {
        var minV = SIMD3<Float>(repeating: Float.greatestFiniteMagnitude)
        var maxV = SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)
        var found = false
        for surface in surfaces {
            for vertex in surface.vertices {
                guard vertex.x.isFinite, vertex.y.isFinite, vertex.z.isFinite else { continue }
                minV = SIMD3<Float>(min(minV.x, vertex.x), min(minV.y, vertex.y), min(minV.z, vertex.z))
                maxV = SIMD3<Float>(max(maxV.x, vertex.x), max(maxV.y, vertex.y), max(maxV.z, vertex.z))
                found = true
            }
        }
        guard found else { return SIMD3<Float>(0, 1.7, 0) }
        return SIMD3<Float>((minV.x + maxV.x) * 0.5, minV.y + 1.7, (minV.z + maxV.z) * 0.5)
    }
}
