import AppKit

enum CaffeineAssets {
    private static let resourceBundle: Bundle = {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return Bundle.module }
        let packagedBundleURL = Bundle.main.resourceURL?
            .appendingPathComponent("Caffeine_Caffeine.bundle", isDirectory: true)
        guard let packagedBundleURL, let bundle = Bundle(url: packagedBundleURL) else {
            fatalError("Could not load packaged Caffeine resources.")
        }
        return bundle
    }()

    static func statusImage(active: Bool) -> NSImage {
        let name = active ? "active" : "inactive"
        let image = NSImage(size: NSSize(width: 22, height: 20))

        for resource in [name, "\(name)@2x"] {
            guard let url = self.resourceBundle.url(forResource: resource, withExtension: "png"),
                  let source = NSImage(contentsOf: url)
            else { continue }
            for representation in source.representations {
                representation.size = image.size
                image.addRepresentation(representation)
            }
        }

        image.isTemplate = true
        image.accessibilityDescription = active ? "Caffeine active" : "Caffeine inactive"
        return image
    }

    static func cupImage() -> NSImage {
        guard let url = self.resourceBundle.url(forResource: "Cup", withExtension: "png"),
              let image = NSImage(contentsOf: url)
        else { return NSImage() }
        return image
    }
}
