import Foundation
import OpenTelemetryApi

#if canImport(UIKit)
import UIKit
#endif

/// Monitors CPU usage, memory footprint, and frame rate per view.
///
/// CPU and memory are sampled from `mach_task_basic_info` at view start/end.
/// Frame rate uses `CADisplayLink` to detect slow frames (>16.67ms) and
/// frozen frames (>700ms) per the Datadog/Sentry convention.
final class PerformanceMonitor {

    // MARK: - CPU / Memory Snapshot

    struct ResourceSnapshot {
        var cpuUsage: Double       // percentage (0-100+)
        var memoryBytes: UInt64    // resident memory in bytes
    }

    /// Sample current process CPU usage and memory footprint.
    static func currentSnapshot() -> ResourceSnapshot {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)

        let result = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { ptr in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), ptr, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return ResourceSnapshot(cpuUsage: 0, memoryBytes: 0)
        }

        // CPU usage from thread info (sum all threads)
        let cpuUsage = Self.threadCPUUsage()

        return ResourceSnapshot(
            cpuUsage: cpuUsage,
            memoryBytes: UInt64(info.resident_size)
        )
    }

    /// Sum CPU usage across all threads (percentage).
    private static func threadCPUUsage() -> Double {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0

        let result = task_threads(mach_task_self_, &threadList, &threadCount)
        guard result == KERN_SUCCESS, let threads = threadList else { return 0 }
        defer {
            let size = vm_size_t(MemoryLayout<thread_act_t>.stride * Int(threadCount))
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), size)
        }

        var totalUsage: Double = 0
        for i in 0..<Int(threadCount) {
            var threadInfo = thread_basic_info()
            var infoCount = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<natural_t>.size)

            let kr = withUnsafeMutablePointer(to: &threadInfo) { infoPtr in
                infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) { ptr in
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), ptr, &infoCount)
                }
            }

            if kr == KERN_SUCCESS && threadInfo.flags != TH_FLAGS_IDLE {
                totalUsage += Double(threadInfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
            }
        }

        return totalUsage
    }

    // MARK: - Frame Rate Monitor

    #if canImport(UIKit)

    /// Tracks frame durations via CADisplayLink to detect slow and frozen frames.
    final class FrameRateMonitor {
        private var displayLink: CADisplayLink?
        private var lastTimestamp: CFTimeInterval = 0
        private(set) var slowFrameCount: Int = 0      // > 16.67ms (below 60fps)
        private(set) var frozenFrameCount: Int = 0     // > 700ms
        private(set) var totalFrameCount: Int = 0

        func start() {
            slowFrameCount = 0
            frozenFrameCount = 0
            totalFrameCount = 0
            lastTimestamp = 0

            let link = CADisplayLink(target: self, selector: #selector(handleFrame(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        func stop() {
            displayLink?.invalidate()
            displayLink = nil
        }

        @objc private func handleFrame(_ link: CADisplayLink) {
            guard lastTimestamp > 0 else {
                lastTimestamp = link.timestamp
                return
            }

            let frameDuration = link.timestamp - lastTimestamp
            lastTimestamp = link.timestamp
            totalFrameCount += 1

            // Slow frame: > 16.67ms (1/60s)
            if frameDuration > 1.0 / 60.0 * 1.5 {  // 25ms threshold (1.5x target)
                slowFrameCount += 1
            }

            // Frozen frame: > 700ms (Datadog/Sentry convention)
            if frameDuration > 0.7 {
                frozenFrameCount += 1
            }
        }

        /// Average FPS over the monitoring period.
        var averageFPS: Double {
            guard totalFrameCount > 0, let link = displayLink else { return 0 }
            let duration = link.timestamp - (lastTimestamp - Double(totalFrameCount) / 60.0)
            return duration > 0 ? Double(totalFrameCount) / duration : 0
        }
    }

    #endif
}
