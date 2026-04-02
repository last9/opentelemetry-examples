import Foundation
import OpenTelemetryApi

/// Captures detailed network timing breakdown from `URLSessionTaskMetrics`.
///
/// Attributes emitted on network spans:
/// - `network.timing.dns_ms`: DNS lookup duration
/// - `network.timing.connect_ms`: TCP connection time
/// - `network.timing.tls_ms`: TLS handshake time
/// - `network.timing.ttfb_ms`: Time to first byte (request start → response start)
/// - `network.timing.transfer_ms`: Response transfer time
/// - `network.timing.total_ms`: Total request duration
/// - `network.protocol`: h2, h3, etc.
/// - `network.connection.reused`: whether the connection was reused
///
/// This supplements the existing URLSession auto-instrumentation with timing details
/// that the basic OTel URLSession instrumentation doesn't capture.
final class NetworkTimingTracker: NSObject {

    private let logger: Logger

    override init() {
        self.logger = OpenTelemetry.instance.loggerProvider
            .loggerBuilder(instrumentationScopeName: "network_timing")
            .build()
        super.init()
    }

    /// Call from a URLSessionTaskDelegate to record timing metrics.
    /// Typically wired via `urlSession(_:task:didFinishCollecting:)`.
    func recordMetrics(_ metrics: URLSessionTaskMetrics, for url: URL?) {
        guard let transaction = metrics.transactionMetrics.last else { return }

        var attrs: [String: AttributeValue] = [
            "event.name": .string("network.timing"),
        ]

        if let url = url {
            attrs["network.url"] = .string(url.absoluteString)
            if let host = url.host {
                attrs["network.host"] = .string(host)
            }
        }

        // DNS
        if let dnsStart = transaction.domainLookupStartDate,
           let dnsEnd = transaction.domainLookupEndDate {
            attrs["network.timing.dns_ms"] = .int(Int(dnsEnd.timeIntervalSince(dnsStart) * 1000))
        }

        // TCP connect
        if let connectStart = transaction.connectStartDate,
           let connectEnd = transaction.connectEndDate {
            attrs["network.timing.connect_ms"] = .int(Int(connectEnd.timeIntervalSince(connectStart) * 1000))
        }

        // TLS
        if let tlsStart = transaction.secureConnectionStartDate,
           let tlsEnd = transaction.secureConnectionEndDate {
            attrs["network.timing.tls_ms"] = .int(Int(tlsEnd.timeIntervalSince(tlsStart) * 1000))
        }

        // Time to first byte (request start → response start)
        if let requestStart = transaction.requestStartDate,
           let responseStart = transaction.responseStartDate {
            attrs["network.timing.ttfb_ms"] = .int(Int(responseStart.timeIntervalSince(requestStart) * 1000))
        }

        // Transfer time (response start → response end)
        if let responseStart = transaction.responseStartDate,
           let responseEnd = transaction.responseEndDate {
            attrs["network.timing.transfer_ms"] = .int(Int(responseEnd.timeIntervalSince(responseStart) * 1000))
        }

        // Total duration
        if let fetchStart = transaction.fetchStartDate,
           let responseEnd = transaction.responseEndDate {
            attrs["network.timing.total_ms"] = .int(Int(responseEnd.timeIntervalSince(fetchStart) * 1000))
        }

        // Protocol
        if let proto = transaction.networkProtocolName {
            attrs["network.protocol"] = .string(proto)
        }

        // Connection reuse
        attrs["network.connection.reused"] = .bool(transaction.isReusedConnection)

        logger.logRecordBuilder()
            .setBody(.string("network.timing"))
            .setSeverity(.info)
            .setAttributes(attrs)
            .emit()
    }
}
