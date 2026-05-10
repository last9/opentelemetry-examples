"""
Braintrust + Last9 dual-export example — direct mode, enhanced with the
Last9 GenAI SDK.

Same dual-export shape as ../braintrust-direct/, with three additions from
the Last9 GenAI SDK:

1. `install()` registers the OTel TracerProvider, the Last9SpanProcessor
   (enriches every span with conversation/agent/workflow context), and
   `opentelemetry-instrumentation-openai-v2` (auto-emits `gen_ai.chat`
   spans + prompt/completion events for every OpenAI client call).
2. `conversation_context()` tags every span in an eval run with the same
   `gen_ai.conversation.id`, so Last9 can group all turns of the run.
3. `agent_context()` differentiates the scorer agent identity on score
   spans via `gen_ai.agent.{id,name,description,version}`.

Span processor order (matters):
  1. Last9SpanProcessor       — enrichment (added by install())
  2. BraintrustSpanProcessor  — exports to Braintrust
  3. BatchSpanProcessor(OTLP) — exports to Last9
"""

import json
import os
import time

# install() must run BEFORE the openai client is imported — auto-instrumentation
# wraps OpenAI's HTTP client at import time, so a late install() instruments
# nothing. Keep this block first.
from last9_genai import (
    agent_context,
    conversation_context,
    install,
    workflow_context,
)

# install() wires the TracerProvider, Last9SpanProcessor, LoggerProvider, and
# OpenAI auto-instrumentation in one call. It reads OTEL_SERVICE_NAME and
# OTEL_RESOURCE_ATTRIBUTES from the environment automatically.
handle = install()

# Now safe to import OpenAI + the rest.
from braintrust.otel import BraintrustSpanProcessor
from openai import OpenAI
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.trace import SpanKind, Status, StatusCode

# ── Setup ────────────────────────────────────────────────────────────────────

# Braintrust: reads BRAINTRUST_API_KEY, BRAINTRUST_PARENT, BRAINTRUST_API_URL.
handle.tracer_provider.add_span_processor(BraintrustSpanProcessor())

# Last9: explicit endpoint + headers.
last9_endpoint = os.environ["LAST9_OTLP_ENDPOINT"].rstrip("/")
last9_auth = os.environ["LAST9_OTLP_AUTH"]
handle.tracer_provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter(
    endpoint=f"{last9_endpoint}/v1/traces",
    headers={"Authorization": last9_auth},
)))

tracer = handle.tracer_provider.get_tracer("braintrust-direct-l9genai-example")
client = OpenAI()

MODEL = "gpt-4o-mini"


# ── Demo workload ────────────────────────────────────────────────────────────


def call_llm(prompt: str) -> str:
    """
    Call OpenAI directly. The OTel `gen_ai.chat` span, prompt/completion
    events, token-usage attributes, and cost-usd attribute are emitted by
    the auto-instrumentation that install() registered — no manual span
    code needed here.
    """
    try:
        response = client.chat.completions.create(
            model=MODEL,
            messages=[{"role": "user", "content": prompt}],
        )
    except Exception as exc:
        # Auto-instrumentation records the exception on its span. We re-raise
        # so the caller can decide whether to fail the eval or continue.
        raise
    return response.choices[0].message.content or ""


def emit_score_span(eval_name: str, scores: dict, input_text: str,
                    output_text: str, expected_text: str) -> None:
    """
    Emit a Braintrust-compatible eval/score span via OTLP. The
    `agent_context()` block stamps `gen_ai.agent.*` attributes onto this
    span so Last9 can tell the Levenshtein scorer apart from any other
    scorer in a multi-scorer eval.
    """
    with agent_context(
        agent_name="Levenshtein Scorer",
        agent_id="scorer.levenshtein.v1",
        agent_description="Normalized Levenshtein similarity 0..1",
        agent_version="1.0",
    ):
        with tracer.start_as_current_span(eval_name, kind=SpanKind.INTERNAL) as span:
            span.set_attribute("braintrust.span_attributes",
                               json.dumps({"name": eval_name, "type": "score"}))
            span.set_attribute("braintrust.scores", json.dumps(scores))
            span.set_attribute("braintrust.input", input_text)
            span.set_attribute("braintrust.output", output_text)
            span.set_attribute("braintrust.expected", expected_text)


def levenshtein_score(output: str, expected: str) -> float:
    """Normalized Levenshtein similarity, 0..1."""
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
    eval_run_id = f"say-hi-eval-{int(time.time())}"
    cases = [
        {"input": "Foo", "expected": "Hi Foo"},
        {"input": "Bar", "expected": "Hi Bar"},
    ]

    # conversation_context tags every span in the eval run with the same
    # gen_ai.conversation.id, so Last9 can group all turns + scores under one
    # filter (gen_ai.conversation.id = <eval_run_id>).
    with conversation_context(conversation_id=eval_run_id, user_id="eval-runner"):
        with tracer.start_as_current_span(eval_run_id, kind=SpanKind.INTERNAL) as root:
            root.set_attribute("braintrust.span_attributes",
                               json.dumps({"name": eval_run_id, "type": "eval"}))
            root.set_attribute("braintrust.input", json.dumps(cases))
            root.set_attribute("braintrust.metadata",
                               json.dumps({"num_cases": len(cases), "model": MODEL}))

            # workflow_context groups the per-case task spans as a named
            # workflow type so Last9 can filter all eval cases by workflow.type.
            with workflow_context(workflow_id=eval_run_id, workflow_type="llm_eval"):
                for case in cases:
                    output = call_llm(
                        f"Greet the person named {case['input']} in three words."
                    )
                    score = levenshtein_score(output, case["expected"])
                    emit_score_span(
                        "Levenshtein",
                        {"levenshtein": round(score, 3)},
                        case["input"], output, case["expected"],
                    )
                    print(f"  input={case['input']!r}  output={output!r}  score={score:.3f}")

            print(f"\nEval: {eval_run_id}")
            print(f"Trace: {root.get_span_context().trace_id:032x}")

    handle.tracer_provider.force_flush()
    handle.tracer_provider.shutdown()


if __name__ == "__main__":
    main()
