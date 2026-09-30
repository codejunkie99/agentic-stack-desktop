import Foundation
import Sparkle

@MainActor
final class AppUpdater {
    private let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: !ProcessInfo.processInfo.arguments.contains("--jev-ui-fixture") && !ProcessInfo.processInfo.arguments.contains("--jev-search-fixture"),
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
