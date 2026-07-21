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
                return "GitHub 返回了无效的响应，请稍后再试。"
            case .missingAppVersion:
                return "无法读取当前应用版本。"
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
                    title: "已经是最新版本",
                    message: "当前版本：\(currentVersion)\n最新版本：\(latestVersion)"
                )
            }
        } catch {
            guard alwaysShowResult else { return }
            presentInformationAlert(title: "无法检查更新", message: error.localizedDescription)
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
        alert.messageText = "发现新版本 \(latestVersion)"
        alert.informativeText = "当前版本为 \(currentVersion)。新版本已经发布，是否前往 GitHub Release 页面下载？"
        alert.addButton(withTitle: "前往下载")
        alert.addButton(withTitle: "稍后")
        alert.addButton(withTitle: "此版本不再提示")

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
        alert.addButton(withTitle: "确定")
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
