#if os(macOS)
import AppKit
import Foundation

@MainActor
final class GitHubReleaseUpdateChecker {
    static let shared = GitHubReleaseUpdateChecker()

    private struct Release: Decodable {
        let tagName: String
        let pageURL: URL

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case pageURL = "html_url"
        }
    }

    private enum UpdateCheckError: LocalizedError {
        case invalidResponse
        case missingAppVersion

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return L10n.string("GitHub returned an invalid response. Try again later.")
            case .missingAppVersion:
                return L10n.string("The current app version could not be read.")
            }
        }
    }

    private let latestReleaseURL = URL(
        string: "https://api.github.com/repos/XuWeinan123/EncryptNotes_for_TRAE/releases/latest"
    )!
    private let releasesPageURL = URL(
        string: "https://github.com/XuWeinan123/EncryptNotes_for_TRAE/releases"
    )!
    private let skippedReleaseVersionKey = "githubReleaseUpdateChecker.skippedVersion"

    private init() {}

    func checkForUpdates(alwaysShowResult: Bool = false) async {
        do {
            let release = try await fetchLatestRelease()
            guard let currentVersion = Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String else {
                throw UpdateCheckError.missingAppVersion
            }

            let latestVersion = Self.normalizedVersion(release.tagName)
            let skippedVersion = UserDefaults.standard.string(forKey: skippedReleaseVersionKey)
            if Self.isVersion(latestVersion, newerThan: currentVersion),
               skippedVersion != latestVersion {
                presentUpdateAlert(
                    release: release,
                    currentVersion: currentVersion,
                    recordsSuppression: true
                )
            } else if alwaysShowResult {
                presentInformationAlert(
                    title: L10n.string("Seal Note Is Up to Date"),
                    message: L10n.string("Current version: %@\nLatest version: %@", currentVersion, latestVersion)
                )
            }
        } catch {
            guard alwaysShowResult else { return }
            presentInformationAlert(title: L10n.string("Could Not Check for Updates"), message: error.localizedDescription)
        }
    }

    func presentUpdateAlertPreview() {
        let currentVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.6"
        let release = Release(
            tagName: "v\(Self.previewVersion(after: currentVersion))",
            pageURL: releasesPageURL
        )
        presentUpdateAlert(
            release: release,
            currentVersion: currentVersion,
            recordsSuppression: false
        )
    }

    private func fetchLatestRelease() async throws -> Release {
        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Seal-Note", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw UpdateCheckError.invalidResponse
        }
        return try Foundation.JSONDecoder().decode(Release.self, from: data)
    }

    private func presentUpdateAlert(
        release: Release,
        currentVersion: String,
        recordsSuppression: Bool
    ) {
        let latestVersion = Self.normalizedVersion(release.tagName)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.string("New Version %@ Available", latestVersion)
        alert.informativeText = L10n.string("You are using version %@. Would you like to download the new version from GitHub Releases?", currentVersion)
        alert.addButton(withTitle: L10n.string("Download"))
        alert.addButton(withTitle: L10n.string("Later"))
        alert.addButton(withTitle: L10n.string("Skip This Version"))

        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(release.pageURL)
        case .alertThirdButtonReturn where recordsSuppression:
            UserDefaults.standard.set(latestVersion, forKey: skippedReleaseVersionKey)
        default:
            break
        }
    }

    private func presentInformationAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: L10n.string("OK"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let candidateParts = versionComponents(candidate)
        let currentParts = versionComponents(current)
        let count = max(candidateParts.count, currentParts.count)

        for index in 0..<count {
            let candidatePart = index < candidateParts.count ? candidateParts[index] : 0
            let currentPart = index < currentParts.count ? currentParts[index] : 0
            if candidatePart != currentPart {
                return candidatePart > currentPart
            }
        }
        return false
    }

    private static func versionComponents(_ version: String) -> [Int] {
        normalizedVersion(version)
            .split(separator: ".")
            .map { component in
                Int(component.prefix(while: { $0.isNumber })) ?? 0
            }
    }

    private static func normalizedVersion(_ version: String) -> String {
        version.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    }

    private static func previewVersion(after currentVersion: String) -> String {
        var components = versionComponents(currentVersion)
        guard !components.isEmpty else { return "1.0" }
        components[components.count - 1] += 1
        return components.map(String.init).joined(separator: ".")
    }
}
#endif
