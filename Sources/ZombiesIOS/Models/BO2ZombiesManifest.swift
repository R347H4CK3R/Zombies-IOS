import Foundation

enum BO2ZombiesManifest {
    /// BO2 PS3 paths selected from the cleaned Zombies-only manifest.
    /// Matching is case-insensitive and accepts the dump root, PS3_GAME,
    /// USRDIR, english, or another selected folder containing these files.
    static let relativePaths: Set<String> = [
        "PS3_GAME/USRDIR/english/code_post_gfx_1080_zm.ff",
        "PS3_GAME/USRDIR/english/code_post_gfx_720_zm.ff",
        "PS3_GAME/USRDIR/english/code_post_gfx_zm.ff",
        "PS3_GAME/USRDIR/english/code_post_gfx_zm.ipak",
        "PS3_GAME/USRDIR/english/common_zm.ff",
        "PS3_GAME/USRDIR/english/common_zm.ipak",
        "PS3_GAME/USRDIR/english/dev_zm.ff",
        "PS3_GAME/USRDIR/english/patch_ui_zm.ff",
        "PS3_GAME/USRDIR/english/patch_zm.ff",
        "PS3_GAME/USRDIR/english/so_zclassic_zm_transit.ff",
        "PS3_GAME/USRDIR/english/so_zclassic_zm_transit.ipak",
        "PS3_GAME/USRDIR/english/so_zencounter_zm_transit.ff",
        "PS3_GAME/USRDIR/english/so_zencounter_zm_transit.ipak",
        "PS3_GAME/USRDIR/english/so_zsurvival_zm_transit.ff",
        "PS3_GAME/USRDIR/english/so_zsurvival_zm_transit.ipak",
        "PS3_GAME/USRDIR/english/ui_viewer_zm.ff",
        "PS3_GAME/USRDIR/english/ui_viewer_zm.ipak",
        "PS3_GAME/USRDIR/english/ui_zm.ff",
        "PS3_GAME/USRDIR/english/zm_transit.ff",
        "PS3_GAME/USRDIR/english/zm_transit.ipak",
        "PS3_GAME/USRDIR/english/zm_transit_common.ipak",
        "PS3_GAME/USRDIR/english/zm_transit_gump_bridge.ff",
        "PS3_GAME/USRDIR/english/zm_transit_gump_busstation.ff",
        "PS3_GAME/USRDIR/english/zm_transit_gump_cornfield.ff",
        "PS3_GAME/USRDIR/english/zm_transit_gump_diner.ff",
        "PS3_GAME/USRDIR/english/zm_transit_gump_farm.ff",
        "PS3_GAME/USRDIR/english/zm_transit_gump_forest.ff",
        "PS3_GAME/USRDIR/english/zm_transit_gump_forest2.ff",
        "PS3_GAME/USRDIR/english/zm_transit_gump_labs.ff",
        "PS3_GAME/USRDIR/english/zm_transit_gump_powerstation.ff",
        "PS3_GAME/USRDIR/english/zm_transit_gump_prealloc_0.ff",
        "PS3_GAME/USRDIR/english/zm_transit_gump_prealloc_1.ff",
        "PS3_GAME/USRDIR/english/zm_transit_gump_prealloc_2.ff",
        "PS3_GAME/USRDIR/english/zm_transit_gump_prealloc_3.ff",
        "PS3_GAME/USRDIR/english/zm_transit_gump_town.ff",
        "PS3_GAME/USRDIR/english/zm_transit_gump_tunnel.ff",
        "PS3_GAME/USRDIR/english/zm_transit_patch.ff",
        "PS3_GAME/USRDIR/english/zmb_classic_transit.all.sabs",
        "PS3_GAME/USRDIR/english/zmb_classic_transit.english.sabs"
    ]

    static let normalizedPaths: Set<String> = Set(relativePaths.map(normalize))

    static func contains(_ path: String) -> Bool {
        let normalized = normalize(path)
        if normalizedPaths.contains(normalized) { return true }

        // A dump may be wrapped in another directory before PS3_GAME.
        if let range = normalized.range(of: "ps3_game/") {
            let trimmed = String(normalized[range.lowerBound...])
            if normalizedPaths.contains(trimmed) { return true }
        }

        // When the user selects PS3_GAME, USRDIR, or english directly, the
        // enumerator returns a path relative to that selected folder. Match that
        // relative suffix while keeping the report path usable directly under
        // the selected root (no app-container copy is required).
        return normalizedPaths.contains { canonical in
            canonical.hasSuffix("/" + normalized)
        }
    }

    private static func normalize(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
    }
}
