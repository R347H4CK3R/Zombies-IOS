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
    }

    var canEnterRuntime: Bool {
        !availableAreas.isEmpty && !containerFiles.isEmpty
    }
}
