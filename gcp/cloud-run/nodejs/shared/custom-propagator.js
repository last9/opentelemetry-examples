/**
 * Custom Trace Context Propagator for GCP Cloud Run
 *
 * Problem: Cloud Run's load balancer creates intermediate spans and modifies
 * the W3C traceparent header, breaking parent-child relationships.
 *
 * Solution: Propagate the original trace context via a backup header
 * that GCP infrastructure won't modify.
 *
 * Based on industry workaround for Cloud Run distributed tracing.
 * Reference: https://medium.com/@vladislavmarkevich/distributed-tracing-cloudrun-6a3bac9d165a
 */
'use strict';

const {
  trace,
  context,
  propagation,
  ROOT_CONTEXT,
} = require('@opentelemetry/api');
const {
  W3CTraceContextPropagator,
  isTracingSuppressed,
} = require('@opentelemetry/core');

const ORIGINAL_TRACEPARENT_HEADER = 'x-original-traceparent';
const ORIGINAL_TRACESTATE_HEADER = 'x-original-tracestate';

/**
 * Custom propagator that preserves original trace context
 * even when GCP infrastructure modifies the standard headers
 */
class CloudRunTracePropagator {
  constructor() {
    this._w3cPropagator = new W3CTraceContextPropagator();
  }

  /**
   * Inject trace context into outgoing HTTP headers
   * Writes BOTH standard W3C headers AND backup headers
   */
  inject(context, carrier, setter) {
    // First, inject using standard W3C propagation
    this._w3cPropagator.inject(context, carrier, setter);

    // Then, copy to backup headers for GCP Cloud Run
    // GCP will modify traceparent, but won't touch our custom headers
    const traceparent = carrier['traceparent'];
    const tracestate = carrier['tracestate'];

    if (traceparent) {
      setter.set(carrier, ORIGINAL_TRACEPARENT_HEADER, traceparent);
      console.log(`[CloudRunPropagator] Injected backup header: ${ORIGINAL_TRACEPARENT_HEADER}=${traceparent}`);
    }

    if (tracestate) {
      setter.set(carrier, ORIGINAL_TRACESTATE_HEADER, tracestate);
    }
  }

  /**
   * Extract trace context from incoming HTTP headers
   * Prefers backup headers over standard headers to bypass GCP modifications
   */
  extract(context, carrier, getter) {
    // Check for our backup headers first (original parent context)
    const originalTraceparent = getter.get(carrier, ORIGINAL_TRACEPARENT_HEADER);
    const originalTracestate = getter.get(carrier, ORIGINAL_TRACESTATE_HEADER);

    if (originalTraceparent) {
      console.log(`[CloudRunPropagator] Found backup header, using original context: ${originalTraceparent}`);

      // Create a temporary carrier with original values
      const originalCarrier = {
        'traceparent': Array.isArray(originalTraceparent)
          ? originalTraceparent[0]
          : originalTraceparent,
      };

      if (originalTracestate) {
        originalCarrier['tracestate'] = Array.isArray(originalTracestate)
          ? originalTracestate[0]
          : originalTracestate;
      }

      // Extract using the original (pre-GCP-modification) headers
      return this._w3cPropagator.extract(context, originalCarrier, {
        get: (c, key) => c[key],
        keys: (c) => Object.keys(c),
      });
    }

    // Fallback to standard W3C extraction
    // This will use the GCP-modified headers (not ideal, but better than nothing)
    console.log('[CloudRunPropagator] No backup header found, using standard traceparent (may be GCP-modified)');
    return this._w3cPropagator.extract(context, carrier, getter);
  }

  fields() {
    // Return all headers this propagator uses
    return [
      'traceparent',
      'tracestate',
      ORIGINAL_TRACEPARENT_HEADER,
      ORIGINAL_TRACESTATE_HEADER,
    ];
  }
}

module.exports = { CloudRunTracePropagator };
