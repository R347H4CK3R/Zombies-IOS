import Foundation
import simd

struct ZombieAgent: Identifiable, Codable {
    let id: String
    var position: SIMD3<Float>
    var health: Float
    var speed: Float
    var targetID: String?
    var alive: Bool { health > 0 }
}

final class ZombieDirector {
    private(set) var round: Int = 0
    private(set) var points: Int = 500
    private(set) var zombies: [String: ZombieAgent] = [:]
    private(set) var remainingToSpawn: Int = 0
    private var spawnAccumulator: Float = 0
    var spawnInterval: Float = 0.75
    var baseHealth: Float = 150

    func beginNextRound(playerCount: Int = 1) {
        round += 1
        let count = max(1, 6 + round * 2 + max(0, playerCount - 1) * 4)
        remainingToSpawn = count
        spawnAccumulator = 0
    }

    func step(_ delta: Float, spawn: (Int, Float) -> ZombieAgent?) {
        guard remainingToSpawn > 0 else { return }
        spawnAccumulator += max(0, delta)
        while remainingToSpawn > 0 && spawnAccumulator >= spawnInterval {
            spawnAccumulator -= spawnInterval
            let health = baseHealth * pow(1.1, Float(max(0, round - 1)))
            if let agent = spawn(round, health) {
                zombies[agent.id] = agent
                remainingToSpawn -= 1
            } else {
                break
            }
        }
    }

    func applyDamage(zombieID: String, damage: Float, rewardPerHit: Int = 10, killReward: Int = 60) {
        guard var zombie = zombies[zombieID], zombie.alive else { return }
        let before = zombie.health
        zombie.health = max(0, zombie.health - max(0, damage))
        if zombie.health < before { points += rewardPerHit }
        if before > 0 && zombie.health == 0 { points += killReward }
        zombies[zombieID] = zombie
    }

    @discardableResult
    func spendPoints(_ amount: Int) -> Bool {
        guard amount >= 0, points >= amount else { return false }
        points -= amount
        return true
    }

    func removeDead() {
        zombies = zombies.filter { $0.value.alive }
    }

    var roundCleared: Bool { remainingToSpawn == 0 && zombies.values.allSatisfy { !$0.alive } }
}

struct MultiplayerPlayerState: Codable {
    var score: Int = 0
    var deaths: Int = 0
    var team: String
    var alive: Bool = true
}

final class MultiplayerRules {
    private(set) var players: [String: MultiplayerPlayerState] = [:]
    private(set) var teamScore: [String: Int] = [:]
    var scoreLimit: Int = 75

    func join(playerID: String, team: String) {
        players[playerID] = MultiplayerPlayerState(team: team)
        teamScore[team, default: 0] += 0
    }

    func recordKill(killerID: String?, victimID: String) {
        guard var victim = players[victimID] else { return }
        victim.deaths += 1
        victim.alive = false
        players[victimID] = victim
        guard let killerID, killerID != victimID, var killer = players[killerID] else { return }
        killer.score += 1
        players[killerID] = killer
        teamScore[killer.team, default: 0] += 1
    }

    func respawn(playerID: String) {
        guard var player = players[playerID] else { return }
        player.alive = true
        players[playerID] = player
    }

    func score(team: String) -> Int { teamScore[team, default: 0] }

    var winningTeam: String? {
        teamScore.first(where: { $0.value >= scoreLimit })?.key
    }
}

enum GameModeRuntime {
    case zombies(ZombieDirector)
    case multiplayer(MultiplayerRules)
}
