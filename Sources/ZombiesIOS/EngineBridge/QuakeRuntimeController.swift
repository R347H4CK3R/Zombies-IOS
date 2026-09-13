import Foundation

@MainActor
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

    @Published private(set) var playerState = zq3_player_state()
    @Published private(set) var runtimeError: String?

    let package: BO2RuntimePackage
    private var lastFrameTime: CFTimeInterval = CACurrentMediaTime()

    init(package: BO2RuntimePackage) {
        self.package = package
        guard zq3_init() != 0 else {
            runtimeError = "Quake runtime initialization failed."
            return
        }
        var xyz = package.vertices.flatMap { [$0.x, $0.y, $0.z] }
        var indices = package.indices
        let initial = package.spawns.first?.origin ?? BO2RuntimeVertex(x: 0, y: 2, z: 0)
        let spawn = zq3_vec3(x: initial.x, y: initial.y, z: initial.z)
        let loaded = xyz.withUnsafeBufferPointer { v in
            indices.withUnsafeBufferPointer { i in
                zq3_load_world(v.baseAddress, package.vertices.count, i.baseAddress, i.count, spawn)
            }
        }
        if loaded == 0 { runtimeError = "Quake runtime rejected the converted BO2 world." }
        playerState = zq3_get_player_state()
    }

    deinit { zq3_shutdown() }

    func submit(_ state: InputState) {
        var c = zq3_input()
        c.forward = state.forward
        c.right = state.right
        c.yaw_delta = state.yawDelta
        c.pitch_delta = state.pitchDelta
        c.jump = state.jump ? 1 : 0
        c.fire = state.fire ? 1 : 0
        c.aim = state.aim ? 1 : 0
        c.reload = state.reload ? 1 : 0
        zq3_set_input(c)
    }

    func step() {
        let now = CACurrentMediaTime()
        let dt = Float(min(0.05, max(0, now - lastFrameTime)))
        lastFrameTime = now
        zq3_step(dt)
        playerState = zq3_get_player_state()
    }
}
