import Foundation

/// Formatter for displaying Indian Rupee (INR) amounts in proper Indian numbering format.
///
/// Handles both complete currency representations (e.g. "₹5,000.00", "₹1,00,000.00")
/// and split parts (whole vs fractional) for dual-typography display designs.
public enum CurrencyFormatter {

    private static let indianNumberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_IN")
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = "."
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter
    }()

    /// Formats a monetary amount into standard Indian Rupee format, e.g. "₹5,000.00".
    public static func format(amount: Double) -> String {
        let number = NSNumber(value: amount)
        let formatted = indianNumberFormatter.string(from: number) ?? String(format: "%.2f", amount)
        return "₹\(formatted)"
    }

    /// Splits an amount into currency whole part ("₹5,000") and 2-decimal fractional part (".00")
    /// preserving Stitch UI dual-typography layout.
    public static func formatParts(amount: Double) -> (whole: String, fraction: String) {
        let full = format(amount: amount)
        if let dotIndex = full.lastIndex(of: ".") {
            let whole = String(full[..<dotIndex])
            let fraction = String(full[dotIndex...])
            return (whole, fraction)
        }
        return (full, ".00")
    }
}
