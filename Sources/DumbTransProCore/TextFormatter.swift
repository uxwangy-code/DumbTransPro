import Foundation

public enum TextFormatter {
    public static func toKebabCase(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }

        let lowered = trimmed.lowercased()
        // Keep only alphanumeric, spaces, and hyphens
        let cleaned = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "-" {
                return Character(scalar)
            } else {
                return " "
            }
        }
        let joined = String(cleaned)
        // Split on whitespace, filter empty, join with hyphens
        let parts = joined.split(separator: " ", omittingEmptySubsequences: true)
        return parts.joined(separator: "-")
    }
}
