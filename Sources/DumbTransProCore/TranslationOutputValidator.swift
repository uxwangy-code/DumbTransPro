import Foundation

/// Run after engine-specific formatting, before displaying, counting, or delivering a result.
public enum TranslationOutputValidator {
    public static func validate(_ output: String) throws -> String {
        let cleaned = clean(output)
        guard cleaned.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) }) else {
            throw TranslateError.invalidOutput
        }
        return cleaned
    }

    static func clean(_ output: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines = trimmed.components(separatedBy: .newlines)
        if lines.first?.hasPrefix("```") == true {
            lines.removeFirst()
            if lines.last?.trimmingCharacters(in: .whitespaces) == "```" { lines.removeLast() }
            return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }
}
