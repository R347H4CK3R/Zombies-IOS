import Foundation
import simd

struct RuntimeAnimationNotify: Codable, Hashable {
    let name: String
    let time: Float
}

struct RuntimeBoneKeyframe: Codable {
    let time: Float
    let translation: SIMD3<Float>
    let rotation: SIMD4<Float>
}

struct RuntimeBoneTrack: Codable {
    let boneName: String
    let keyframes: [RuntimeBoneKeyframe]
}

struct RuntimeAnimationClip: Codable {
    let id: String
    let duration: Float
    let frameRate: Float
    let looping: Bool
    let notifies: [RuntimeAnimationNotify]
    let tracks: [RuntimeBoneTrack]
}

final class AnimationPlayer {
    private(set) var clip: RuntimeAnimationClip?
    private(set) var time: Float = 0
    private(set) var firedNotifies: [RuntimeAnimationNotify] = []

    func play(_ clip: RuntimeAnimationClip, restart: Bool = true) {
        self.clip = clip
        if restart { time = 0 }
        firedNotifies.removeAll(keepingCapacity: true)
    }

    func stop() {
        clip = nil
        time = 0
        firedNotifies.removeAll(keepingCapacity: true)
    }

    func step(_ delta: Float) {
        guard let clip, clip.duration > 0, delta >= 0 else { return }
        let previous = time
        var next = time + delta
        var wrapped = false
        if clip.looping && next >= clip.duration {
            next.formTruncatingRemainder(dividingBy: clip.duration)
            wrapped = true
        } else {
            next = min(next, clip.duration)
        }
        firedNotifies = clip.notifies.filter { notify in
            if wrapped { return notify.time >= previous || notify.time <= next }
            return notify.time > previous && notify.time <= next
        }
        time = next
    }

    func pose(for boneName: String) -> (translation: SIMD3<Float>, rotation: SIMD4<Float>)? {
        guard let clip, let track = clip.tracks.first(where: { $0.boneName == boneName }), !track.keyframes.isEmpty else { return nil }
        if track.keyframes.count == 1 {
            let key = track.keyframes[0]
            return (key.translation, key.rotation)
        }
        let frames = track.keyframes.sorted { $0.time < $1.time }
        let upperIndex = frames.firstIndex(where: { $0.time >= time }) ?? (frames.count - 1)
        if upperIndex == 0 {
            let key = frames[0]
            return (key.translation, key.rotation)
        }
        let a = frames[upperIndex - 1]
        let b = frames[upperIndex]
        let span = max(0.0001, b.time - a.time)
        let t = max(0, min(1, (time - a.time) / span))
        let translation = simd_mix(a.translation, b.translation, SIMD3<Float>(repeating: t))
        let qa = simd_quatf(ix: a.rotation.x, iy: a.rotation.y, iz: a.rotation.z, r: a.rotation.w)
        let qb = simd_quatf(ix: b.rotation.x, iy: b.rotation.y, iz: b.rotation.z, r: b.rotation.w)
        let q = simd_slerp(qa, qb, t).vector
        return (translation, SIMD4<Float>(q.x, q.y, q.z, q.w))
    }
}
