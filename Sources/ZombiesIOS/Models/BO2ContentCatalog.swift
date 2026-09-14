import Foundation

enum BO2ContentMode: String, Codable, CaseIterable, Sendable {
    case campaign
    case multiplayer
    case zombies
    case common
}

struct BO2ContentClassifier {
    static func classify(path: String) -> BO2ContentMode {
        let normalized = path
            .replacingOccurrences(of: "\\", with: "/")
            .lowercased()
        let filename = (normalized as NSString).lastPathComponent
        let stem = (filename as NSString).deletingPathExtension

        // Mode-specific markers must win over broad shared names such as
        // common_zm, patch_ui_zm, and code_post_gfx_mp.
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
        for path in paths {
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
