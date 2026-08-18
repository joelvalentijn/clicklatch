// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Joël in 't Veld

import AppKit
import Foundation
import Observation

/// Downloads and installs a newer ClickLocker.
///
/// The security of this rests on one check: an update is only installed when the
/// downloaded bundle satisfies the *running* app's designated requirement. Whoever
/// controls the feed still cannot get code onto the machine that was not signed
/// with the same key. That does mean an ad hoc signed build can never update
/// itself — its requirement is the hash of that one binary, which a new build can
/// never match. The updater says so rather than installing something unverified.
@MainActor
@Observable
final class Updater {

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String)
        case downloading(progress: Double)
        case readyToInstall(version: String)
        case failed(reason: String)
    }

    /// Where releases live. Overridable through the `updateFeedURL` default, which
    /// is what makes the whole chain testable before a real release exists.
    static let defaultFeedURL =
        "https://api.github.com/repos/joelvalentijn/clicklocker/releases/latest"

    private enum Marker {
        static let previousVersion = "updatePreviousVersion"
        static let wasTrusted = "updateWasTrusted"
    }

    private(set) var state: State = .idle
    private(set) var lastCheck: Date?

    private var pendingRelease: Release?
    private var downloadedApp: URL?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Version of this build

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private var feedURL: URL? {
        URL(string: defaults.string(forKey: "updateFeedURL") ?? Self.defaultFeedURL)
    }

    // MARK: - Checking

    struct Release: Equatable {
        var version: String
        var downloadURL: URL
    }

    func check(automatic: Bool = false) async {
        if automatic, let lastCheck, Date().timeIntervalSince(lastCheck) < 23 * 3600 { return }

        state = .checking
        lastCheck = Date()

        guard let feedURL else {
            state = .failed(reason: "The update address is not a valid URL.")
            return
        }

        do {
            var request = URLRequest(url: feedURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)

            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                // A repository without any release answers 404 here, which is not
                // an error worth alarming anyone about.
                state = http.statusCode == 404
                    ? .failed(reason: "No release has been published yet.")
                    : .failed(reason: "The update server answered with status \(http.statusCode).")
                return
            }

            guard let release = Self.parseRelease(from: data) else {
                state = .failed(reason: "Could not make sense of the update information.")
                return
            }

            if Self.isNewer(release.version, than: currentVersion) {
                pendingRelease = release
                state = .available(version: release.version)
            } else {
                pendingRelease = nil
                state = .upToDate
            }
        } catch {
            state = .failed(reason: error.localizedDescription)
        }
    }

    /// Pulls the version and the zip asset out of a GitHub release document.
    static func parseRelease(from data: Data) -> Release? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let assets = json["assets"] as? [[String: Any]]
        else { return nil }

        let zip = assets.first { ($0["name"] as? String)?.hasSuffix(".zip") == true }
        guard let urlString = zip?["browser_download_url"] as? String,
              let url = URL(string: urlString)
        else { return nil }

        return Release(version: normalise(tag), downloadURL: url)
    }

    /// Strips a leading `v` so `v1.2.0` and `1.2.0` compare as equals.
    static func normalise(_ version: String) -> String {
        var trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.first == "v" || trimmed.first == "V" { trimmed.removeFirst() }
        return trimmed
    }

    /// Numeric comparison per component, so 1.10.0 beats 1.9.0.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let left = normalise(candidate).split(separator: ".").map { Int($0) ?? 0 }
        let right = normalise(current).split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    // MARK: - Downloading

    func download() async {
        guard let release = pendingRelease else { return }
        state = .downloading(progress: 0)

        do {
            let (temporary, _) = try await URLSession.shared.download(from: release.downloadURL)
            // A download made here carries no quarantine flag — unlike one made by
            // a browser — which is exactly why this can install a build Apple has
            // never notarised.
            let unpacked = try unpack(zip: temporary)

            guard let app = try newestApp(in: unpacked) else {
                state = .failed(reason: "The download did not contain a ClickLocker app.")
                return
            }
            guard CodeSignature.matchesRunningApp(app) else {
                state = .failed(reason: CodeSignature.rejectionReason())
                return
            }

            downloadedApp = app
            state = .readyToInstall(version: release.version)
        } catch {
            state = .failed(reason: error.localizedDescription)
        }
    }

    private func cacheDirectory() throws -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.joelintveld.clicklocker", isDirectory: true)
            .appendingPathComponent("update", isDirectory: true)
        try? FileManager.default.removeItem(at: base)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// `ditto` is used rather than a zip library because it keeps the code
    /// signature and the extended attributes intact.
    private func unpack(zip: URL) throws -> URL {
        let destination = try cacheDirectory()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zip.path, destination.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError.message("Unpacking the download failed.")
        }
        return destination
    }

    private func newestApp(in directory: URL) throws -> URL? {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )
        return contents.first { $0.pathExtension == "app" }
    }

    // MARK: - Installing

    /// Leaves a note for the next launch, then hands the swap to a detached
    /// script and quits — a bundle cannot replace itself while it is running.
    func installAndRestart(isTrusted: Bool) {
        guard let newApp = downloadedApp else { return }
        let current = Bundle.main.bundleURL

        defaults.set(currentVersion, forKey: Marker.previousVersion)
        defaults.set(isTrusted, forKey: Marker.wasTrusted)

        do {
            try Self.launchSwapScript(replacing: current, with: newApp)
        } catch {
            state = .failed(reason: error.localizedDescription)
            defaults.removeObject(forKey: Marker.previousVersion)
            defaults.removeObject(forKey: Marker.wasTrusted)
            return
        }

        NSApp.terminate(nil)
    }

    /// Not private so the swap can be exercised against throwaway bundles: it is
    /// the one step that could otherwise leave the machine without the app.
    static func launchSwapScript(replacing current: URL, with replacement: URL) throws {
        let script = """
            #!/bin/bash
            # Written by ClickLocker to replace itself; safe to delete.
            set -u
            while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done

            APP=\(shellQuoted(current.path))
            NEW=\(shellQuoted(replacement.path))

            # Move the old bundle aside rather than deleting it, so a failed swap
            # cannot leave the machine without the app at all.
            rm -rf "$APP.old"
            mv "$APP" "$APP.old" || exit 1
            if ! ditto "$NEW" "$APP"; then
                mv "$APP.old" "$APP"
                exit 1
            fi
            rm -rf "$APP.old"
            open "$APP"
            """

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clicklocker-update-\(UUID().uuidString).sh")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [url.path]
        try process.run()
    }

    private static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - After the update

    /// What the previous run left behind, if this launch follows an update.
    struct UpdateOutcome {
        var previousVersion: String
        var lostPermission: Bool
    }

    /// Reads and clears the note the previous run left. Returns nothing when this
    /// launch does not follow an update.
    func consumeUpdateOutcome(isTrusted: Bool) -> UpdateOutcome? {
        guard let previous = defaults.string(forKey: Marker.previousVersion) else { return nil }
        let wasTrusted = defaults.bool(forKey: Marker.wasTrusted)
        defaults.removeObject(forKey: Marker.previousVersion)
        defaults.removeObject(forKey: Marker.wasTrusted)

        return UpdateOutcome(previousVersion: previous, lostPermission: wasTrusted && !isTrusted)
    }
}

enum UpdateError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}

/// Checks a downloaded bundle against the signature of the app doing the update.
enum CodeSignature {

    static func matchesRunningApp(_ candidate: URL) -> Bool {
        guard let requirement = runningAppRequirement() else { return false }

        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(candidate as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode
        else { return false }

        let status = SecStaticCodeCheckValidity(staticCode, [], requirement)
        return status == errSecSuccess
    }

    /// The designated requirement of the running app.
    private static func runningAppRequirement() -> SecRequirement? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode
        else { return nil }

        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess
        else { return nil }

        return requirement
    }

    /// An ad hoc build can never accept an update, and the reason is worth
    /// spelling out rather than reporting a bare failure.
    static func rejectionReason() -> String {
        if isAdHocSigned() {
            return """
                This copy is signed ad hoc, so its identity is the hash of this exact build and \
                no other build can ever match it. Sign ClickLocker with a certificate \
                (Scripts/create-signing-certificate.sh) to be able to update in place.
                """
        }
        return "The downloaded copy is not signed by the same key as this one, so it was not installed."
    }

    static func isAdHocSigned() -> Bool {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return false }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode
        else { return false }

        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let dictionary = information as? [String: Any]
        else { return false }

        // An ad hoc signature has no certificate chain at all.
        let certificates = dictionary[kSecCodeInfoCertificates as String] as? [Any]
        return (certificates?.isEmpty ?? true)
    }
}
