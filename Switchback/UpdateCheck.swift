import Foundation

/// The update check's rules (v0.7 U1–U3), free of networking and UI so they're
/// tested directly. `UpdateChecker` does the fetching and remembering.
///
/// Crossbar has its own copy of this file with its own `Product`; keep them in step.
/// Extract a shared package when a third app needs it (rule of three).
enum UpdateCheck {
    struct Product {
        /// As it appears in sentences: "Switchback 0.7.1 is available".
        let displayName: String
        /// `owner/repo` on GitHub.
        let repo: String
        let caskName: String

        var latestReleaseAPI: URL { URL(string: "https://api.github.com/repos/\(repo)/releases/latest")! }
        var releasesPage: URL { URL(string: "https://github.com/\(repo)/releases")! }
        var brewCommand: String { "brew upgrade --cask \(caskName)" }
    }

    static let product = Product(displayName: "Switchback", repo: "breed007/switchback-macos", caskName: "switchback")

    /// How often to check, at most.
    static let interval: TimeInterval = 24 * 60 * 60

    /// A version like 0.7.1, compared numerically by component, so 0.10.0 is newer
    /// than 0.9.2 and 0.7 equals 0.7.0.
    struct Version: Comparable, CustomStringConvertible {
        let components: [Int]

        /// Accepts "0.7.1" or "v0.7.1". Nil for anything else ("0.7.1-beta", "").
        init?(_ text: String) {
            let trimmed = text.hasPrefix("v") ? String(text.dropFirst()) : text
            let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
            guard (1...4).contains(parts.count) else { return nil }
            var numbers: [Int] = []
            for part in parts {
                guard !part.isEmpty, part.allSatisfy(\.isASCII), part.allSatisfy(\.isNumber),
                      let number = Int(part) else { return nil }
                numbers.append(number)
            }
            components = numbers
        }

        static func < (a: Version, b: Version) -> Bool {
            for index in 0..<max(a.components.count, b.components.count) {
                let x = index < a.components.count ? a.components[index] : 0
                let y = index < b.components.count ? b.components[index] : 0
                if x != y { return x < y }
            }
            return false
        }

        static func == (a: Version, b: Version) -> Bool { !(a < b) && !(b < a) }

        var description: String { components.map(String.init).joined(separator: ".") }
    }

    struct Release: Equatable {
        let version: Version
        let url: URL
    }

    /// The release in a GitHub `releases/latest` response, or nil if the response
    /// isn't one: a bad tag, or a page that isn't under this repo's releases. The URL
    /// check matters because the app opens it.
    static func parseLatest(_ data: Data, for product: Product = product) -> Release? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = object["tag_name"] as? String, let version = Version(tag),
              let link = object["html_url"] as? String, let url = URL(string: link),
              isReleasePage(url, for: product)
        else { return nil }
        return Release(version: version, url: url)
    }

    /// An https page under github.com/<repo>/releases/.
    static func isReleasePage(_ url: URL, for product: Product = product) -> Bool {
        guard url.scheme == "https", url.host == "github.com", url.user == nil, url.port == nil else { return false }
        let path = url.standardized.path
        return path.hasPrefix("/\(product.repo)/releases/") && !path.contains("/../")
    }

    /// The release, if it's newer than what's installed.
    static func update(_ release: Release?, over installed: Version) -> Release? {
        guard let release, installed < release.version else { return nil }
        return release
    }

    /// Whether a scheduled check is due.
    static func isDue(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck else { return true }
        // A clock set backward shouldn't stop checks for good.
        return now.timeIntervalSince(lastCheck) >= interval || lastCheck > now
    }

    /// Installed with Homebrew: the cask's Caskroom folder exists.
    static func installedWithHomebrew(_ product: Product = product,
                                      fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> Bool {
        ["/opt/homebrew/Caskroom", "/usr/local/Caskroom"].contains { fileExists("\($0)/\(product.caskName)") }
    }

    /// The managed `DisableUpdateCheck` preference. Only a value an administrator
    /// forced (MDM) counts; a user can't set it to hide the option from themselves
    /// by accident, and doesn't need to: they can just turn the check off.
    static let managedDisableKey = "DisableUpdateCheck"

    static func disabledByPolicy(isForced: (String) -> Bool, value: (String) -> Any?) -> Bool {
        isForced(managedDisableKey) && (value(managedDisableKey) as? Bool ?? false)
    }

    /// The live managed-preference reading, for `disabledByPolicy`.
    static func disabledByPolicy(bundleID: String) -> Bool {
        disabledByPolicy(isForced: { CFPreferencesAppValueIsForced($0 as CFString, bundleID as CFString) },
                         value: { CFPreferencesCopyAppValue($0 as CFString, bundleID as CFString) })
    }
}
