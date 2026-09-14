import Foundation

enum BO2ContentMode: String, Codable, CaseIterable, Sendable {
    case campaign
    case multiplayer
    case zombies
    case common
}

struct BO2ContentClassifier {
    private static let knownConvertibleExtensions: Set<String> = [
        "ff", "ipak", "sabs", "sabl", "clump",
        "gsc", "csc", "cfg", "csv", "str", "menu", "vision",
        "iwi", "dds", "png", "jpg", "jpeg", "tga",
        "wav", "mp3", "at3", "at9", "wem", "xma",
        "webm", "bik",
        "xmodel", "xmodel_bin", "xanim", "xanim_bin", "material",
        "json", "txt"
    ]

    private static let excludedNames: Set<String> = [
        "eboot.bin", "param.sfo", "icon0.png", "pic0.png", "pic1.png",
        "ps3_disc.sfb", "ps3logo.dat"
    ]

    private static let excludedExtensions: Set<String> = [
        "self", "sprx", "prx", "pup", "sfo", "sfb"
    ]

    static func isConvertibleResource(path: String) -> Bool {
        let normalized = path
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
        let filename = (normalized as NSString).lastPathComponent
        let ext = (filename as NSString).pathExtension.lowercased()

        guard !filename.hasPrefix("._"),
              !normalized.contains("/__macosx/"),
              !excludedNames.contains(filename),
              !excludedExtensions.contains(ext),
              !ext.isEmpty else {
            return false
        }

        // A complete BO2 dump contains many retail data extensions that are not
        // individually documented (including Bink/WebM movies and packed clumps).
        // Treat every non-platform file below USRDIR as game data so the full-game
        // inventory cannot silently omit an asset class. For unit fixtures and
        // directly selected language folders, retain the known-extension path.
        if normalized.contains("usrdir/") {
            return true
        }
        if normalized.contains("ps3_game/") {
            return false
        }
        return knownConvertibleExtensions.contains(ext)
    }

    static func classify(path: String) -> BO2ContentMode {
        let normalized = path
            .replacingOccurrences(of: "\\", with: "/")
            .lowercased()
        let filename = (normalized as NSString).lastPathComponent
        let stem = (filename as NSString).deletingPathExtension

        if isZombies(stem: stem, path: normalized) { return .zombies }
        if isMultiplayer(stem: stem, path: normalized) { return .multiplayer }
        if isCampaign(stem: stem, path: normalized) { return .campaign }
        return .common
    }

    private static func isZombies(stem: String, path: String) -> Bool {
        let tokens = tokenSet(stem)
        return stem.hasPrefix("zm_") ||
            stem.hasPrefix("zmb_") ||
            tokens.contains("zm") ||
            tokens.contains("zmb") ||
            stem.contains("zombie") ||
            stem.contains("zclassic") ||
            stem.contains("zencounter") ||
            stem.contains("zsurvival") ||
            stem.contains("transit") ||
            path.contains("/zombies/")
    }

    private static func isMultiplayer(stem: String, path: String) -> Bool {
        let tokens = tokenSet(stem)
        return stem.hasPrefix("mp_") ||
            tokens.contains("mp") ||
            stem.hasPrefix("multiplayer_") ||
            path.contains("/multiplayer/") ||
            path.contains("/mp/")
    }

    private static func isCampaign(stem: String, path: String) -> Bool {
        let tokens = tokenSet(stem)
        return stem.hasPrefix("sp_") ||
            tokens.contains("sp") ||
            stem.hasPrefix("campaign_") ||
            path.contains("/campaign/") ||
            path.contains("/sp/")
    }

    private static func tokenSet(_ value: String) -> Set<Substring> {
        Set(value.split { !$0.isLetter && !$0.isNumber })
    }
}

struct BO2ContentCatalog: Codable, Sendable {
    let filesByMode: [BO2ContentMode: [String]]

    init(paths: [String]) {
        var grouped: [BO2ContentMode: [String]] = [:]
        for mode in BO2ContentMode.allCases {
            grouped[mode] = []
        }
        for path in paths where BO2ContentClassifier.isConvertibleResource(path: path) {
            grouped[BO2ContentClassifier.classify(path: path), default: []].append(path)
        }
        self.filesByMode = grouped.mapValues {
            $0.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
    }

    func paths(for mode: BO2ContentMode) -> [String] {
        filesByMode[mode] ?? []
    }

    func count(for mode: BO2ContentMode) -> Int {
        paths(for: mode).count
    }
}
