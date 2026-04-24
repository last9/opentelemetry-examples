/**
 * OpenTelemetry instrumentation helpers for Stripe.js operations.
 *
 * Wraps the three key Stripe lifecycle moments:
 *   1. loadStripe()        → stripe.js.load span
 *   2. PaymentElement ready → stripe.elements.mount span
 *   3. confirmPayment()    → stripe.payment.confirm span + structured logs
 *
 * 3DS: when confirmPayment redirects the user to their bank, we lose the JS
 * context. Call checkReturnFrom3DS() on component mount to detect the return
 * and emit a span + log for the completed challenge.
 */

import { context, SpanStatusCode, trace } from '@opentelemetry/api';
import { SeverityNumber } from '@opentelemetry/api-logs';
import { loadStripe, Stripe, StripeElements } from '@stripe/stripe-js';
import { getLogger, getTracer } from './telemetry';

// ── loadStripe ────────────────────────────────────────────────────────────────

/**
 * Wraps loadStripe() in a span so you can see Stripe.js script load time
 * alongside your other frontend traces.
 */
export const loadStripeWithTracing = async (
  publishableKey: string
): Promise<Stripe | null> => {
  const tracer = getTracer();
  const logger = getLogger();
  const span = tracer.startSpan('stripe.js.load');

  logger.emit({
    severityNumber: SeverityNumber.INFO,
    body: 'Loading Stripe.js SDK',
    attributes: { 'event.name': 'stripe.sdk.load_started' },
  });

  return context.with(trace.setSpan(context.active(), span), async () => {
    try {
      const stripe = await loadStripe(publishableKey);
      span.setAttribute('stripe.sdk.loaded', true);
      span.setStatus({ code: SpanStatusCode.OK });

      logger.emit({
        severityNumber: SeverityNumber.INFO,
        body: 'Stripe.js SDK loaded',
        attributes: { 'event.name': 'stripe.sdk.load_succeeded' },
      });

      return stripe;
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      span.recordException(err as Error);
      span.setStatus({ code: SpanStatusCode.ERROR, message });

      logger.emit({
        severityNumber: SeverityNumber.ERROR,
        body: `Stripe.js failed to load: ${message}`,
        attributes: { 'event.name': 'stripe.sdk.load_failed', 'error.message': message },
      });

      throw err;
    } finally {
      span.end();
    }
  });
};

// ── Elements mount ────────────────────────────────────────────────────────────

/**
 * Call this inside PaymentElement's onReady callback.
 * Records how long it took from component render to the element being ready
 * for input — a key UX performance metric.
 */
export const recordElementsMount = (mountStartMs: number): void => {
  const mountDurationMs = Date.now() - mountStartMs;
  const tracer = getTracer();
  const logger = getLogger();

  const span = tracer.startSpan('stripe.elements.mount');
  span.setAttribute('stripe.elements.mount_duration_ms', mountDurationMs);
  span.setStatus({ code: SpanStatusCode.OK });
  span.end();

  logger.emit({
    severityNumber: SeverityNumber.INFO,
    body: 'Stripe PaymentElement ready',
    attributes: {
      'event.name': 'stripe.elements.ready',
      'stripe.elements.mount_duration_ms': mountDurationMs,
    },
  });
};

// ── confirmPayment ────────────────────────────────────────────────────────────

interface PaymentOptions {
  amount: number;
  currency: string;
  returnUrl: string;
}

/**
 * Wraps stripe.confirmPayment() with a span and structured log events.
 *
 * Uses redirect:'if_required' so that payments that don't need 3DS complete
 * without a page redirect. When 3DS IS required, Stripe redirects to the
 * bank page and the user returns to returnUrl — call checkReturnFrom3DS()
 * on that page to close the observability loop.
 */
export const traceStripePayment = async (
  stripe: Stripe,
  elements: StripeElements,
  options: PaymentOptions
): Promise<{ error?: { message?: string; code?: string; type?: string; decline_code?: string } }> => {
  const tracer = getTracer();
  const logger = getLogger();

  const span = tracer.startSpan('stripe.payment.confirm', {
    attributes: {
      'payment.amount': options.amount,
      'payment.currency': options.currency,
      'payment.gateway': 'stripe',
    },
  });

  logger.emit({
    severityNumber: SeverityNumber.INFO,
    body: 'Payment confirmation started',
    attributes: {
      'event.name': 'payment.started',
      'payment.amount': options.amount,
      'payment.currency': options.currency,
    },
  });

  return context.with(trace.setSpan(context.active(), span), async () => {
    try {
      const { error } = await stripe.confirmPayment({
        elements,
        confirmParams: { return_url: options.returnUrl },
        redirect: 'if_required',
      });

      if (error) {
        span.setAttribute('payment.status', 'failed');
        span.setAttribute('payment.error.type', error.type ?? 'unknown');
        if (error.code) span.setAttribute('payment.error.code', error.code);
        if (error.decline_code) span.setAttribute('payment.error.decline_code', error.decline_code);
        span.setStatus({
          code: SpanStatusCode.ERROR,
          message: error.message ?? 'Payment failed',
        });

        logger.emit({
          severityNumber: SeverityNumber.ERROR,
          body: `Payment failed: ${error.message}`,
          attributes: {
            'event.name': 'payment.failed',
            'payment.error.type': error.type ?? 'unknown',
            'payment.error.code': error.code ?? '',
            'payment.error.decline_code': error.decline_code ?? '',
            'payment.amount': options.amount,
            'payment.currency': options.currency,
          },
        });
      } else {
        span.setAttribute('payment.status', 'succeeded');
        span.setStatus({ code: SpanStatusCode.OK });

        logger.emit({
          severityNumber: SeverityNumber.INFO,
          body: 'Payment succeeded',
          attributes: {
            'event.name': 'payment.succeeded',
            'payment.amount': options.amount,
            'payment.currency': options.currency,
          },
        });
      }

      return { error };
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      span.recordException(err as Error);
      span.setStatus({ code: SpanStatusCode.ERROR, message });
      throw err;
    } finally {
      span.end();
    }
  });
};

// ── 3DS return handling ───────────────────────────────────────────────────────

/**
 * Call on component mount to detect a return from a 3DS redirect.
 *
 * When Stripe redirects for 3DS, it appends ?payment_intent_client_secret=...
 * to the returnUrl. Calling this function creates a span + log for the
 * completed authentication so you have visibility into 3DS challenge outcomes.
 */
export const checkReturnFrom3DS = (stripe: Stripe): void => {
  const params = new URLSearchParams(window.location.search);
  const clientSecret = params.get('payment_intent_client_secret');
  if (!clientSecret) return;

  const tracer = getTracer();
  const logger = getLogger();

  stripe.retrievePaymentIntent(clientSecret).then(({ paymentIntent }) => {
    if (!paymentIntent) return;

    const status = paymentIntent.status;
    const succeeded = status === 'succeeded';

    const span = tracer.startSpan('stripe.3ds.challenge', {
      attributes: {
        '3ds.required': true,
        '3ds.completed': succeeded,
        'payment.intent_id': paymentIntent.id,
        'payment.status': status,
        'payment.amount': paymentIntent.amount,
        'payment.currency': paymentIntent.currency,
      },
    });

    span.setStatus(succeeded ? { code: SpanStatusCode.OK } : { code: SpanStatusCode.ERROR, message: `3DS result: ${status}` });
    span.end();

    logger.emit({
      severityNumber: succeeded ? SeverityNumber.INFO : SeverityNumber.WARN,
      body: `3DS challenge completed — status: ${status}`,
      attributes: {
        'event.name': succeeded ? '3ds.succeeded' : '3ds.failed',
        '3ds.required': true,
        'payment.intent_id': paymentIntent.id,
        'payment.status': status,
      },
    });

    // Clean up URL params so a page refresh doesn't re-process
    const cleanUrl = window.location.pathname;
    window.history.replaceState({}, '', cleanUrl);
  });
};
