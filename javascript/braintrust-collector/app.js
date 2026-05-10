'use strict';

/**
 * Braintrust + Last9 dual-export example — collector mode.
 *
 * The app emits OTLP/HTTP to a local OpenTelemetry Collector. The collector's
 * trace pipeline fans out to two `otlphttp` exporters: one targeting
 * Braintrust, one targeting Last9.
 *
 * Routing, headers, and per-backend filtering live in
 * otel-collector-config.yaml — not in app code.
 */

require('dotenv').config();

const { trace, context, SpanKind, SpanStatusCode } = require('@opentelemetry/api');
const { NodeTracerProvider } = require('@opentelemetry/sdk-trace-node');
const { BatchSpanProcessor } = require('@opentelemetry/sdk-trace-base');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');
const { resourceFromAttributes } = require('@opentelemetry/resources');
const { ATTR_SERVICE_NAME } = require('@opentelemetry/semantic-conventions');
const { OpenAI } = require('openai');

// ── Setup ────────────────────────────────────────────────────────────────────

const provider = new NodeTracerProvider({
  resource: resourceFromAttributes({
    [ATTR_SERVICE_NAME]: process.env.OTEL_SERVICE_NAME || 'braintrust-collector-example',
    'deployment.environment': process.env.DEPLOYMENT_ENV || 'local',
  }),
  // OTLPTraceExporter() with no args reads OTEL_EXPORTER_OTLP_ENDPOINT from env.
  // The collector fans out to Braintrust + Last9 — see otel-collector-config.yaml.
  spanProcessors: [
    new BatchSpanProcessor(new OTLPTraceExporter()),
  ],
});
provider.register();

const tracer = trace.getTracer('braintrust-collector-example');
const openai = new OpenAI();

const MODEL = 'gpt-4o-mini';

// ── Demo workload ────────────────────────────────────────────────────────────

async function callLlm(prompt) {
  return tracer.startActiveSpan('gen_ai.chat', { kind: SpanKind.CLIENT }, async (span) => {
    span.setAttribute('gen_ai.system', 'openai');
    span.setAttribute('gen_ai.request.model', MODEL);
    span.setAttribute('gen_ai.operation.name', 'chat');

    span.addEvent('gen_ai.content.prompt', {
      'gen_ai.prompt': JSON.stringify([{ role: 'user', content: prompt }]),
    });

    let response;
    try {
      response = await openai.chat.completions.create({
        model: MODEL,
        messages: [{ role: 'user', content: prompt }],
      });
    } catch (err) {
      span.recordException(err);
      span.setStatus({ code: SpanStatusCode.ERROR, message: err.message });
      span.end();
      throw err;
    }

    const completion = response.choices[0].message.content || '';

    span.addEvent('gen_ai.content.completion', {
      'gen_ai.completion': JSON.stringify({ role: 'assistant', content: completion }),
    });
    span.setAttribute('gen_ai.response.id', response.id);
    span.setAttribute('gen_ai.response.model', response.model);
    span.setAttribute('gen_ai.usage.input_tokens', response.usage.prompt_tokens);
    span.setAttribute('gen_ai.usage.output_tokens', response.usage.completion_tokens);
    span.setAttribute('gen_ai.response.finish_reasons',
                      [response.choices[0].finish_reason || 'stop']);
    span.end();
    return completion;
  });
}

function emitScoreSpan(evalName, scores, input, output, expected) {
  // The braintrust.span_attributes.type = "score" discriminator turns this
  // into a Braintrust score span on ingest. Last9 sees it as a regular OTel
  // span with the eval/score attributes attached.
  // Pass context.active() so the span nests under the eval root span.
  const span = tracer.startSpan(evalName, { kind: SpanKind.INTERNAL }, context.active());
  span.setAttribute('braintrust.span_attributes',
                    JSON.stringify({ name: evalName, type: 'score' }));
  span.setAttribute('braintrust.scores', JSON.stringify(scores));
  span.setAttribute('braintrust.input', input);
  span.setAttribute('braintrust.output', output);
  span.setAttribute('braintrust.expected', expected);
  span.end();
}

function levenshteinScore(output, expected) {
  if (!output && !expected) return 1.0;
  let a = output.toLowerCase();
  let b = expected.toLowerCase();
  if (a.length < b.length) [a, b] = [b, a];
  if (!b.length) return 0.0;

  let prev = Array.from({ length: b.length + 1 }, (_, i) => i);
  for (let i = 1; i <= a.length; i++) {
    const curr = [i];
    for (let j = 1; j <= b.length; j++) {
      curr.push(Math.min(
        curr[j - 1] + 1,
        prev[j] + 1,
        prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1),
      ));
    }
    prev = curr;
  }
  return 1.0 - prev[b.length] / Math.max(a.length, b.length);
}

// ── Run ──────────────────────────────────────────────────────────────────────

async function main() {
  const evalName = `say-hi-eval-${Math.floor(Date.now() / 1000)}`;
  const cases = [
    { input: 'Foo', expected: 'Hi Foo' },
    { input: 'Bar', expected: 'Hi Bar' },
  ];

  await tracer.startActiveSpan(evalName, { kind: SpanKind.INTERNAL }, async (root) => {
    try {
      root.setAttribute('braintrust.span_attributes',
                        JSON.stringify({ name: evalName, type: 'eval' }));
      root.setAttribute('braintrust.input', JSON.stringify(cases));
      root.setAttribute('braintrust.metadata',
                        JSON.stringify({ num_cases: cases.length, model: MODEL }));

      for (const c of cases) {
        const output = await callLlm(`Greet the person named ${c.input} in three words.`);
        const score = levenshteinScore(output, c.expected);
        emitScoreSpan('Levenshtein',
                      { levenshtein: parseFloat(score.toFixed(3)) },
                      c.input, output, c.expected);
        console.log(`  input=${JSON.stringify(c.input)}  output=${JSON.stringify(output)}  score=${score.toFixed(3)}`);
      }

      console.log(`\nEval: ${evalName}`);
      console.log(`Trace: ${root.spanContext().traceId}`);
    } finally {
      root.end();
    }
  });

  await provider.forceFlush().catch((err) => console.error('Flush failed:', err));
  await provider.shutdown().catch((err) => console.error('Shutdown failed:', err));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
