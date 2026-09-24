import Foundation

public struct PolicyCheck: ConfigurationCheck {

    public init() {}

    public func findings(in configuration: Configuration) -> [ValidationFinding] {
        var findings: [ValidationFinding] = []
        let defaultsPath = ConfigurationPath().field("defaults")

        appendWindowSizeFindings(configuration.defaults.minimumWindowSize, at: defaultsPath.field("minimumWindowSize"), to: &findings)

        if configuration.defaults.retry.attempts < 1 {
            findings.append(ValidationFinding(
                code: .retryAttemptsTooLow,
                path: defaultsPath.field("retry").field("attempts"),
                message: L.string("policy.retryAttemptsTooLow", "The number of placement attempts must be at least 1.")
            ))
        }
        appendNegativeDurationFinding(configuration.defaults.retry.initialDelay, at: defaultsPath.field("retry").field("initialDelay"), to: &findings)
        appendNegativeDurationFinding(configuration.defaults.retry.interval, at: defaultsPath.field("retry").field("interval"), to: &findings)
        appendNegativeDurationFinding(configuration.defaults.retry.tolerance, at: defaultsPath.field("retry").field("tolerance"), to: &findings)

        if let timeout = configuration.defaults.conflict.manualOverrideTimeout {
            appendNegativeDurationFinding(timeout, at: defaultsPath.field("conflict").field("manualOverrideTimeout"), to: &findings)
        }

        for rule in configuration.rules {
            let matchPath = ConfigurationPath().element("rules", rule.id).field("match")

            if let aspectRatio = rule.match.aspectRatio {
                let aspectRatioPath = matchPath.field("aspectRatio")
                if aspectRatio.minimum <= 0 {
                    findings.append(ValidationFinding(
                        code: .aspectRatioNonPositive,
                        path: aspectRatioPath.field("minimum"),
                        message: L.string("policy.aspectRatioNonPositive.minimum", "The minimum aspect ratio must be greater than 0.")
                    ))
                }
                if aspectRatio.maximum <= 0 {
                    findings.append(ValidationFinding(
                        code: .aspectRatioNonPositive,
                        path: aspectRatioPath.field("maximum"),
                        message: L.string("policy.aspectRatioNonPositive.maximum", "The maximum aspect ratio must be greater than 0.")
                    ))
                }
                if aspectRatio.minimum > aspectRatio.maximum {
                    findings.append(ValidationFinding(
                        code: .aspectRatioInverted,
                        path: aspectRatioPath,
                        message: L.string("policy.aspectRatioInverted", "The minimum aspect ratio is greater than the maximum.")
                    ))
                }
            }

            if let minimumSize = rule.match.minimumSize {
                appendWindowSizeFindings(minimumSize, at: matchPath.field("minimumSize"), to: &findings)
            }
            if let maximumSize = rule.match.maximumSize {
                appendWindowSizeFindings(maximumSize, at: matchPath.field("maximumSize"), to: &findings)
            }
        }

        return findings
    }

    private func appendNegativeDurationFinding(_ value: Double, at path: ConfigurationPath, to findings: inout [ValidationFinding]) {
        guard value < 0 else { return }
        findings.append(ValidationFinding(
            code: .negativeDuration,
            path: path,
            message: L.string("policy.negativeDuration", "A duration must not be negative.")
        ))
    }

    private func appendWindowSizeFindings(_ size: WindowSize, at path: ConfigurationPath, to findings: inout [ValidationFinding]) {
        if size.width <= 0 {
            findings.append(ValidationFinding(
                code: .nonPositiveWindowSize,
                path: path.field("width"),
                message: L.string("policy.nonPositiveWindowSize.width", "The window width must be greater than 0.")
            ))
        }
        if size.height <= 0 {
            findings.append(ValidationFinding(
                code: .nonPositiveWindowSize,
                path: path.field("height"),
                message: L.string("policy.nonPositiveWindowSize.height", "The window height must be greater than 0.")
            ))
        }
    }
}
