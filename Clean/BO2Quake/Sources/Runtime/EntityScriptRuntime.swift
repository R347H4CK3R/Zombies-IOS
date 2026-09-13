import Foundation
import simd

struct RuntimeEntity: Codable, Identifiable {
    let id: String
    let classname: String
    let origin: SIMD3<Float>?
    let properties: [String: String]
}

struct TriggerVolume: Codable {
    let id: String
    let mins: SIMD3<Float>
    let maxs: SIMD3<Float>
    let target: String?

    func contains(_ point: SIMD3<Float>) -> Bool {
        point.x >= mins.x && point.y >= mins.y && point.z >= mins.z &&
        point.x <= maxs.x && point.y <= maxs.y && point.z <= maxs.z
    }
}

enum ObjectiveState: String, Codable {
    case inactive
    case active
    case complete
    case failed
}

final class EntityScriptRuntime {
    struct ScheduledTimer {
        let id: String
        var remaining: Float
        let event: String
    }

    private(set) var entities: [String: RuntimeEntity] = [:]
    private(set) var triggers: [String: TriggerVolume] = [:]
    private(set) var variables: [String: String] = [:]
    private(set) var objectiveState: [String: ObjectiveState] = [:]
    private(set) var pendingEvents: [String] = []
    private var timers: [String: ScheduledTimer] = [:]
    private var activeTriggers: Set<String> = []

    func load(entities: [RuntimeEntity], triggers: [TriggerVolume]) {
        self.entities = Dictionary(uniqueKeysWithValues: entities.map { ($0.id, $0) })
        self.triggers = Dictionary(uniqueKeysWithValues: triggers.map { ($0.id, $0) })
        activeTriggers.removeAll()
        timers.removeAll()
        pendingEvents.removeAll()
    }

    func setVariable(_ key: String, value: String) {
        variables[key] = value
    }

    func variable(_ key: String) -> String? { variables[key] }

    func setObjective(_ id: String, state: ObjectiveState) {
        objectiveState[id] = state
        pendingEvents.append("objective:\(id):\(state.rawValue)")
    }

    func scheduleTimer(id: String, seconds: Float, event: String) {
        timers[id] = ScheduledTimer(id: id, remaining: max(0, seconds), event: event)
    }

    func cancelTimer(id: String) { timers.removeValue(forKey: id) }

    func triggerEnter(id: String) {
        guard triggers[id] != nil, !activeTriggers.contains(id) else { return }
        activeTriggers.insert(id)
        pendingEvents.append("triggerEnter:\(id)")
    }

    func triggerExit(id: String) {
        guard activeTriggers.remove(id) != nil else { return }
        pendingEvents.append("triggerExit:\(id)")
    }

    func updateTriggerOccupancy(position: SIMD3<Float>) {
        for (id, trigger) in triggers {
            if trigger.contains(position) { triggerEnter(id: id) }
            else { triggerExit(id: id) }
        }
    }

    func step(_ delta: Float) {
        guard delta >= 0 else { return }
        var fired: [String] = []
        for (id, var timer) in timers {
            timer.remaining -= delta
            if timer.remaining <= 0 {
                pendingEvents.append(timer.event)
                fired.append(id)
            } else {
                timers[id] = timer
            }
        }
        for id in fired { timers.removeValue(forKey: id) }
    }

    func drainEvents() -> [String] {
        let events = pendingEvents
        pendingEvents.removeAll(keepingCapacity: true)
        return events
    }
}
