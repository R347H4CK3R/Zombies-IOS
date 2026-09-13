import Foundation

enum BO2MapTarget: String, CaseIterable, Identifiable {
    case hijacked = "mp_hijacked"

    var id: String { rawValue }
    var displayName: String {
        switch self { case .hijacked: return "Hijacked" }
    }
    var fastFileName: String { rawValue + ".ff" }
    var ipakName: String { rawValue + ".ipak" }
    var audioName: String {
        switch self { case .hijacked: return "mpl_hijacked.all.sabs" }
    }
}
