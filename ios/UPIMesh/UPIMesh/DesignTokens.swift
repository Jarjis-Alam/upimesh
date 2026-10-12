import SwiftUI

/// Design Tokens for UPI Offline Mesh ("Liquid Mesh UPI")
///
/// Derived directly from `ios_ui/liquid_mesh_upi/DESIGN.md` and the Stitch UI screen prototypes.
/// Implements the dark obsidian liquid-glass design system with specular highlights,
/// refractive card elevations, and chromatic state indicators.
///
/// Typography Note:
/// Uses Apple system fonts configured with the exact font sizes, weights, and design traits
/// specified in `DESIGN.md` (Standard Manrope fallback: `.default`, JetBrains Mono fallback: `.monospaced`).
public enum DesignTokens {

    // MARK: - Colors
    public enum Colors {
        // Void canvas & Surfaces
        public static let voidCanvas = Color(hex: "080A0D")
        public static let background = Color(hex: "111317")
        public static let surface = Color(hex: "111317")
        public static let surfaceDim = Color(hex: "111317")
        public static let surfaceBright = Color(hex: "37393D")
        public static let surfaceContainerLowest = Color(hex: "0C0E11")
        public static let surfaceContainerLow = Color(hex: "1A1C1F")
        public static let surfaceContainer = Color(hex: "1E2023")
        public static let surfaceContainerHigh = Color(hex: "282A2D")
        public static let surfaceContainerHighest = Color(hex: "333538")
        public static let surfaceVariant = Color(hex: "333538")

        // Content
        public static let onSurface = Color(hex: "E2E2E6")
        public static let onSurfaceVariant = Color(hex: "BCCABB")
        public static let inverseSurface = Color(hex: "E2E2E6")
        public static let inverseOnSurface = Color(hex: "2F3034")

        // Primary / Mint Vitality
        public static let primary = Color(hex: "6BFB9A")
        public static let onPrimary = Color(hex: "003919")
        public static let primaryContainer = Color(hex: "4ADE80")
        public static let onPrimaryContainer = Color(hex: "005E2D")
        public static let surfaceTint = Color(hex: "4DE082")

        // Secondary / Electric Azure
        public static let secondary = Color(hex: "7BD0FF")
        public static let onSecondary = Color(hex: "00354A")
        public static let secondaryContainer = Color(hex: "00A6E0")
        public static let onSecondaryContainer = Color(hex: "00374D")

        // Tertiary / Patina Emerald
        public static let tertiary = Color(hex: "A9EEDB")
        public static let onTertiary = Color(hex: "00382E")
        public static let tertiaryContainer = Color(hex: "8DD1BF")
        public static let onTertiaryContainer = Color(hex: "0F5B4D")

        // Mesh Accent / Dynamic Gold (Used throughout Stitch exports)
        public static let meshGold = Color(hex: "FACC15")
        public static let meshAmber = Color(hex: "FBBF24")
        public static let onMeshGold = Color(hex: "111317")

        // Error & Alerts
        public static let error = Color(hex: "FFB4AB")
        public static let onError = Color(hex: "690005")
        public static let errorContainer = Color(hex: "93000A")
        public static let onErrorContainer = Color(hex: "FFDAD6")
        public static let alertRed = Color(hex: "FB7185")

        // Outlines & Borders
        public static let outline = Color(hex: "869486")
        public static let outlineVariant = Color(hex: "3D4A3E")
        public static let glassStrokeLight = Color.white.opacity(0.18)
        public static let glassStrokeDim = Color.white.opacity(0.04)
    }

    // MARK: - Corner Radii
    public enum CornerRadius {
        public static let sm: CGFloat = 8
        public static let base: CGFloat = 16
        public static let md: CGFloat = 20
        public static let card: CGFloat = 26
        public static let lg: CGFloat = 32
        public static let full: CGFloat = 9999
    }

    // MARK: - Spacing
    public enum Spacing {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 16
        public static let lg: CGFloat = 24
        public static let xl: CGFloat = 32
        public static let gutter: CGFloat = 16
        public static let margin: CGFloat = 20
    }

    // MARK: - Typography (Semantic System Styles)
    public enum Typography {
        public static let displayHero = Font.system(size: 40, weight: .bold, design: .default)
        public static let displayHeroMobile = Font.system(size: 32, weight: .bold, design: .default)
        public static let headlineLg = Font.system(size: 28, weight: .semibold, design: .default)
        public static let headlineMd = Font.system(size: 22, weight: .semibold, design: .default)
        public static let headlineSm = Font.system(size: 18, weight: .semibold, design: .default)
        public static let bodyLg = Font.system(size: 17, weight: .regular, design: .default)
        public static let bodyMd = Font.system(size: 15, weight: .regular, design: .default)
        public static let bodySm = Font.system(size: 13, weight: .regular, design: .default)
        public static let labelNumeric = Font.system(size: 15, weight: .medium, design: .monospaced)
        public static let labelNumericLg = Font.system(size: 20, weight: .semibold, design: .monospaced)
        public static let labelNumericSm = Font.system(size: 11, weight: .medium, design: .monospaced)
        public static let labelCaps = Font.system(size: 11, weight: .bold, design: .default)
        public static let caption = Font.system(size: 12, weight: .regular, design: .default)
    }
}

// MARK: - Color Hex Initializer
public extension Color {
    init(hex: String) {
        let cleanHex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleanHex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch cleanHex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Liquid Glass View Modifiers

public struct LiquidCardModifier: ViewModifier {
    public var cornerRadius: CGFloat = DesignTokens.CornerRadius.card
    public var strokeColor: Color = DesignTokens.Colors.glassStrokeLight
    public var backgroundColor: Color = DesignTokens.Colors.surfaceContainer.opacity(0.70)

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(backgroundColor)
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [strokeColor, DesignTokens.Colors.glassStrokeDim],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.4), radius: 12, x: 0, y: 8)
    }
}

public struct LiquidGlowModifier: ViewModifier {
    public var color: Color
    public var radius: CGFloat = 16

    public func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.35), radius: radius, x: 0, y: 4)
    }
}

public extension View {
    func liquidCard(
        cornerRadius: CGFloat = DesignTokens.CornerRadius.card,
        strokeColor: Color = DesignTokens.Colors.glassStrokeLight,
        backgroundColor: Color = DesignTokens.Colors.surfaceContainer.opacity(0.70)
    ) -> some View {
        self.modifier(LiquidCardModifier(cornerRadius: cornerRadius, strokeColor: strokeColor, backgroundColor: backgroundColor))
    }

    func liquidGlow(color: Color, radius: CGFloat = 16) -> some View {
        self.modifier(LiquidGlowModifier(color: color, radius: radius))
    }
}

// MARK: - Background Spatial Canvas View

public struct SpatialCanvasBackground: View {
    public init() {}

    public var body: some View {
        ZStack {
            DesignTokens.Colors.voidCanvas
                .ignoresSafeArea()

            // Subtle refractive ambient light wells
            Circle()
                .fill(DesignTokens.Colors.secondary.opacity(0.08))
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .offset(x: -120, y: -260)

            Circle()
                .fill(DesignTokens.Colors.meshGold.opacity(0.08))
                .frame(width: 340, height: 340)
                .blur(radius: 100)
                .offset(x: 140, y: -80)

            Circle()
                .fill(DesignTokens.Colors.primary.opacity(0.06))
                .frame(width: 300, height: 300)
                .blur(radius: 90)
                .offset(x: -40, y: 280)
        }
    }
}
