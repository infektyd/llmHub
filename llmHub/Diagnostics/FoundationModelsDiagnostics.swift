import Foundation
import FoundationModels
import OSLog

@MainActor
public enum FoundationModelsDiagnostics {
    private static let logger = Logger(subsystem: "com.llmhub", category: "AFM")

    /// Logs prefix for all diagnostics
    private static let logPrefix = "AFM_DIAG"

    /// Persisted toggle for verbose diagnostics
    public static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "foundationModelsDiagnosticsEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "foundationModelsDiagnosticsEnabled") }
    }

    /// Probes the system for FoundationModels availability and logs detailed info.
    public static func probe() {
        guard isEnabled || CommandLine.arguments.contains("-v") else { return }

        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let locale = Locale.current.identifier
        let languages = Locale.preferredLanguages.joined(separator: ", ")

        logger.info("\(logPrefix) --- PROBE START ---")
        logger.info("\(logPrefix) OS: \(osVersion)")
        logger.info("\(logPrefix) Locale: \(locale)")
        logger.info("\(logPrefix) Preferred Languages: \(languages)")

        if #available(macOS 15.0, iOS 18.0, *) {
            let availability = SystemLanguageModel.default.availability

            switch availability {
            case .available:
                logger.info("\(logPrefix) availability=available")
            case .unavailable(let reason):
                let reasonName = String(describing: reason)
                logger.error(
                    "\(logPrefix) availability=unavailable reason=\(reasonName) desc=\(String(describing: reason))"
                )
            @unknown default:
                logger.warning("\(logPrefix) availability=unknown")
            }
        } else {
            logger.error("\(logPrefix) availability=unsupported_os")
        }

        logger.info("\(logPrefix) --- PROBE END ---")
    }

    /// Logs a start of an AFM request
    public static func logRequestStart(useCase: String) {
        guard isEnabled else { return }
        logger.info("\(logPrefix) request_start useCase=\(useCase)")
    }

    /// Logs a successful AFM request with latency
    public static func logRequestSuccess(latencyMs: Double) {
        guard isEnabled else { return }
        logger.info("\(logPrefix) request_success latency_ms=\(latencyMs)")
    }

    /// Logs a failed AFM request with latency and error details
    public static func logRequestFail(latencyMs: Double, error: Error) {
        guard isEnabled else { return }
        logger.error("\(logPrefix) request_fail latency_ms=\(latencyMs)")
        wrapError(error)
    }

    /// Logs streaming events
    public static func logStreamEvent(_ event: String, reason: String? = nil) {
        guard isEnabled else { return }
        if let reason = reason {
            logger.info("\(logPrefix) stream_\(event) reason=\(reason)")
        } else {
            logger.info("\(logPrefix) stream_\(event)")
        }
    }

    /// Wraps and logs an error with detailed OSLog/unified log signals
    public static func wrapError(_ error: Error) {
        guard isEnabled else { return }

        let nsError = error as NSError
        let domain = nsError.domain
        let code = nsError.code
        let description = error.localizedDescription
        let userInfoKeys = nsError.userInfo.keys.map { String(describing: $0) }.joined(
            separator: ", ")

        logger.error(
            "\(logPrefix) error domain=\(domain) code=\(code) desc=\(description) userInfoKeys=[\(userInfoKeys)]"
        )
    }
}
