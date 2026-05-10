"""
Braintrust + Last9 dual-export example — collector mode.

The app emits OTLP/HTTP to a local OpenTelemetry Collector. The collector's
trace pipeline fans out to two `otlphttp` exporters: one targeting Braintrust,
one targeting Last9.

This keeps the app vendor-agnostic: routing, headers, and per-backend filtering
live in `otel-collector-config.yaml`, not in app code.
"""

import json
import os
import time

from openai import OpenAI
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import SERVICE_NAME, Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.trace import SpanKind, Status, StatusCode

# ── Setup ────────────────────────────────────────────────────────────────────

resource = Resource.create({
    SERVICE_NAME: os.environ.get("OTEL_SERVICE_NAME", "braintrust-collector-example"),
    "deployment.environment": os.environ.get("DEPLOYMENT_ENV", "local"),
})

provider = TracerProvider(resource=resource)

# Single OTLP exporter to the local collector. The collector fans out to
# Braintrust and Last9 — see otel-collector-config.yaml.
provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))

trace.set_tracer_provider(provider)
tracer = trace.get_tracer("braintrust-collector-example")
client = OpenAI()

MODEL = "gpt-4o-mini"


# ── Demo workload ────────────────────────────────────────────────────────────


def call_llm(prompt: str) -> str:
    """One LLM call with gen_ai.* semantic-convention attributes."""
    with tracer.start_as_current_span("gen_ai.chat", kind=SpanKind.CLIENT) as span:
        span.set_attribute("gen_ai.system", "openai")
        span.set_attribute("gen_ai.request.model", MODEL)
        span.set_attribute("gen_ai.operation.name", "chat")

        span.add_event("gen_ai.content.prompt", attributes={
            "gen_ai.prompt": json.dumps([{"role": "user", "content": prompt}]),
        })

        try:
            response = client.chat.completions.create(
                model=MODEL,
                messages=[{"role": "user", "content": prompt}],
            )
        except Exception as exc:
            span.record_exception(exc)
            span.set_status(Status(StatusCode.ERROR, str(exc)))
            raise

        completion = response.choices[0].message.content or ""

        span.add_event("gen_ai.content.completion", attributes={
            "gen_ai.completion": json.dumps(
                {"role": "assistant", "content": completion}
            ),
        })
        span.set_attribute("gen_ai.response.id", response.id)
        span.set_attribute("gen_ai.response.model", response.model)
        span.set_attribute("gen_ai.usage.input_tokens", response.usage.prompt_tokens)
        span.set_attribute("gen_ai.usage.output_tokens", response.usage.completion_tokens)
        span.set_attribute("gen_ai.response.finish_reasons",
                           [response.choices[0].finish_reason or "stop"])
        return completion


def emit_score_span(eval_name: str, scores: dict, input_text: str,
                    output_text: str, expected_text: str) -> None:
    """
    Emit a Braintrust-compatible eval/score span via OTLP.

    The braintrust.span_attributes.type = "score" discriminator turns this
    into a Braintrust score span on ingest. Last9 sees it as a regular OTel
    span with the eval/score attributes attached.
    """
    with tracer.start_as_current_span(eval_name, kind=SpanKind.INTERNAL) as span:
        span.set_attribute("braintrust.span_attributes",
                           json.dumps({"name": eval_name, "type": "score"}))
        span.set_attribute("braintrust.scores", json.dumps(scores))
        span.set_attribute("braintrust.input", input_text)
        span.set_attribute("braintrust.output", output_text)
        span.set_attribute("braintrust.expected", expected_text)


def levenshtein_score(output: str, expected: str) -> float:
    """Tiny normalized Levenshtein for the score demo."""
    if not output and not expected:
        return 1.0
    a, b = output.lower(), expected.lower()
    if len(a) < len(b):
        a, b = b, a
    if not b:
        return 0.0
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        curr = [i]
        for j, cb in enumerate(b, 1):
            curr.append(min(curr[-1] + 1, prev[j] + 1,
                            prev[j - 1] + (ca != cb)))
        prev = curr
    distance = prev[-1]
    return 1.0 - distance / max(len(a), len(b))


# ── Run ──────────────────────────────────────────────────────────────────────


def main() -> None:
    eval_name = f"say-hi-eval-{int(time.time())}"
    cases = [
        {"input": "Foo", "expected": "Hi Foo"},
        {"input": "Bar", "expected": "Hi Bar"},
    ]

    with tracer.start_as_current_span(eval_name, kind=SpanKind.INTERNAL) as root:
        root.set_attribute("braintrust.span_attributes",
                           json.dumps({"name": eval_name, "type": "eval"}))
        root.set_attribute("braintrust.input", json.dumps(cases))
        root.set_attribute("braintrust.metadata",
                           json.dumps({"num_cases": len(cases), "model": MODEL}))

        for case in cases:
            output = call_llm(f"Greet the person named {case['input']} in three words.")
            score = levenshtein_score(output, case["expected"])
            emit_score_span(
                "Levenshtein",
                {"levenshtein": round(score, 3)},
                case["input"], output, case["expected"],
            )
            print(f"  input={case['input']!r}  output={output!r}  score={score:.3f}")

        print(f"\nEval: {eval_name}")
        print(f"Trace: {root.get_span_context().trace_id:032x}")

    provider.force_flush()
    provider.shutdown()


if __name__ == "__main__":
    main()
