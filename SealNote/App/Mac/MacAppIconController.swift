import AppKit

@MainActor
final class MacAppIconController {
    static let shared = MacAppIconController()

    private init() {}

    func apply(theme: AppTheme) {
        guard let image = Self.image(for: theme) else { return }
        NSApp.applicationIconImage = image
    }

    static func image(for theme: AppTheme) -> NSImage? {
        let resourceName = theme.macAppIconResourceName
        if let image = NSImage(named: NSImage.Name(resourceName)), image.isValid {
            return image
        }

        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "icns"),
              let image = NSImage(contentsOf: url),
              image.isValid else {
            return nil
        }
        return image
    }
}

private extension AppTheme {
    var macAppIconResourceName: String {
        switch self {
        case .pink: return "Icon"
        case .cyan: return "Icon2"
        case .green: return "Icon3"
        }
    }
}
