import SwiftUI

/// Centralized color tokens for Nyam.
///
/// Source of truth for the design system. Views should reference these
/// semantic names (`.nyamSage.shade3`, `.nyamSage.tint6`) rather than
/// scattering hex strings around the codebase — when the palette changes,
/// it changes here once.
///
/// Palette: sage green family, primary `#99A66F`. Designed for high
/// contrast against white and adequate-contrast usage on light tints.
extension Color {
    enum NyamSage {
        /// Primary brand color — `#99A66F`.
        static let primary = Color(hex: 0x99A66F)

        // MARK: Shades — darker than primary
        // Use for high-emphasis text on light backgrounds, dark mode accents.

        static let shade2 = Color(hex: 0x8B9960)
        static let shade3 = Color(hex: 0x7B8655)
        static let shade4 = Color(hex: 0x697349)
        static let shade5 = Color(hex: 0x5A623F)
        static let shade6 = Color(hex: 0x474D31)
        static let shade7 = Color(hex: 0x353A24)
        static let shade8 = Color(hex: 0x232618)

        // MARK: Tints — lighter than primary
        // Use for surfaces, hover states, soft backgrounds.

        static let tint2 = Color(hex: 0xA3AF7D)
        static let tint3 = Color(hex: 0xAEB88B)
        static let tint4 = Color(hex: 0xB9C29B)
        static let tint5 = Color(hex: 0xC3CBA8)
        static let tint6 = Color(hex: 0xCDD3B6)
        static let tint7 = Color(hex: 0xD6DCC5)
        /// Very light wash. Good for card backgrounds, subtle fills.
        static let tint8 = Color(hex: 0xDFE3D2)
    }
}

/// Surface tokens for the warm-cream Beli/Notion aesthetic. The app forces
/// `.preferredColorScheme(.light)` so these constants are the actual rendered
/// colors regardless of the user's system setting.
extension Color {
    enum NyamSurface {
        /// Main screen background — warm cream. Makes the sage primary pop
        /// without the harshness of pure white.
        static let background = Color(hex: 0xFAF6EE)
        /// Cards / elevated surfaces sit just above background — pure white
        /// gives subtle elevation against the cream.
        static let card = Color(hex: 0xFFFFFF)
        /// Faint sage wash for input fields, chips, and secondary surfaces.
        static let washSage = Color(hex: 0xF3F1E7)
    }
}

extension Color {
    /// Construct a sRGB Color from a 24-bit hex literal (e.g. `0x99A66F`).
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }
}
