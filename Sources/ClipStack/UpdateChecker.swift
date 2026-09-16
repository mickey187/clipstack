import AppKit
import ClipStackCore
import Foundation
import Observation

/// Asks GitHub once a day whether there is a newer release.
///
/// Deliberately minimal: it never downloads, never installs, and never shows a
/// modal. A newer version simply adds an item to the status menu. Every failure
/// — offline, rate limited, malformed response — is a silent no-op, because a
/// clipboard utility has no business interrupting you about GitHub's uptime.
@MainActor
@Observable
final class UpdateChecker {
    static let repository = "mickey187/clipstack"

    /// Set only when the published release is strictly newer than this build.
    private(set) var availableVersion: String?

    private var isChecking = false
    private let lastCheckKey = "ClipStack.lastUpdateCheck"
    private let checkInterval: TimeInterval = 60 * 60 * 24

    var releasesURL: URL {
        URL(string: "https://github.com/\(Self.repository)/releases/latest")!
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Checks at most once per day. Safe to call on every launch.
    func checkIfDue() {
        let last = UserDefaults.standard.object(forKey: lastCheckKey) as? Date
        if let last, Date().timeIntervalSince(last) < checkInterval { return }
        Task { await check() }
    }

    /// Checks regardless of when we last looked, and opens the page if current.
    func checkNow() {
        Task {
            await check()
            if availableVersion == nil {
                // Nothing newer: showing the release page is a more useful answer
                // than an alert saying "you are up to date".
                openReleasesPage()
            }
        }
    }

    func openReleasesPage() {
        NSWorkspace.shared.open(releasesURL)
    }

    private func check() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        guard let latest = await fetchLatestTag() else { return }
        UserDefaults.standard.set(Date(), forKey: lastCheckKey)

        guard let published = SemanticVersion(latest),
              let running = SemanticVersion(currentVersion) else { return }

        availableVersion = published > running ? published.description : nil
    }

    private func fetchLatestTag() async -> String? {
        let url = URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // GitHub rejects API requests without one.
        request.setValue("ClipStack/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String
        else { return nil }

        return tag
    }
}
