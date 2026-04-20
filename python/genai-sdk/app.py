"""
Last9 GenAI SDK example — multi-turn conversation tracing.

Demonstrates conversation tracking, workflow grouping, and
prompt/completion event capture with OpenTelemetry.
"""

import json
import os
import time

from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.resources import SERVICE_NAME, Resource
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.trace import SpanKind

from last9_genai import Last9SpanProcessor, conversation_context, workflow_context

# ── Setup ────────────────────────────────────────────────────────────────────

resource = Resource.create({
    SERVICE_NAME: os.environ.get("OTEL_SERVICE_NAME", "genai-example"),
    "deployment.environment": os.environ.get("DEPLOYMENT_ENV", "local"),
})

provider = TracerProvider(resource=resource)
provider.add_span_processor(Last9SpanProcessor())

endpoint = os.environ["OTEL_EXPORTER_OTLP_ENDPOINT"]
auth = os.environ["OTEL_EXPORTER_OTLP_HEADERS"]

provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter(
    endpoint=f"{endpoint.rstrip('/')}/v1/traces",
    headers={"Authorization": auth},
)))

trace.set_tracer_provider(provider)
tracer = trace.get_tracer("genai-example")

# ── Helpers ──────────────────────────────────────────────────────────────────


def simulate_llm_call(messages, *, call_type="initial", after_tools=None,
                      response_text="OK", input_tokens=100, output_tokens=50):
    """Simulate an LLM call with proper span events."""
    with tracer.start_as_current_span("gen_ai.chat", kind=SpanKind.CLIENT) as span:
        span.set_attribute("gen_ai.system", "anthropic")
        span.set_attribute("gen_ai.request.model", "claude-sonnet-4-6")
        span.set_attribute("gen_ai.call.type", call_type)
        span.set_attribute("llm.message_count", len(messages))
        if after_tools:
            span.set_attribute("gen_ai.call.after_tools", after_tools)

        # Record prompt
        span.add_event("gen_ai.content.prompt", attributes={
            "gen_ai.prompt": json.dumps(messages[-4:]),
        })

        time.sleep(0.05)  # simulate latency

        # Record completion
        span.add_event("gen_ai.content.completion", attributes={
            "gen_ai.completion": json.dumps({"role": "assistant", "content": response_text}),
        })

        span.set_attribute("gen_ai.usage.input_tokens", input_tokens)
        span.set_attribute("gen_ai.usage.output_tokens", output_tokens)
        span.set_attribute("gen_ai.response.finish_reasons",
                           ["end_turn"] if call_type == "synthesis" else ["tool_use"])

    return response_text


def simulate_tool_call(tool_name, tool_input):
    """Simulate a tool execution span."""
    with tracer.start_as_current_span(tool_name, kind=SpanKind.INTERNAL) as span:
        span.set_attribute("mithai.tool.name", tool_name)
        span.set_attribute("mithai.tool.approved", True)
        span.set_attribute("mithai.tool.input", json.dumps(tool_input)[:500])
        time.sleep(0.1)  # simulate execution


# ── Multi-turn conversation ──────────────────────────────────────────────────

THREAD_ID = "demo-conversation-001"
USER_ID = "user_demo"

print(f"Conversation ID: {THREAD_ID}\n")

# Turn 1: User asks about failing pods
print("Turn 1: Are there any failing pods?")
with conversation_context(conversation_id=THREAD_ID, user_id=USER_ID):
    with tracer.start_as_current_span("mithai.request", kind=SpanKind.SERVER) as root:
        root.set_attribute("mithai.platform", "slack")
        root.set_attribute("mithai.thread_id", THREAD_ID)
        root.set_attribute("mithai.user_id", USER_ID)
        root.set_attribute("mithai.message.text", "Are there any failing pods in production?")

        messages = [{"role": "user", "content": "Are there any failing pods in production?"}]

        # LLM decides to call a tool
        simulate_llm_call(messages, call_type="initial", input_tokens=220, output_tokens=35)

        # Tool-use workflow
        with workflow_context(workflow_id=f"{THREAD_ID}:0", workflow_type="tool_use_loop"):
            simulate_tool_call("kubernetes__get_pods", {"namespace": "production", "status": "Failed"})

        # LLM synthesizes the result
        simulate_llm_call(messages, call_type="synthesis",
                          after_tools=["kubernetes__get_pods"],
                          response_text="Found 1 failing pod: api-gateway-7f8b9c is in CrashLoopBackOff.",
                          input_tokens=480, output_tokens=120)

    print(f"  Trace: {root.get_span_context().trace_id:032x}")

# Turn 2: User asks to check logs
print("Turn 2: Check the logs")
with conversation_context(conversation_id=THREAD_ID, user_id=USER_ID):
    with tracer.start_as_current_span("mithai.request", kind=SpanKind.SERVER) as root:
        root.set_attribute("mithai.platform", "slack")
        root.set_attribute("mithai.thread_id", THREAD_ID)
        root.set_attribute("mithai.user_id", USER_ID)
        root.set_attribute("mithai.message.text", "Check the logs for that pod")

        messages = [{"role": "user", "content": "Check the logs for that pod"}]

        simulate_llm_call(messages, call_type="initial", input_tokens=650, output_tokens=40)

        with workflow_context(workflow_id=f"{THREAD_ID}:1", workflow_type="tool_use_loop"):
            simulate_tool_call("shell__run_command",
                               {"command": "kubectl logs api-gateway-7f8b9c -n production --tail=50"})

        simulate_llm_call(messages, call_type="synthesis",
                          after_tools=["shell__run_command"],
                          response_text="The pod is crashing due to postgres connection refused on port 5432.",
                          input_tokens=1200, output_tokens=250)

    print(f"  Trace: {root.get_span_context().trace_id:032x}")

# Turn 3: User asks to restart
print("Turn 3: Restart postgres")
with conversation_context(conversation_id=THREAD_ID, user_id=USER_ID):
    with tracer.start_as_current_span("mithai.request", kind=SpanKind.SERVER) as root:
        root.set_attribute("mithai.platform", "slack")
        root.set_attribute("mithai.thread_id", THREAD_ID)
        root.set_attribute("mithai.user_id", USER_ID)
        root.set_attribute("mithai.message.text", "Restart the postgres statefulset")

        messages = [{"role": "user", "content": "Restart the postgres statefulset"}]

        simulate_llm_call(messages, call_type="initial", input_tokens=800, output_tokens=30)

        with workflow_context(workflow_id=f"{THREAD_ID}:2", workflow_type="tool_use_loop"):
            simulate_tool_call("shell__run_command",
                               {"command": "kubectl rollout restart statefulset/postgres -n production"})

        simulate_llm_call(messages, call_type="synthesis",
                          after_tools=["shell__run_command"],
                          response_text="Postgres restarted. The api-gateway should recover automatically.",
                          input_tokens=950, output_tokens=85)

    print(f"  Trace: {root.get_span_context().trace_id:032x}")

# Flush
provider.force_flush()
print(f"\nAll traces sent! Filter by gen_ai.conversation.id = {THREAD_ID}")
