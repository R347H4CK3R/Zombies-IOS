import Foundation
import simd

struct WeaponDefinition: Codable {
    let id: String
    let clipSize: Int
    let maxAmmo: Int
    let fireIntervalMs: Int
    let reloadTimeMs: Int
    let reloadEmptyTimeMs: Int
    let damage: Float
    let minDamage: Float
    let maxDamageRange: Float
    let minDamageRange: Float
    let shotCount: Int
    let fireType: String
    let adsTransInMs: Int
    let adsTransOutMs: Int
    let adsZoomFov: Float?

    var range: Float { minDamageRange }
}

struct CombatHit {
    let entityID: String?
    let position: SIMD3<Float>
    let distance: Float
}

protocol CombatRaycaster: AnyObject {
    func raycast(origin: SIMD3<Float>, direction: SIMD3<Float>, range: Float) -> CombatHit?
}

final class WeaponCombatRuntime {
    private(set) var definition: WeaponDefinition
    private(set) var magazine: Int
    private(set) var reserve: Int
    private(set) var reloading = false
    private var reloadRemaining: Float = 0
    private var fireCooldown: Float = 0
    weak var raycaster: CombatRaycaster?

    init(definition: WeaponDefinition) {
        self.definition = definition
        self.magazine = definition.clipSize
        self.reserve = max(0, definition.maxAmmo - definition.clipSize)
    }

    func step(_ delta: Float) {
        let dt = max(0, delta)
        fireCooldown = max(0, fireCooldown - dt)
        guard reloading else { return }
        reloadRemaining -= dt
        if reloadRemaining <= 0 {
            let need = max(0, definition.clipSize - magazine)
            let moved = min(need, reserve)
            magazine += moved
            reserve -= moved
            reloading = false
            reloadRemaining = 0
        }
    }

    @discardableResult
    func fire(origin: SIMD3<Float>, direction: SIMD3<Float>) -> [CombatHit] {
        guard !reloading, magazine > 0, fireCooldown <= 0 else { return [] }
        magazine -= 1
        fireCooldown = Float(definition.fireIntervalMs) / 1000
        let dir = simd_length_squared(direction) > 0 ? simd_normalize(direction) : SIMD3<Float>(0, 0, -1)
        var hits: [CombatHit] = []
        for _ in 0..<max(1, definition.shotCount) {
            if let hit = raycaster?.raycast(origin: origin, direction: dir, range: definition.minDamageRange) {
                hits.append(hit)
            }
        }
        return hits
    }

    func beginReload() {
        guard !reloading, magazine < definition.clipSize, reserve > 0 else { return }
        reloading = true
        let empty = magazine == 0
        reloadRemaining = Float(empty ? definition.reloadEmptyTimeMs : definition.reloadTimeMs) / 1000
    }

    func cancelReload() {
        reloading = false
        reloadRemaining = 0
    }

    func switchWeapon(to newDefinition: WeaponDefinition) {
        definition = newDefinition
        magazine = min(newDefinition.clipSize, newDefinition.maxAmmo)
        reserve = max(0, newDefinition.maxAmmo - magazine)
        reloading = false
        reloadRemaining = 0
        fireCooldown = 0
    }

    func damage(for distance: Float) -> Float {
        if distance <= definition.maxDamageRange { return definition.damage }
        if distance >= definition.minDamageRange { return definition.minDamage }
        let span = max(0.0001, definition.minDamageRange - definition.maxDamageRange)
        let t = max(0, min(1, (distance - definition.maxDamageRange) / span))
        return definition.damage + (definition.minDamage - definition.damage) * t
    }

    @discardableResult
    func applyDamage(_ amount: Float, to health: inout Float) -> Float {
        let applied = max(0, min(amount, health))
        health -= applied
        return applied
    }
}
