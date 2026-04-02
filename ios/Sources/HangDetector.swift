import Foundation
import OpenTelemetryApi

/// Detects main thread hangs (ANR) by pinging from a background thread.
///
/// A dedicated background thread dispatches a lightweight block to `DispatchQueue.main`
/// every `checkInterval` seconds. If the main thread doesn't execute the block within
/// `hangThreshold`, the main thread's call stack is captured and a `hang` log event
/// is emitted with WARN severity. When the main thread recovers, the total hang
/// duration is recorded.
///
/// This is the same pattern used by Datadog iOS RUM and Sentry — iOS has no system-level
/// ANR dialog like Android, but watchdog kills and user-perceived freezes are the equivalent.
final class HangDetector {
    /// Minimum main thread block time to classify as a hang (default: 2s, Datadog/Sentry standard).
    static let defaultHangThreshold: TimeInterval = 2.0

    /// How often the background thread checks the main thread (default: 1s).
    static let defaultCheckInterval: TimeInterval = 1.0

    private let hangThreshold: TimeInterval
    private let checkInterval: TimeInterval
    private let logger: Logger
    private var monitorThread: Thread?
    private var isRunning = false

    init(
        hangThreshold: TimeInterval = defaultHangThreshold,
        checkInterval: TimeInterval = defaultCheckInterval
    ) {
        self.hangThreshold = hangThreshold
        self.checkInterval = checkInterval
        self.logger = OpenTelemetry.instance.loggerProvider
            .loggerBuilder(instrumentationScopeName: "hang")
            .build()
    }

    // MARK: - Public

    func start() {
        guard !isRunning else { return }
        isRunning = true

        let thread = Thread { [weak self] in
            self?.monitorLoop()
        }
        thread.name = "com.last9.hang-detector"
        thread.qualityOfService = .utility
        monitorThread = thread
        thread.start()
    }

    func stop() {
        isRunning = false
        monitorThread?.cancel()
        monitorThread = nil
    }

    // MARK: - Monitor Loop

    private func monitorLoop() {
        while isRunning && !Thread.current.isCancelled {
            // Set flag to false, then ask main thread to flip it
            var responded = false
            let semaphore = DispatchSemaphore(value: 0)

            DispatchQueue.main.async {
                responded = true
                semaphore.signal()
            }

            // Wait for main thread to respond within the threshold
            let result = semaphore.wait(timeout: .now() + hangThreshold)

            if result == .timedOut && !responded {
                // Main thread is blocked — capture stack trace and emit hang start
                let stackTrace = Thread.callStackSymbols.joined(separator: "\n")
                let mainThreadStack = captureMainThreadStack()
                let hangStartTime = Date()

                emitHangStart(mainThreadStack: mainThreadStack, backgroundStack: stackTrace)

                // Wait for the main thread to recover (poll every 100ms)
                while isRunning && !Thread.current.isCancelled {
                    var recovered = false
                    let recoverSemaphore = DispatchSemaphore(value: 0)

                    DispatchQueue.main.async {
                        recovered = true
                        recoverSemaphore.signal()
                    }

                    let recoverResult = recoverSemaphore.wait(timeout: .now() + 0.5)
                    if recoverResult == .success && recovered {
                        let hangDuration = Date().timeIntervalSince(hangStartTime)
                        emitHangEnd(durationMs: Int(hangDuration * 1000))
                        break
                    }
                }
            }

            // Sleep before next check
            Thread.sleep(forTimeInterval: checkInterval)
        }
    }

    // MARK: - Stack Trace Capture

    /// Captures the main thread's stack trace using Mach thread APIs.
    /// Falls back to a descriptive message if Mach APIs aren't available.
    private func captureMainThreadStack() -> String {
        // Use task_threads to find the main thread and read its state.
        // The main thread is always thread index 0 in the task's thread list.
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0

        let result = task_threads(mach_task_self_, &threadList, &threadCount)
        guard result == KERN_SUCCESS, let threads = threadList, threadCount > 0 else {
            return "(unable to capture main thread stack)"
        }
        defer {
            let size = vm_size_t(MemoryLayout<thread_act_t>.stride * Int(threadCount))
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), size)
        }

        // Thread 0 is the main thread
        let mainThread = threads[0]

        #if arch(arm64)
        var state = arm_thread_state64_t()
        var stateCount = mach_msg_type_number_t(MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<natural_t>.size)
        let flavor = ARM_THREAD_STATE64

        let kr = withUnsafeMutablePointer(to: &state) { statePtr in
            statePtr.withMemoryRebound(to: natural_t.self, capacity: Int(stateCount)) { ptr in
                thread_get_state(mainThread, thread_state_flavor_t(flavor), ptr, &stateCount)
            }
        }

        guard kr == KERN_SUCCESS else {
            return "(unable to read main thread state)"
        }

        // Walk the frame pointer chain to collect return addresses
        var frames: [String] = []
        var fp = UInt(state.__fp)
        var pc = UInt(state.__pc)

        frames.append(String(format: "pc: 0x%016llx", pc))

        for _ in 0..<128 {
            guard fp != 0, fp % UInt(MemoryLayout<UInt>.alignment) == 0 else { break }
            let framePtr = UnsafePointer<UInt>(bitPattern: fp)
            guard let framePtr = framePtr else { break }
            let nextFp = framePtr.pointee
            let returnAddr = framePtr.advanced(by: 1).pointee
            if returnAddr == 0 { break }
            frames.append(String(format: "0x%016llx", returnAddr))
            fp = nextFp
        }

        return frames.joined(separator: "\n")

        #elseif arch(x86_64)
        var state = x86_thread_state64_t()
        var stateCount = mach_msg_type_number_t(MemoryLayout<x86_thread_state64_t>.size / MemoryLayout<natural_t>.size)
        let flavor = x86_THREAD_STATE64

        let kr = withUnsafeMutablePointer(to: &state) { statePtr in
            statePtr.withMemoryRebound(to: natural_t.self, capacity: Int(stateCount)) { ptr in
                thread_get_state(mainThread, thread_state_flavor_t(flavor), ptr, &stateCount)
            }
        }

        guard kr == KERN_SUCCESS else {
            return "(unable to read main thread state)"
        }

        var frames: [String] = []
        var fp = UInt(state.__rbp)
        let pc = UInt(state.__rip)

        frames.append(String(format: "pc: 0x%016llx", pc))

        for _ in 0..<128 {
            guard fp != 0, fp % UInt(MemoryLayout<UInt>.alignment) == 0 else { break }
            let framePtr = UnsafePointer<UInt>(bitPattern: fp)
            guard let framePtr = framePtr else { break }
            let nextFp = framePtr.pointee
            let returnAddr = framePtr.advanced(by: 1).pointee
            if returnAddr == 0 { break }
            frames.append(String(format: "0x%016llx", returnAddr))
            fp = nextFp
        }

        return frames.joined(separator: "\n")

        #else
        return "(unsupported architecture for stack capture)"
        #endif
    }

    // MARK: - Log Events

    private func emitHangStart(mainThreadStack: String, backgroundStack: String) {
        logger.logRecordBuilder()
            .setBody(.string("hang"))
            .setSeverity(.warn)
            .setAttributes([
                "event.name": .string("hang"),
                "hang.state": .string("start"),
                "hang.threshold_ms": .int(Int(hangThreshold * 1000)),
                "hang.main_thread.stacktrace": .string(mainThreadStack),
            ])
            .emit()
    }

    private func emitHangEnd(durationMs: Int) {
        logger.logRecordBuilder()
            .setBody(.string("hang"))
            .setSeverity(.warn)
            .setAttributes([
                "event.name": .string("hang"),
                "hang.state": .string("end"),
                "hang.duration_ms": .int(durationMs),
            ])
            .emit()
    }
}
