import Foundation

@MainActor
protocol UpdaterProviding: AnyObject {
    var isAvailable: Bool { get }
    func checkForUpdates()
}

@MainActor
final class DisabledUpdaterController: UpdaterProviding {
    let isAvailable = false
    func checkForUpdates() {}
}

#if canImport(Sparkle) && ENABLE_SPARKLE
import Sparkle

@MainActor
final class SparkleUpdaterController: UpdaterProviding {
    private let controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil)
    let isAvailable = true

    func checkForUpdates() {
        self.controller.checkForUpdates(nil)
    }
}
#endif

@MainActor
func makeUpdaterController() -> any UpdaterProviding {
    let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
    let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
    guard Bundle.main.bundleURL.pathExtension == "app", !feed.isEmpty, !key.isEmpty else {
        return DisabledUpdaterController()
    }
    #if canImport(Sparkle) && ENABLE_SPARKLE
    return SparkleUpdaterController()
    #else
    return DisabledUpdaterController()
    #endif
}
