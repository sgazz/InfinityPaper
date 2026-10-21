//
//  AppLinks.swift
//  InfinityPaper
//
//  Central place for optional marketing / support URLs (Settings, etc.).
//

import Foundation

enum AppLinks {
    /// When the public site is ready, set this to a valid URL. `nil` hides the Website row in Settings.
    static let website: URL? = nil

    static let support = URL(string: "https://sgazz.github.io/infinitypaper-support/")
    static let privacyPolicy = URL(string: "https://sgazz.github.io/infinitypaper-support/privacy-policy.html")
}
