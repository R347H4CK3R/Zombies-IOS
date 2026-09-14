import Foundation

struct BO2ZoneDependencyResolver: Sendable {
    let catalog: BO2ContentCatalog

    func descriptor(mode: BO2ContentMode, zone: String) -> BO2LaunchDescriptor {
        let normalizedZone = zone.lowercased()
        var selected = Set<String>()

        for path in catalog.paths(for: .common) where isRuntimeResource(path) {
            selected.insert(path)
        }

        for path in catalog.paths(for: mode) where isRuntimeResource(path) {
            let stem = ((path as NSString).lastPathComponent as NSString)
                .deletingPathExtension
                .lowercased()
            if stem == normalizedZone ||
                stem.hasPrefix(normalizedZone + "_") ||
                isModeShared(stem: stem, mode: mode) {
                selected.insert(path)
            }
        }

        return BO2LaunchDescriptor(
            mode: mode,
            zone: zone,
            resources: selected.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        )
    }

    private func isRuntimeResource(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return ["ff", "ipak", "sabs", "sabl", "gsc", "csc", "cfg", "csv", "str", "menu", "vision"].contains(ext)
    }

    private func isModeShared(stem: String, mode: BO2ContentMode) -> Bool {
        switch mode {
        case .campaign:
            return stem.contains("_sp") || stem.hasPrefix("sp_") || stem.contains("campaign")
        case .multiplayer:
            return stem.contains("_mp") || stem.hasPrefix("mp_") || stem.contains("multiplayer")
        case .zombies:
            return stem.contains("_zm") || stem.hasPrefix("zm_") || stem.hasPrefix("zmb_") || stem.contains("zombie")
        case .common:
            return true
        }
    }
}
