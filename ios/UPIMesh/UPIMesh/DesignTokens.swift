import SwiftUI

/// Design Tokens for UPI Offline Mesh ("Obsidian Kinetic")
///
/// Derived directly from `ios 2/obsidian_kinetic/DESIGN.md` and the Stitch UI screen prototypes.
/// Implements the AMOLED pitch black obsidian liquid-glass design system with specular highlights,
/// kinetic amber/yellow accents, refractive card elevations, and hardware-grade telemetry.
///
/// Typography Note:
/// Uses Apple system fonts configured with the exact font sizes, weights, and design traits
/// specified in `DESIGN.md` (Bricolage Grotesque fallback: `.default`, JetBrains Mono fallback: `.monospaced`).
public enum DesignTokens {

    // MARK: - Colors
    public enum Colors {
        // Void canvas & Surfaces
        public static let voidCanvas = Color(hex: "000000")
        public static let background = Color(hex: "12131A")
        public static let surface = Color(hex: "12131A")
        public static let surfaceDim = Color(hex: "12131A")
        public static let surfaceBright = Color(hex: "383941")
        public static let surfaceContainerLowest = Color(hex: "0D0E15")
        public static let surfaceContainerLow = Color(hex: "1A1B22")
        public static let surfaceContainer = Color(hex: "1E1F26")
        public static let surfaceContainerHigh = Color(hex: "292931")
        public static let surfaceContainerHighest = Color(hex: "33343C")
        public static let surfaceVariant = Color(hex: "33343C")

        // Content
        public static let onSurface = Color(hex: "E3E1EC")
        public static let onSurfaceVariant = Color(hex: "D1C6AB")
        public static let inverseSurface = Color(hex: "E3E1EC")
        public static let inverseOnSurface = Color(hex: "2F3038")

        // Primary / Kinetic Amber-Gold
        public static let primary = Color(hex: "FFECB9")
        public static let onPrimary = Color(hex: "3C2F00")
        public static let primaryContainer = Color(hex: "FACC15")
        public static let onPrimaryContainer = Color(hex: "6C5700")
        public static let surfaceTint = Color(hex: "EEC200")

        // Secondary / Warm Amber
        public static let secondary = Color(hex: "FFB95F")
        public static let onSecondary = Color(hex: "472A00")
        public static let secondaryContainer = Color(hex: "EE9800")
        public static let onSecondaryContainer = Color(hex: "5B3800")

        // Tertiary / Golden Glow
        public static let tertiary = Color(hex: "FFEBC4")
        public static let onTertiary = Color(hex: "3F2E00")
        public static let tertiaryContainer = Color(hex: "FFC93E")
        public static let onTertiaryContainer = Color(hex: "715500")

        // Mesh Accent / Dynamic Gold (Used throughout UI and companion sync)
        public static let meshGold = Color(hex: "FACC15")
        public static let meshAmber = Color(hex: "F59E0B")
        public static let onMeshGold = Color(hex: "3C2F00")

        // Error & Alerts
        public static let error = Color(hex: "FFB4AB")
        public static let onError = Color(hex: "690005")
        public static let errorContainer = Color(hex: "93000A")
        public static let onErrorContainer = Color(hex: "FFDAD6")
        public static let alertRed = Color(hex: "EF4444")

        // Outlines & Borders
        public static let outline = Color(hex: "9A9078")
        public static let outlineVariant = Color(hex: "4D4632")
        public static let glassStrokeLight = Color.white.opacity(0.12)
        public static let glassStrokeDim = Color.white.opacity(0.04)
        public static let amberGlowStroke = Color(hex: "FACC15").opacity(0.35)
    }

    // MARK: - Corner Radii
    public enum CornerRadius {
        public static let sm: CGFloat = 8
        public static let base: CGFloat = 16
        public static let md: CGFloat = 20
        public static let card: CGFloat = 24
        public static let lg: CGFloat = 32
        public static let full: CGFloat = 9999
    }

    // MARK: - Spacing
    public enum Spacing {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 24
        public static let gutter: CGFloat = 12
        public static let margin: CGFloat = 16
    }

    // MARK: - Typography (Semantic System Styles)
    public enum Typography {
        public static let displayHero = Font.system(size: 48, weight: .heavy, design: .default)
        public static let displayHeroMobile = Font.system(size: 38, weight: .heavy, design: .default)
        public static let headlineLg = Font.system(size: 32, weight: .bold, design: .default)
        public static let headlineMd = Font.system(size: 24, weight: .bold, design: .default)
        public static let headlineSm = Font.system(size: 20, weight: .semibold, design: .default)
        public static let bodyLg = Font.system(size: 17, weight: .medium, design: .default)
        public static let bodyMd = Font.system(size: 15, weight: .regular, design: .default)
        public static let bodySm = Font.system(size: 13, weight: .regular, design: .default)
        public static let telemetryLg = Font.system(size: 28, weight: .semibold, design: .monospaced)
        public static let telemetryMd = Font.system(size: 16, weight: .medium, design: .monospaced)
        public static let telemetrySm = Font.system(size: 12, weight: .medium, design: .monospaced)
        public static let labelNumeric = Font.system(size: 16, weight: .medium, design: .monospaced)
        public static let labelNumericLg = Font.system(size: 28, weight: .semibold, design: .monospaced)
        public static let labelNumericSm = Font.system(size: 12, weight: .medium, design: .monospaced)
        public static let labelCaps = Font.system(size: 11, weight: .bold, design: .monospaced)
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
