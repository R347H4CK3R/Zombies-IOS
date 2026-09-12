import Foundation

enum TranzitDependencyRole: String, Codable, Hashable, CaseIterable {
    case zone
    case sharedZone
    case imageContainer
    case materialContainer
    case modelContainer
    case weaponContainer
    case animationContainer
    case scriptContainer
    case audioBank
    case auxiliary
}

enum TranzitDependencyRequirement: String, Codable, Hashable, CaseIterable {
    case required
    case optional
    case deferred

    fileprivate var priority: Int {
        switch self {
        case .required: return 3
        case .optional: return 2
        case .deferred: return 1
        }
    }
}

struct TranzitDependency: Codable, Hashable {
    let relativePath: String
    let role: TranzitDependencyRole
    let requirement: TranzitDependencyRequirement
    let byteCount: Int64
    let sha256: String
    let modifiedAt: Date?
    let runtimeArtifactKeys: [String]

    init(
        relativePath: String,
        role: TranzitDependencyRole,
        requirement: TranzitDependencyRequirement,
        byteCount: Int64,
        sha256: String,
        modifiedAt: Date?,
        runtimeArtifactKeys: [String] = []
    ) {
        self.relativePath = relativePath
        self.role = role
        self.requirement = requirement
        self.byteCount = byteCount
        self.sha256 = sha256
        self.modifiedAt = modifiedAt
        self.runtimeArtifactKeys = runtimeArtifactKeys.sorted()
    }

    var normalizedRelativePath: String {
        Self.normalize(relativePath)
    }

    static func normalize(_ path: String) -> String {
        let unified = path.replacingOccurrences(of: "\\", with: "/")
        var components: [String] = []

        for raw in unified.split(separator: "/", omittingEmptySubsequences: true) {
            let component = String(raw)
            switch component {
            case ".":
                continue
            case "..":
                if !components.isEmpty {
                    components.removeLast()
                }
            default:
                components.append(component)
            }
        }

        return components.joined(separator: "/")
    }

    var hasUnsafeAbsoluteOrTraversalPath: Bool {
        let unified = relativePath.replacingOccurrences(of: "\\", with: "/")
        if unified.hasPrefix("/") { return true }
        if unified.range(of: #"^[A-Za-z]:/"#, options: .regularExpression) != nil { return true }

        var depth = 0
        for raw in unified.split(separator: "/", omittingEmptySubsequences: true) {
            switch raw {
            case ".":
                continue
            case "..":
                if depth == 0 { return true }
                depth -= 1
            default:
                depth += 1
            }
        }
        return false
    }
}

struct TranzitDependencyManifest: Codable, Hashable {
    let entries: [TranzitDependency]

    init(entries: [TranzitDependency]) {
        var byPath: [String: TranzitDependency] = [:]

        for entry in entries where !entry.hasUnsafeAbsoluteOrTraversalPath {
            let key = entry.normalizedRelativePath
            guard !key.isEmpty else { continue }

            if let existing = byPath[key] {
                if entry.requirement.priority > existing.requirement.priority {
                    byPath[key] = entry
                } else if entry.requirement.priority == existing.requirement.priority {
                    byPath[key] = Self.preferred(existing, entry)
                }
            } else {
                byPath[key] = entry
            }
        }

        self.entries = byPath
            .map { key, value in
                TranzitDependency(
                    relativePath: key,
                    role: value.role,
                    requirement: value.requirement,
                    byteCount: value.byteCount,
                    sha256: value.sha256,
                    modifiedAt: value.modifiedAt,
                    runtimeArtifactKeys: value.runtimeArtifactKeys
                )
            }
            .sorted {
                if $0.requirement.priority != $1.requirement.priority {
                    return $0.requirement.priority > $1.requirement.priority
                }
                if $0.normalizedRelativePath != $1.normalizedRelativePath {
                    return $0.normalizedRelativePath < $1.normalizedRelativePath
                }
                return $0.role.rawValue < $1.role.rawValue
            }
    }

    private static func preferred(_ lhs: TranzitDependency, _ rhs: TranzitDependency) -> TranzitDependency {
        let left = (lhs.sha256, lhs.role.rawValue, lhs.byteCount, lhs.runtimeArtifactKeys.joined(separator: "|"))
        let right = (rhs.sha256, rhs.role.rawValue, rhs.byteCount, rhs.runtimeArtifactKeys.joined(separator: "|"))
        return String(describing: left) <= String(describing: right) ? lhs : rhs
    }
}
