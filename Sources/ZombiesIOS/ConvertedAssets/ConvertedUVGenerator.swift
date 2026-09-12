import Foundation

enum ConvertedUVGenerator {
    /// Deterministic phase-one fallback when source UVs are not yet decoded.
    /// Projects the two widest world axes into 0...1 so converted textures
    /// visibly map instead of rendering with no texture coordinates.
    static func planarFallback(
        positions: [SIMD3<Float>],
        boundsMin: SIMD3<Float>,
        boundsMax: SIMD3<Float>
    ) -> [SIMD2<Float>] {
        guard !positions.isEmpty else { return [] }
        let span = boundsMax - boundsMin
        let axes = [
            (index: 0, span: abs(span.x)),
            (index: 1, span: abs(span.y)),
            (index: 2, span: abs(span.z))
        ].sorted { $0.span > $1.span }
        let uAxis = axes[0].index
        let vAxis = axes[1].index
        let uMin = component(boundsMin, axis: uAxis)
        let vMin = component(boundsMin, axis: vAxis)
        let uSpan = max(0.0001, component(boundsMax, axis: uAxis) - uMin)
        let vSpan = max(0.0001, component(boundsMax, axis: vAxis) - vMin)

        return positions.map { p in
            let u = (component(p, axis: uAxis) - uMin) / uSpan
            let v = (component(p, axis: vAxis) - vMin) / vSpan
            return SIMD2<Float>(u, 1 - v)
        }
    }

    private static func component(_ value: SIMD3<Float>, axis: Int) -> Float {
        switch axis {
        case 0: return value.x
        case 1: return value.y
        default: return value.z
        }
    }
}
