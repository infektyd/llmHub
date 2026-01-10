import Foundation
import OSLog

// Ensure this diagnostics helper is callable from any actor context.
nonisolated public enum ArtifactImportDiagnostics {
    private static let logger = Logger(subsystem: "com.llmhub", category: "ArtifactImport")
    private static let logPrefix = "ARTIFACT_DIAG"

    public static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "artifactImportDiagnosticsEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "artifactImportDiagnosticsEnabled") }
    }

    public static var isEnabledForThisRun: Bool {
        isEnabled || CommandLine.arguments.contains("-artifactImportDiag")
    }

    public static func log(_ message: String) {
        guard isEnabledForThisRun else { return }
        logger.info("\(logPrefix) \(message)")
    }

    public static func logError(_ message: String) {
        guard isEnabledForThisRun else { return }
        logger.error("\(logPrefix) \(message)")
    }

    public static func logURL(_ label: String, url: URL) {
        guard isEnabledForThisRun else { return }
        logger.info("\(logPrefix) \(label)=\(url.absoluteString)")
    }

    public static func logImportStart(sourceURL: URL, entrypoint: String) {
        guard isEnabledForThisRun else { return }
        log("import_start entrypoint=\(entrypoint)")
        logURL("source", url: sourceURL)
        logger.info("\(logPrefix) source_isFileURL=\(sourceURL.isFileURL)")
        if sourceURL.isFileURL {
            logger.info("\(logPrefix) source_path=\(sourceURL.path)")
        }
    }

    public static func logSecurityScoped(started: Bool, entrypoint: String) {
        guard isEnabledForThisRun else { return }
        logger.info("\(logPrefix) security_scoped started=\(started) entrypoint=\(entrypoint)")
    }

    public static func logSandboxState(sandboxURL: URL, manifestCount: Int, totalSize: Int) {
        guard isEnabledForThisRun else { return }
        logURL("sandbox", url: sandboxURL)
        logger.info("\(logPrefix) manifest_count=\(manifestCount) total_size=\(totalSize)")
    }

    public static func logCopyAttempt(sourceURL: URL, destinationURL: URL) {
        guard isEnabledForThisRun else { return }
        log("copy_attempt")
        logURL("src", url: sourceURL)
        logURL("dst", url: destinationURL)
    }

    public static func logCopyResult(success: Bool, error: Error? = nil) {
        guard isEnabledForThisRun else { return }
        if success {
            logger.info("\(logPrefix) copy_success")
        } else {
            logger.error("\(logPrefix) copy_failed error=\(error?.localizedDescription ?? "unknown")")
        }
    }

    public static func logManifestChanged(count: Int, totalSize: Int) {
        guard isEnabledForThisRun else { return }
        logger.info("\(logPrefix) manifest_changed count=\(count) total_size=\(totalSize)")
    }
}
