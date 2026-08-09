#if DEBUG
import Foundation

/// Shared sample data for `#Preview` blocks and the README screenshot
/// generator (`ScreenshotGenTests`). DEBUG-only: never in release builds.
enum DiagnosticsKitSamples {
    /// An in-memory log (no `UserDefaults`) with a mix of levels. `@MainActor`
    /// so `ErrorLog.publish` commits synchronously — entries are present
    /// immediately, which `ImageRenderer` (no `.task`/`.onAppear`) requires.
    @MainActor static func sampleLog() -> ErrorLog {
        let log = ErrorLog(defaults: nil, app: "Preview")
        log.info("AudioSession", "Route changed to built-in speaker")
        log.warning("CoreData", "Save retried after a transient merge conflict")
        log.error("AudioSession", "Failed to activate session — cannot start playing")
        return log
    }
}
#endif
