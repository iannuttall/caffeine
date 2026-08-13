import Foundation

enum ResourceBundle {
    static let resources: Bundle = {
        let bundleName = "Caffeine_Caffeine"

        if let resourceURL = Bundle.main.resourceURL,
           let packaged = Bundle(url: resourceURL.appendingPathComponent("\(bundleName).bundle"))
        {
            return packaged
        }

        return Bundle.module
    }()
}
