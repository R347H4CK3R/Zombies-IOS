import Foundation
import simd

final class QuakeRuntimeController {
    enum RuntimeError: LocalizedError {
        case initializeFailed(Int32)
        case worldLoadFailed(Int32)

        var errorDescription: String? {
            switch self {
            case .initializeFailed(let code): return "Quake runtime initialization failed (\(code))."
            case .worldLoadFailed(let code): return "Quake world load failed (\(code))."
            }
        }
    }

    struct PlayerState: Equatable {
        let position: SIMD3<Float>
        let yaw: Float
        let pitch: Float
        let grounded: Bool
        let frameNumber: UInt64
    }

    private(set) var package: BO2RuntimePackage
    private var lastJumpPulse = 0
    private var lastReloadPulse = 0
    private var pendingJump = false
    private var pendingReload = false
    private var initialized = false

    init(package: BO2RuntimePackage) throws {
        self.package = package
        let initCode = zq3_init()
        guard initCode == ZQ3_OK.rawValue else { throw RuntimeError.initializeFailed(initCode) }
        initialized = true
        try loadWorld(package)
    }

    deinit {
        if initialized { zq3_shutdown() }
    }

    func setInput(
        move: CGSize,
        look: CGSize,
        firing: Bool,
        aiming: Bool,
        jumpPulse: Int,
        reloadPulse: Int
    ) {
        if jumpPulse != lastJumpPulse {
            lastJumpPulse = jumpPulse
            pendingJump = true
        }
        if reloadPulse != lastReloadPulse {
            lastReloadPulse = reloadPulse
            pendingReload = true
        }

        var input = zq3_input_t()
        input.move_x = Float(max(-1, min(1, move.width / 70.0)))
        input.move_y = Float(max(-1, min(1, -move.height / 70.0)))
        input.look_x = Float(look.width)
        input.look_y = Float(look.height)
        input.fire = firing ? 1 : 0
        input.aim = aiming ? 1 : 0
        input.jump = pendingJump ? 1 : 0
        input.reload = pendingReload ? 1 : 0
        zq3_set_input(&input)
        pendingJump = false
        pendingReload = false
    }

    @discardableResult
    func step(deltaSeconds: Float) -> PlayerState {
        zq3_step(deltaSeconds)
        return playerState()
    }

    func playerState() -> PlayerState {
        var state = zq3_player_state_t()
        zq3_get_player_state(&state)
        let position = withUnsafeBytes(of: state.position) { raw -> SIMD3<Float> in
            let values = raw.bindMemory(to: Float.self)
            return SIMD3<Float>(values[0], values[1], values[2])
        }
        return PlayerState(
            position: position,
            yaw: state.yaw,
            pitch: state.pitch,
            grounded: state.grounded != 0,
            frameNumber: state.frame_number
        )
    }

    private func loadWorld(_ package: BO2RuntimePackage) throws {
        var xyz = [Float]()
        xyz.reserveCapacity(package.vertices.count * 3)
        for vertex in package.vertices {
            xyz.append(vertex.x)
            xyz.append(vertex.y)
            xyz.append(vertex.z)
        }

        let spawn = validatedSpawn(in: package)
        var spawnXYZ: [Float] = [spawn.x, spawn.y, spawn.z]
        let result: Int32 = xyz.withUnsafeBufferPointer { vertices in
            package.indices.withUnsafeBufferPointer { indices in
                spawnXYZ.withUnsafeBufferPointer { spawnBuffer in
                    zq3_load_world(
                        vertices.baseAddress,
                        UInt32(package.vertices.count),
                        indices.baseAddress,
                        UInt32(package.indices.count),
                        spawnBuffer.baseAddress
                    )
                }
            }
        }
        guard result == ZQ3_OK.rawValue else { throw RuntimeError.worldLoadFailed(result) }
    }

    private func validatedSpawn(in package: BO2RuntimePackage) -> SIMD3<Float> {
        let minV = package.bounds.min.simd
        let maxV = package.bounds.max.simd
        if let candidate = package.spawns.first?.origin.simd,
           candidate.x >= minV.x, candidate.x <= maxV.x,
           candidate.y >= minV.y - 32, candidate.y <= maxV.y + 256,
           candidate.z >= minV.z, candidate.z <= maxV.z {
            return candidate
        }
        return SIMD3<Float>(
            (minV.x + maxV.x) * 0.5,
            maxV.y + 64,
            (minV.z + maxV.z) * 0.5
        )
    }
}
