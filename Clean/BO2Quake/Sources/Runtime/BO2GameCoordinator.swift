import Foundation
import Combine
import simd

@MainActor
final class BO2GameCoordinator: ObservableObject {
    let movement: QuakeRuntimeController
    let audio: BO2AudioEngine
    let animationPlayer = AnimationPlayer()
    let weapon: WeaponCombatRuntime
    let entities = EntityScriptRuntime()
    private let raycaster: WorldTriangleRaycaster
    private(set) var gameMode: GameModeRuntime
    private var fireHeld = false

    @Published private(set) var objectiveMessages: [String] = []
    @Published private(set) var lastCombatHits: [CombatHit] = []

    init(
        world: WorldRuntimeAsset,
        weaponDefinition: WeaponDefinition,
        gameMode: GameModeRuntime = .zombies(ZombieDirector())
    ) throws {
        self.movement = try QuakeRuntimeController(asset: world)
        self.audio = BO2AudioEngine()
        self.weapon = WeaponCombatRuntime(definition: weaponDefinition)
        self.raycaster = WorldTriangleRaycaster(asset: world)
        self.gameMode = gameMode
        self.weapon.raycaster = self.raycaster
    }

    func setGameMode(_ mode: GameModeRuntime) {
        gameMode = mode
        objectWillChange.send()
    }

    func setFireHeld(_ held: Bool) {
        fireHeld = held
        if held { fire(direction: aimDirection) }
    }

    func step(seconds: Float) {
        movement.step(seconds: seconds)
        weapon.step(seconds)
        animationPlayer.step(seconds)
        if fireHeld { fire(direction: aimDirection) }
        entities.updateTriggerOccupancy(position: movement.playerPosition)
        entities.step(seconds)
        let events = entities.drainEvents()
        if !events.isEmpty {
            objectiveMessages.append(contentsOf: events)
            if objectiveMessages.count > 32 {
                objectiveMessages.removeFirst(objectiveMessages.count - 32)
            }
        }
        audio.setListener(position: movement.playerPosition, yaw: movement.yaw, pitch: movement.pitch)

        switch gameMode {
        case .zombies(let director):
            if director.round == 0 || director.roundCleared { director.beginNextRound() }
        case .multiplayer:
            break
        }
        // Nested runtime objects are deliberately not ObservableObjects; publish
        // one frame notification so HUD ammo/round/points reflect authoritative state.
        objectWillChange.send()
    }

    var aimDirection: SIMD3<Float> {
        let yaw = movement.yaw * .pi / 180
        let pitch = movement.pitch * .pi / 180
        let cp = cos(pitch)
        return simd_normalize(SIMD3<Float>(sin(yaw) * cp, sin(pitch), -cos(yaw) * cp))
    }

    func fire(direction: SIMD3<Float>) {
        let hits = weapon.fire(origin: movement.playerPosition, direction: direction)
        if !hits.isEmpty { lastCombatHits = hits }
    }

    func beginReload() {
        weapon.beginReload()
        objectWillChange.send()
    }

    func triggerUse(_ id: String) {
        entities.setVariable("lastUse", value: id)
    }
}
