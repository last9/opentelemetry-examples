import Foundation
import OpenTelemetryApi

/// Catches POSIX signal crashes (SIGSEGV, SIGABRT, SIGBUS, SIGFPE, SIGILL, SIGTRAP).
///
/// The existing `NSSetUncaughtExceptionHandler` only catches ObjC NSExceptions.
/// Signal handlers catch lower-level crashes: null pointer dereferences (SIGSEGV),
/// memory corruption (SIGBUS), abort() calls (SIGABRT), etc.
///
/// On signal, we capture the signal number, write a crash marker to disk
/// (since we can't safely allocate memory or call ObjC), and attempt to flush.
///
/// Mach exception ports would be more robust (they catch EXC_BAD_ACCESS before
/// it becomes SIGSEGV), but signal handlers are simpler and sufficient for
/// an example implementation.
final class SignalCrashHandler {

    /// Signals to handle — covers the common iOS crash signals.
    private static let handledSignals: [Int32] = [
        SIGSEGV,  // Segmentation fault (null pointer, bad memory access)
        SIGABRT,  // Abort (assert failures, uncaught C++ exceptions)
        SIGBUS,   // Bus error (misaligned access)
        SIGFPE,   // Floating point exception (division by zero)
        SIGILL,   // Illegal instruction
        SIGTRAP,  // Breakpoint/debugger trap
    ]

    /// Previous signal handlers — restored after our handler fires to allow
    /// crash reporters (like Apple's ReportCrash) to also process the signal.
    private static var previousHandlers: [Int32: (@convention(c) (Int32) -> Void)?] = [:]

    /// File path for crash marker — written synchronously from signal handler.
    /// Must be pre-computed since we can't allocate in a signal handler.
    private static var crashMarkerPath: UnsafeMutablePointer<CChar>?

    /// Pre-allocated buffers for each signal — written from signal handler.
    /// Maps signal number to a pre-formatted "signal:NN\n" byte sequence.
    private static var signalMarkers: [Int32: [UInt8]] = [:]

    static func install() {
        // Pre-compute the crash marker file path
        if let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let path = cacheDir.appendingPathComponent("last9_signal_crash.txt").path
            crashMarkerPath = strdup(path)
        }

        // Pre-format marker strings for each signal (can't format in signal handler)
        for sig in handledSignals {
            let str = "signal:\(sig)\n"
            signalMarkers[sig] = Array(str.utf8)
        }

        for sig in handledSignals {
            var action = sigaction()
            action.__sigaction_u.__sa_handler = signalHandler
            sigemptyset(&action.sa_mask)
            action.sa_flags = 0

            var previousAction = sigaction()
            sigaction(sig, &action, &previousAction)

            // Save previous handler for chaining
            previousHandlers[sig] = previousAction.__sigaction_u.__sa_handler
        }
    }

    /// Called on next app launch to check if a signal crash occurred.
    /// If so, emits a FATAL log event with the signal info.
    static func checkAndReportPreviousCrash() {
        guard let pathPtr = crashMarkerPath else { return }
        let path = String(cString: pathPtr)

        guard FileManager.default.fileExists(atPath: path),
              let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return
        }

        // Parse the crash marker: "signal:<number>"
        let parts = content.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":")
        guard parts.count == 2, let signalNumber = Int32(parts[1]) else {
            try? FileManager.default.removeItem(atPath: path)
            return
        }

        let signalName = Self.signalName(signalNumber)

        let logger = OpenTelemetry.instance.loggerProvider
            .loggerBuilder(instrumentationScopeName: "crash")
            .build()

        logger.logRecordBuilder()
            .setBody(.string("signal_crash"))
            .setSeverity(.fatal)
            .setAttributes([
                "event.name": .string("signal_crash"),
                "crash.signal.number": .int(Int(signalNumber)),
                "crash.signal.name": .string(signalName),
                "crash.type": .string("signal"),
            ])
            .emit()

        // Clean up
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - Signal Handler (async-signal-safe only!)

    /// Signal handler — called in a crash context. ONLY async-signal-safe functions allowed.
    /// No ObjC, no Swift allocations, no locks, no malloc.
    private static let signalHandler: @convention(c) (Int32) -> Void = { signal in
        // Write crash marker to disk (open/write/close are async-signal-safe)
        if let path = crashMarkerPath, let marker = signalMarkers[signal] {
            let fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
            if fd >= 0 {
                marker.withUnsafeBufferPointer { buf in
                    if let baseAddress = buf.baseAddress {
                        _ = write(fd, baseAddress, buf.count)
                    }
                }
                close(fd)
            }
        }

        // Mark crash for watchdog detector (so it doesn't double-report)
        Last9OTel.shared?.watchdogDetector.markCrashHandlerFired()

        // Attempt to flush (best effort — may not complete before process dies)
        Last9OTel.shared?.flush()

        // Restore previous handler and re-raise so Apple/other crash reporters run
        if let previous = previousHandlers[signal] {
            var action = sigaction()
            action.__sigaction_u.__sa_handler = previous
            sigemptyset(&action.sa_mask)
            sigaction(signal, &action, nil)
        } else {
            // Restore default handler
            var action = sigaction()
            action.__sigaction_u.__sa_handler = SIG_DFL
            sigemptyset(&action.sa_mask)
            sigaction(signal, &action, nil)
        }

        // Re-raise to let the default handler produce the crash report
        raise(signal)
    }

    // MARK: - Signal Names

    private static func signalName(_ signal: Int32) -> String {
        switch signal {
        case SIGSEGV: return "SIGSEGV"
        case SIGABRT: return "SIGABRT"
        case SIGBUS:  return "SIGBUS"
        case SIGFPE:  return "SIGFPE"
        case SIGILL:  return "SIGILL"
        case SIGTRAP: return "SIGTRAP"
        default:      return "SIGNAL(\(signal))"
        }
    }
}
