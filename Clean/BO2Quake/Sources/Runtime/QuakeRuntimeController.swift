import Foundation
import simd

final class QuakeRuntimeController: ObservableObject {
    struct InputState {
        var forward: Float = 0
        var right: Float = 0
        var yawDelta: Float = 0
        var pitchDelta: Float = 0
        var jump = false
        var fire = false
        var aim = false
        var reload = false
    }

    @Published private(set) var playerPosition = SIMD3<Float>(0, 60, 0)
    @Published private(set) var yaw: Float = 0
    @Published private(set) var pitch: Float = 0
    @Published private(set) var magazine: Int = 30
    @Published private(set) var reserve: Int = 120
    @Published private(set) var reloading = false
    @Published private(set) var lastShotHit = false

    private(set) var input = InputState()
    private var initialized = false

    init(asset: WorldRuntimeAsset) throws {
        guard zq3_init() != 0 else { throw RuntimeError.initializationFailed }
        initialized = true

        var xyz = [Float]()
        xyz.reserveCapacity(asset.metadata.vertexCount * 3)
        for index in 0..<asset.metadata.vertexCount {
            let base = index * WorldRuntimeAsset.vertexStride
            xyz.append(Self.readFloatLE(asset.vertexData, base))
            xyz.append(Self.readFloatLE(asset.vertexData, base + 4))
            xyz.append(Self.readFloatLE(asset.vertexData, base + 8))
        }
        var indices = [UInt32]()
        indices.reserveCapacity(asset.metadata.indexCount)
        for index in 0..<asset.metadata.indexCount {
            let value: UInt32 = asset.indexData.withUnsafeBytes { raw in
                raw.loadUnaligned(fromByteOffset: index * 4, as: UInt32.self)
            }
            indices.append(UInt32(littleEndian: value))
        }

        let spawn = zq3_vec3(x: asset.center.x, y: asset.center.y + ZQ3_PLAYER_HEIGHT, z: asset.center.z)
        let loaded = xyz.withUnsafeBufferPointer { vertices in
            indices.withUnsafeBufferPointer { indexBuffer in
                zq3_load_world(vertices.baseAddress, asset.metadata.vertexCount, indexBuffer.baseAddress, indices.count, spawn)
            }
        }
        guard loaded != 0 else { throw RuntimeError.worldLoadFailed }
        refreshState()
    }

    deinit {
        if initialized { zq3_shutdown() }
    }

    enum RuntimeError: Error {
        case initializationFailed
        case worldLoadFailed
    }

    func setMovement(forward: Float, right: Float) {
        input.forward = max(-1, min(1, forward))
        input.right = max(-1, min(1, right))
    }

    func addLook(yaw: Float, pitch: Float) {
        input.yawDelta += yaw
        input.pitchDelta += pitch
    }

    func setFire(_ value: Bool) { input.fire = value }
    func setAim(_ value: Bool) { input.aim = value }
    func requestJump() { input.jump = true }
    func requestReload() { input.reload = true }

    func step(seconds: Float) {
        var cInput = zq3_input(
            forward: input.forward,
            right: input.right,
            yaw_delta: input.yawDelta,
            pitch_delta: input.pitchDelta,
            jump: input.jump ? 1 : 0,
            fire: input.fire ? 1 : 0,
            aim: input.aim ? 1 : 0,
            reload: input.reload ? 1 : 0
        )
        zq3_set_input(cInput)
        zq3_step(seconds)
        input.yawDelta = 0
        input.pitchDelta = 0
        input.jump = false
        input.reload = false
        refreshState()
    }

    private func refreshState() {
        let player = zq3_get_player_state()
        playerPosition = SIMD3<Float>(player.origin.x, player.origin.y, player.origin.z)
        yaw = player.yaw
        pitch = player.pitch
        let weapon = zq3_get_weapon_state()
        magazine = Int(weapon.magazine)
        reserve = Int(weapon.reserve)
        reloading = weapon.reloading != 0
        lastShotHit = weapon.last_shot_hit != 0
    }

    private static func readFloatLE(_ data: Data, _ offset: Int) -> Float {
        let raw: UInt32 = data.withUnsafeBytes { bytes in
            bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
        }
        return Float(bitPattern: UInt32(littleEndian: raw))
    }
}
