import Foundation
import AVFoundation
import simd

struct BO2SoundBank: Decodable {
    struct Alias: Decodable, Hashable {
        let name: String
        let file: String
        let secondary: String
        let bus: String
        let volumeMin: Float
        let volumeMax: Float
        let distanceMin: Float
        let distanceMax: Float
        let pitchMin: Float
        let pitchMax: Float
        let spatial: Bool
        let looping: Bool
        let probability: Float
        let startDelayMs: Float
        let music: Bool
        let fadeInMs: Float
        let fadeOutMs: Float
        let pauseable: Bool
    }

    let formatVersion: Int
    let id: String
    let aliases: [Alias]
}

@MainActor
final class BO2AudioEngine {
    enum AudioError: Error {
        case invalidFormatVersion(Int)
        case duplicateAlias(String)
        case missingAudioFile(String)
        case aliasNotFound(String)
    }

    private struct LoadedAlias {
        let definition: BO2SoundBank.Alias
        let url: URL?
    }

    private let engine = AVAudioEngine()
    private let environment = AVAudioEnvironmentNode()
    private var aliases: [String: LoadedAlias] = [:]
    private var activePlayers: [UUID: AVAudioPlayerNode] = [:]
    private var loopingPlayers: [String: UUID] = [:]

    init() {
        engine.attach(environment)
        engine.connect(environment, to: engine.mainMixerNode, format: nil)
        environment.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
        environment.listenerAngularOrientation = AVAudio3DAngularOrientation(yaw: 0, pitch: 0, roll: 0)
    }

    func loadBank(at bankURL: URL) throws {
        let data = try Data(contentsOf: bankURL.appendingPathComponent("aliases.json"))
        let bank = try JSONDecoder().decode(BO2SoundBank.self, from: data)
        guard bank.formatVersion == 1 else { throw AudioError.invalidFormatVersion(bank.formatVersion) }
        for alias in bank.aliases {
            guard aliases[alias.name] == nil else { throw AudioError.duplicateAlias(alias.name) }
            let url: URL?
            if alias.file.isEmpty {
                url = nil
            } else {
                let candidate = bankURL.appendingPathComponent(alias.file)
                guard FileManager.default.fileExists(atPath: candidate.path) else {
                    throw AudioError.missingAudioFile(alias.file)
                }
                url = candidate
            }
            aliases[alias.name] = LoadedAlias(definition: alias, url: url)
        }
        if !engine.isRunning {
            try engine.start()
        }
    }

    func setListener(position: SIMD3<Float>, yaw: Float, pitch: Float) {
        environment.listenerPosition = AVAudio3DPoint(x: position.x, y: position.y, z: position.z)
        environment.listenerAngularOrientation = AVAudio3DAngularOrientation(
            yaw: yaw * 180 / .pi,
            pitch: pitch * 180 / .pi,
            roll: 0
        )
    }

    @discardableResult
    func play(_ name: String, at position: SIMD3<Float>? = nil) throws -> UUID? {
        guard let loaded = aliases[name] else { throw AudioError.aliasNotFound(name) }
        guard let url = loaded.url else { return nil }
        if loaded.definition.probability < 1,
           Float.random(in: 0 ... 1) > max(0, loaded.definition.probability) {
            return nil
        }

        if loaded.definition.looping, let existing = loopingPlayers[name] {
            stop(existing)
        }

        let file = try AVAudioFile(forReading: url)
        let player = AVAudioPlayerNode()
        engine.attach(player)
        if loaded.definition.spatial {
            engine.connect(player, to: environment, format: file.processingFormat)
            if let p = position {
                player.position = AVAudio3DPoint(x: p.x, y: p.y, z: p.z)
            }
            player.renderingAlgorithm = .auto
        } else {
            engine.connect(player, to: engine.mainMixerNode, format: file.processingFormat)
        }

        let id = UUID()
        activePlayers[id] = player
        let volume = max(0, min(1, loaded.definition.volumeMax / 100))
        player.volume = volume

        schedule(file: file, player: player, alias: loaded.definition, id: id)
        let delay = max(0, loaded.definition.startDelayMs) / 1000
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(delay)) { [weak self, weak player] in
                guard let self, let player, self.activePlayers[id] != nil else { return }
                player.play()
            }
        } else {
            player.play()
        }
        if loaded.definition.looping { loopingPlayers[name] = id }
        return id
    }

    private func schedule(file: AVAudioFile, player: AVAudioPlayerNode, alias: BO2SoundBank.Alias, id: UUID) {
        player.scheduleFile(file, at: nil) { [weak self, weak player] in
            DispatchQueue.main.async {
                guard let self, let player, self.activePlayers[id] != nil else { return }
                if alias.looping {
                    do {
                        file.framePosition = 0
                        self.schedule(file: file, player: player, alias: alias, id: id)
                        if !player.isPlaying { player.play() }
                    }
                } else {
                    self.stop(id)
                    if !alias.secondary.isEmpty {
                        _ = try? self.play(alias.secondary)
                    }
                }
            }
        }
    }

    func stop(_ id: UUID) {
        guard let player = activePlayers.removeValue(forKey: id) else { return }
        player.stop()
        engine.disconnectNodeInput(player)
        engine.detach(player)
        loopingPlayers = loopingPlayers.filter { $0.value != id }
    }

    func stopLoop(_ aliasName: String) {
        if let id = loopingPlayers[aliasName] { stop(id) }
    }

    func stopAll() {
        for id in Array(activePlayers.keys) { stop(id) }
    }
}
