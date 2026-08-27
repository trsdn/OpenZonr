import Foundation

public struct PatternCheck: ConfigurationCheck {

    public init() {}

    public func findings(in configuration: Configuration) -> [ValidationFinding] {
        var findings: [ValidationFinding] = []

        for rule in configuration.rules {
            guard let pattern = rule.match.titlePattern else { continue }
            do {
                _ = try NSRegularExpression(pattern: pattern)
            } catch {
                findings.append(ValidationFinding(
                    code: .invalidTitlePattern,
                    path: ConfigurationPath().element("rules", rule.id).field("match").field("titlePattern"),
                    message: "Der reguläre Ausdruck für den Fenstertitel ist ungültig: \(error.localizedDescription)"
                ))
            }
        }

        return findings
    }
}
