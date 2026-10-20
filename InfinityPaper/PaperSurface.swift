import UIKit

enum PaperSurface: String, CaseIterable, Identifiable, Sendable {
    case quiet
    case electric

    var id: String { rawValue }

    static let didChangeNotification = Notification.Name("paperSurface.didChange")

    static func current(defaults: UserDefaults = .standard) -> PaperSurface {
        guard let raw = defaults.string(forKey: AppSettings.paperSurface),
              let value = PaperSurface(rawValue: raw) else {
            return .quiet
        }
        return value
    }

    static func setCurrent(_ value: PaperSurface, defaults: UserDefaults = .standard) {
        let old = current(defaults: defaults)
        defaults.set(value.rawValue, forKey: AppSettings.paperSurface)
        guard old != value else { return }
        NotificationCenter.default.post(name: didChangeNotification, object: value)
    }

    static var adaptiveBackgroundColor: UIColor {
        UIColor { traits in current().backgroundColor(for: traits) }
    }

    func backgroundColor(for traits: UITraitCollection) -> UIColor {
        let isDark = traits.userInterfaceStyle == .dark
        switch (self, isDark) {
        case (.quiet, false):
            return UIColor(red: 248 / 255, green: 245 / 255, blue: 238 / 255, alpha: 1) // #F8F5EE
        case (.quiet, true):
            return UIColor(red: 35 / 255, green: 34 / 255, blue: 32 / 255, alpha: 1) // #232220
        case (.electric, false):
            return UIColor(red: 244 / 255, green: 247 / 255, blue: 250 / 255, alpha: 1) // #F4F7FA
        case (.electric, true):
            return UIColor(red: 27 / 255, green: 31 / 255, blue: 40 / 255, alpha: 1) // #1B1F28
        }
    }

    var noiseProfile: PaperNoiseProfile {
        switch self {
        case .quiet:
            return PaperNoiseProfile(dotCount: 95, alphaMin: 0.012, alphaMax: 0.032)
        case .electric:
            // Slightly quieter grain so the cooler surface stays clean under neon strokes.
            return PaperNoiseProfile(dotCount: 80, alphaMin: 0.010, alphaMax: 0.026)
        }
    }
}

struct PaperNoiseProfile: Sendable {
    let dotCount: Int
    let alphaMin: CGFloat
    let alphaMax: CGFloat
}

