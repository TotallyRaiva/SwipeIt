//
//  UpdateChecker.swift
//  SwipeIt
//
//  Created by Reiwa on 18.10.2026.
//

import Foundation
import Observation
import AppKit

/// Model representing release metadata retrieved from GitHub Releases.
public struct GitHubRelease: Decodable, Sendable {
    public let tagName: String
    public let name: String?
    public let body: String?
    public let htmlUrl: String
    public let publishedAt: String?
    public let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlUrl = "html_url"
        case publishedAt = "published_at"
        case assets
    }
}

public struct GitHubAsset: Decodable, Sendable {
    public let name: String
    public let browserDownloadUrl: String
    public let size: Int?

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
        case size
    }
}

/// Service that checks GitHub Releases for new SwipeIt versions and manages update prompts.
@Observable
@MainActor
public final class UpdateChecker {
    public private(set) var isChecking: Bool = false
    public private(set) var updateAvailable: Bool = false
    public private(set) var latestVersion: String?
    public private(set) var releaseTitle: String?
    public private(set) var releaseNotes: String?
    public private(set) var downloadURL: URL?
    public private(set) var releasePageURL: URL?
    public private(set) var lastCheckedDate: Date?
    public private(set) var statusMessage: String?
    public private(set) var isManualCheck: Bool = false

    private let repoOwner: String
    private let repoName: String
    private let session: URLSession

    public init(
        repoOwner: String = "TotallyRaiva",
        repoName: String = "SwipeIt",
        session: URLSession = .shared
    ) {
        self.repoOwner = repoOwner
        self.repoName = repoName
        self.session = session
    }

    /// Current running app version (e.g. "1.0.1")
    public var currentAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.1"
    }

    /// Compares two semver version strings (e.g., "1.0.2" vs "1.0.1").
    /// Returns true if `candidate` is strictly newer than `current`.
    public static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let cleanCandidate = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "vV ."))
        let cleanCurrent = current.trimmingCharacters(in: CharacterSet(charactersIn: "vV ."))

        let candidateParts = cleanCandidate.split(separator: ".").compactMap { Int($0) }
        let currentParts = cleanCurrent.split(separator: ".").compactMap { Int($0) }

        let maxCount = max(candidateParts.count, currentParts.count)
        for i in 0..<maxCount {
            let candidateVal = i < candidateParts.count ? candidateParts[i] : 0
            let currentVal = i < currentParts.count ? currentParts[i] : 0
            if candidateVal > currentVal {
                return true
            } else if candidateVal < currentVal {
                return false
            }
        }
        return false
    }

    /// Performs an asynchronous update check against GitHub Releases API.
    /// - Parameters:
    ///   - manual: True if triggered by user action ("Check Now"), False if background startup check.
    ///   - settings: SettingsStore to read preferences and record timestamps.
    public func checkForUpdates(manual: Bool = false, settings: SettingsStore? = nil) async {
        guard !isChecking else { return }

        // Background check guards: respect setting and throttle to once every 4 hours
        if !manual, let settings = settings {
            guard settings.automaticallyCheckForUpdates else { return }
            let now = Date().timeIntervalSince1970
            let fourHours: Double = 4 * 60 * 60
            if now - settings.lastUpdateCheckTimestamp < fourHours {
                return
            }
        }

        isChecking = true
        isManualCheck = manual
        statusMessage = manual ? "Checking for updates…" : nil

        defer {
            isChecking = false
        }

        let apiURLString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
        guard let url = URL(string: apiURLString) else {
            if manual {
                statusMessage = "Invalid update URL."
            }
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("SwipeIt-App/\(currentAppVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                if manual {
                    statusMessage = "Unable to fetch release details from GitHub."
                }
                return
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let checkTime = Date()
            lastCheckedDate = checkTime
            settings?.lastUpdateCheckTimestamp = checkTime.timeIntervalSince1970

            let remoteVersion = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            let hasNewer = Self.isVersion(remoteVersion, newerThan: currentAppVersion)

            latestVersion = remoteVersion
            releaseTitle = release.name ?? release.tagName
            releaseNotes = release.body
            releasePageURL = URL(string: release.htmlUrl)

            // Look for SwipeIt.dmg in release assets; fallback to latest download link
            if let dmgAsset = release.assets.first(where: { $0.name.hasSuffix(".dmg") }),
               let assetUrl = URL(string: dmgAsset.browserDownloadUrl) {
                downloadURL = assetUrl
            } else {
                downloadURL = URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases/latest/download/SwipeIt.dmg")
            }

            if hasNewer {
                updateAvailable = true
                statusMessage = "New version \(remoteVersion) available!"
            } else {
                updateAvailable = false
                if manual {
                    statusMessage = "SwipeIt is up to date (v\(currentAppVersion))."
                } else {
                    statusMessage = nil
                }
            }
        } catch {
            if manual {
                statusMessage = "Update check failed. Check your internet connection."
            }
        }
    }

    /// Opens the direct DMG download link in the user's default browser / download manager.
    public func openDownload() {
        let url = downloadURL ?? URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases/latest/download/SwipeIt.dmg")!
        NSWorkspace.shared.open(url)
    }

    /// Opens the full GitHub release page in the browser.
    public func openReleasePage() {
        let url = releasePageURL ?? URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases/latest")!
        NSWorkspace.shared.open(url)
    }

    /// Dismisses the update banner temporarily for this session.
    public func dismissUpdate() {
        updateAvailable = false
        statusMessage = nil
    }
}
