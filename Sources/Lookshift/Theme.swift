import AppKit
import SwiftUI

/// Colours from the Jive design system (blue accent), in light and dark variants.
/// Values come from jive/src/tokens.json; keep them in sync by hand.
@MainActor
enum Theme {
    static let surface = color(light: 0xf7f8fa, dark: 0x0c0d10)
    static let surfaceRaised = color(light: 0xffffff, dark: 0x15171c)
    static let ink = color(light: 0x14161a, dark: 0xeceef1)
    static let inkMuted = color(light: 0x586071, dark: 0x9ba1ad)
    static let line = color(light: 0xe1e4e9, dark: 0x252931)
    static let lineStrong = color(light: 0x7f8696, dark: 0x666d7b)
    static let brand = color(light: 0x0b63c4, dark: 0x4cb4ff)
    static let brandStrong = color(light: 0x084f9e, dark: 0x7ac7ff)
    /// Brand for always-dark overlays such as calibration.
    static let brandOnDark = NSColor(srgbRed: 0x4c / 255, green: 0xb4 / 255, blue: 1, alpha: 1)
    static let onBrand = color(light: 0xffffff, dark: 0x04182a)
    static let success = color(light: 0x0f766e, dark: 0x5eead4)
    static let warning = color(light: 0x92560a, dark: 0xfbbf24)
    static let warningBackground = color(light: 0xfdf0d0, dark: 0x2e2410)
    static let amber = color(light: 0xd98a06, dark: 0xf5b544)
    static let rose = color(light: 0xe11d48, dark: 0xf4718a)

    /// The same colours for SwiftUI views.
    static var brandColor: Color { Color(nsColor: brand) }

    private static func color(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255,
                           blue: CGFloat(hex & 0xff) / 255, alpha: 1)
        }
    }
}

extension ActionButton {
    /// The one button that does the next thing: brand fill, and Return presses it.
    func makePrimary(_ primary: Bool) {
        isPrimary = primary
        keyEquivalent = primary ? "\r" : ""
        needsDisplay = true
    }
}
