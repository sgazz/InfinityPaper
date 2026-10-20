import Foundation

/// Existing storage keys and defaults shared by the settings UI and canvas services.
enum AppSettings {
    static let pencilInputDidChange = Notification.Name("pencilInput.didChange")
    static let pencilOnly = "settings.pencil.only"
    static let pencilPressure = "settings.pencil.pressure"
    static let pencilTilt = "settings.pencil.tilt"
    static let pencilSensitivity = "settings.pencil.sensitivity"
    static let autosaveModeDidChange = Notification.Name("autosaveMode.didChange")
    static let colorIndex = "settings.baseColorIndex"
    static let lineWidth = "settings.baseLineWidth"
    static let includeReferenceImage = "settings.export.includeReferenceImage"
    static let includePaperPattern = "settings.export.includePaperPattern"
    static let exportFull = "settings.export.full"
    static let exportFormat = "settings.export.format"
    static let resolution = "settings.export.resolution"
    static let margin = "settings.export.margin"
    static let includeNoise = "settings.export.includeNoise"
    static let transparent = "settings.export.transparent"
    static let autoName = "settings.export.autoName"
    static let prefix = "settings.export.prefix"
    static let autosaveMode = "settings.session.autosaveMode"
    static let autoload = "settings.session.autoload"
    static let paperSurface = "settings.paper.surface"

    enum Default {
        static let lineWidth = 2.5
        static let exportFormat = ExportFormat.pdf
        static let resolution = 2.0
        static let margin = 0.0
        static let includeNoise = true
        static let transparent = false
        static let autoName = true
        static let prefix = "InfinityPaper_"
        static let autosaveMode = AutosaveMode.onBackground
        static let autoload = true
    }

    static let defaults: UserDefaults = {
        let defaults = UserDefaults.standard
        registerDefaults(in: defaults)
        return defaults
    }()

    /// Registration supplies missing values without overwriting saved preferences.
    static func registerDefaults(in defaults: UserDefaults) {
        defaults.register(defaults: [
            pencilOnly: false, pencilPressure: true, pencilTilt: false, pencilSensitivity: 0.5,
            lineWidth: Default.lineWidth, colorIndex: 0, exportFull: false,
            includeReferenceImage: true, includePaperPattern: true, exportFormat: Default.exportFormat.rawValue, resolution: Default.resolution,
            margin: Default.margin, includeNoise: Default.includeNoise,
            transparent: Default.transparent, autoName: Default.autoName,
            prefix: Default.prefix, autosaveMode: Default.autosaveMode.rawValue,
            autoload: Default.autoload, paperSurface: "quiet"
        ])
        for (key, range, fallback) in [(lineWidth, 1.0...8.0, Default.lineWidth),
                                       (resolution, 1.0...4.0, Default.resolution),
                                       (margin, 0.0...64.0, Default.margin), (pencilSensitivity, 0.0...1.0, 0.5)] {
            let value = defaults.double(forKey: key)
            if !value.isFinite || !range.contains(value) { defaults.set(fallback, forKey: key) }
        }
    }
}

enum ExportFormat: String, CaseIterable, Identifiable { case pdf, png; var id: String { rawValue } }
enum AutosaveMode: String, CaseIterable, Identifiable { case onBackground, periodic; var id: String { rawValue } }
