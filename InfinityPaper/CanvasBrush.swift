import UIKit

/// Shared palette and persisted brush selection for every brush control.
enum CanvasBrush {
    // Preserve the previously earned palette without retaining the old menu.
    static var palette: [UIColor] {
        UserDefaults.standard.integer(forKey: "radialMenu.bounce.count") >= 1000
            ? primaryColorPalette + achievementColorPalette
            : primaryColorPalette
    }

    static func color(at index: Int, traits: UITraitCollection) -> UIColor {
        let colors = palette
        let safeIndex = min(max(0, index), colors.count - 1)
        if traits.userInterfaceStyle == .dark,
           safeIndex == 0 || safeIndex == primaryColorPalette.count {
            return .white
        }
        return colors[safeIndex]
    }
    static func colorName(at index: Int) -> String {
        let names = ["Ink", "Graphite", "Electric violet", "Royal purple", "Orchid", "Magenta", "Pink",
                     "Coral", "Orange", "Amber", "Lime", "Spring green", "Teal", "Cyan", "Blue", "Sky blue", "Aqua",
                     "Pastel blue", "Pastel pink", "Pastel peach", "Pastel mint", "Pastel lavender", "Pastel ice"]
        return names.indices.contains(index) ? names[index] : "Brush color"
    }

    static let primaryColorPalette: [UIColor] = [
        // Strong neutrals (balance + fine lines on light paper)
        UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 0.96), // #1A1A1F deep ink
        UIColor(red: 0.24, green: 0.27, blue: 0.34, alpha: 0.95), // #3D4557 cool graphite
        // Purple / violet (brand spine)
        UIColor(red: 0.58, green: 0.20, blue: 1.00, alpha: 0.96), // #9433FF electric violet
        UIColor(red: 0.43, green: 0.16, blue: 0.85, alpha: 0.96), // #6E29D9 royal purple
        UIColor(red: 0.72, green: 0.28, blue: 0.98, alpha: 0.95), // #B847FA vivid orchid
        // Magenta / pink
        UIColor(red: 1.00, green: 0.14, blue: 0.62, alpha: 0.96), // #FF249E neon magenta
        UIColor(red: 1.00, green: 0.35, blue: 0.78, alpha: 0.95), // #FF59C7 vivid pink
        // Warm accents
        UIColor(red: 1.00, green: 0.32, blue: 0.38, alpha: 0.96), // #FF5261 hot coral
        UIColor(red: 1.00, green: 0.48, blue: 0.08, alpha: 0.96), // #FF7A14 bright orange
        UIColor(red: 1.00, green: 0.76, blue: 0.12, alpha: 0.95), // #FFC21F electric amber
        // Greens
        UIColor(red: 0.55, green: 1.00, blue: 0.22, alpha: 0.95), // #8CFF38 acid lime
        UIColor(red: 0.12, green: 0.94, blue: 0.48, alpha: 0.96), // #1EF07A neon spring
        // Cyans / teals / blues
        UIColor(red: 0.02, green: 0.86, blue: 0.78, alpha: 0.96), // #05DBC7 neon teal
        UIColor(red: 0.05, green: 0.92, blue: 1.00, alpha: 0.96), // #0DEBFF bright cyan
        UIColor(red: 0.14, green: 0.55, blue: 1.00, alpha: 0.96), // #248CFF laser blue
        UIColor(red: 0.32, green: 0.62, blue: 1.00, alpha: 0.95), // #519EFF sky laser
        // Extra depth without mud
        UIColor(red: 0.18, green: 0.95, blue: 1.00, alpha: 0.94) // #2EF2FF aqua pop
    ]
    static let achievementColorPalette: [UIColor] = [
        UIColor(red: 0.65, green: 0.77, blue: 0.95, alpha: 0.95),  // pastel blue
        UIColor(red: 0.96, green: 0.73, blue: 0.82, alpha: 0.95),  // pastel pink
        UIColor(red: 0.96, green: 0.85, blue: 0.66, alpha: 0.95),  // pastel peach
        UIColor(red: 0.73, green: 0.9, blue: 0.77, alpha: 0.95),   // pastel mint
        UIColor(red: 0.84, green: 0.78, blue: 0.93, alpha: 0.95),  // pastel lavender
        UIColor(red: 0.88, green: 0.92, blue: 0.98, alpha: 0.95)   // pastel ice
    ]
}
