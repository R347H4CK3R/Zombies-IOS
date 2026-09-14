import Foundation

struct BO2ModeValidation: Codable, Hashable, Sendable {
    let mode: BO2ContentMode
    let zone: String
    let renderedRealGeometry: Bool
    let collision: Bool
    let weaponFire: Bool
    let audio: Bool
    let startup: Bool

    var passed: Bool {
        renderedRealGeometry && collision && weaponFire && audio && startup
    }
}

struct FullGameValidationReport: Codable, Sendable {
    var createdAt = Date()
    var modeValidations: [BO2ContentMode: BO2ModeValidation] = [:]
    var requiredAssetClassesComplete = false
    var fallbackGeometryUsed = false
    var placeholderAssetClasses: [String] = []
    var unsignedIPABuilt = false
    var conversionFailures: [String] = []

    mutating func record(
        mode: BO2ContentMode,
        zone: String,
        renderedRealGeometry: Bool,
        collision: Bool,
        weaponFire: Bool,
        audio: Bool,
        startup: Bool
    ) {
        modeValidations[mode] = BO2ModeValidation(
            mode: mode,
            zone: zone,
            renderedRealGeometry: renderedRealGeometry,
            collision: collision,
            weaponFire: weaponFire,
            audio: audio,
            startup: startup
        )
        createdAt = Date()
    }

    var isPlayableRelease: Bool {
        let requiredModes: [BO2ContentMode] = [.campaign, .multiplayer, .zombies]
        return unsignedIPABuilt &&
            requiredAssetClassesComplete &&
            !fallbackGeometryUsed &&
            placeholderAssetClasses.isEmpty &&
            conversionFailures.isEmpty &&
            requiredModes.allSatisfy { modeValidations[$0]?.passed == true }
    }
}
