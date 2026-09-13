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
    private(set) var gameMode: GameModeRuntime

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
        self.gameMode = gameMode
    }

    func setGameMode(_ mode: GameModeRuntime) {
        gameMode = mode
    }

    func step(seconds: Float) {
        movement.step(seconds: seconds)
        weapon.step(seconds)
        animationPlayer.step(seconds)
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
    }

    func fire(direction: SIMD3<Float>) {
        lastCombatHits = weapon.fire(origin: movement.playerPosition, direction: direction)
    }

    func beginReload() {
        weapon.beginReload()
        movement.requestReload()
    }

    func triggerUse(_ id: String) {
        entities.setVariable("lastUse", value: id)
    }
}
