//
//  BuildStamp.swift
//  Layerworks
//
//  ⚠️ THE VALUES BELOW ARE REWRITTEN BY `Scripts/stamp-build.sh`. Do not hand-edit them.
//  Every build carries CURRENT_PROJECT_VERSION = git rev-list --count HEAD, and the app shows it.
//

import Foundation

enum BuildStamp {
    /// Short SHA of HEAD when this build was stamped. "+" suffix = uncommitted changes.
    static let commit = "c4768ca"

    /// Branch HEAD was on when this build was stamped.
    static let branch = "main"

    /// Local time the stamp was generated — effectively the build time.
    static let built = "2026-11-25 16:49"

    /// CFBundleVersion — set from the commit count by the post-commit hook.
    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    /// CFBundleShortVersionString — the marketing version.
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    /// One line for the app to show: "Version 1.0 (Build 3, commit abc1234)".
    static var line: String {
        "Version \(version) (Build \(buildNumber), commit \(commit))"
    }
}
