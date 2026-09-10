import Foundation

enum TranzitArea: String, CaseIterable, Identifiable {
    case bridge
    case busstation
    case cornfield
    case diner
    case farm
    case forest
    case forest2
    case labs
    case powerstation
    case town
    case tunnel

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bridge: return "Bridge"
        case .busstation: return "Bus Station"
        case .cornfield: return "Cornfield"
        case .diner: return "Diner"
        case .farm: return "Farm"
        case .forest: return "Forest"
        case .forest2: return "Forest 2"
        case .labs: return "Labs"
        case .powerstation: return "Power Station"
        case .town: return "Town"
        case .tunnel: return "Tunnel"
        }
    }

    var fastFileStem: String { "zm_transit_gump_\(rawValue)" }
}

struct TranzitRuntimeIndex {
    let availableAreas: [TranzitArea]
    let containerFiles: [ScannedFile]
    let audioBanks: [ScannedFile]
    let embeddedReferences: [AssetReference]
    let firstPlayableArea: TranzitArea?
    let firstPlayableFastFile: ScannedFile?

    init(report: ScanReport) {
        let names = Set(report.files.map { $0.name.lowercased() })

        availableAreas = TranzitArea.allCases.filter { area in
            names.contains(area.fastFileStem + ".ff")
        }

        containerFiles = report.files.filter {
            ["ff", "ipak"].contains($0.fileExtension.lowercased())
        }

        audioBanks = report.files.filter {
            ["sabs", "sabl"].contains($0.fileExtension.lowercased())
        }

        embeddedReferences = report.files.flatMap {
            $0.inspection?.embeddedAssetReferences ?? []
        }

        // Do not pick tiny preallocation/stub fastfiles as a playable target.
        // Among real Tranzit area fastfiles, start with the smallest payload so
        // the native gameplay/rendering loop can be proven with minimal memory.
        let usableAreas: [(TranzitArea, ScannedFile)] = TranzitArea.allCases.compactMap { area in
            guard let file = report.files.first(where: {
                $0.name.lowercased() == area.fastFileStem + ".ff" && $0.size > 4_096
            }) else { return nil }
            return (area, file)
        }
        .sorted { $0.1.size < $1.1.size }

        firstPlayableArea = usableAreas.first?.0
        firstPlayableFastFile = usableAreas.first?.1
    }

    var canEnterRuntime: Bool {
        firstPlayableArea != nil && !containerFiles.isEmpty
    }
}
