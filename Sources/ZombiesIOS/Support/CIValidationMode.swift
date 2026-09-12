import Foundation

enum CIValidationMode {
    static let launchArgument = "--ci-gameplay-validation"
    static let environmentKey = "ZOMBIESIOS_CI_GAMEPLAY"

    static var isEnabled: Bool {
        if ProcessInfo.processInfo.arguments.contains(launchArgument) { return true }
        return ProcessInfo.processInfo.environment[environmentKey] == "1"
    }
}
