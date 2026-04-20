"""
Demo: tracking multi-agent identity with last9_genai.agent_context().

Shows the OTel GenAI semantic-convention agent attributes
(`gen_ai.agent.id`, `gen_ai.agent.name`, `gen_ai.agent.description`,
`gen_ai.agent.version`) being auto-propagated onto every span within
an `agent_context()` block, composed with `conversation_context()` and
`workflow_context()`.

Run:
    export OPENAI_API_KEY=...
    export OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp-aps1.last9.io:443
    export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <token>"
    export OTEL_SERVICE_NAME=last9-genai-agent-demo
    export OTEL_RESOURCE_ATTRIBUTES=deployment.environment=local

    uv run --with 'last9-genai>=1.2' --with opentelemetry-exporter-otlp \\
        --with openai python last9_agent_context.py
"""

import os
import time

from openai import OpenAI
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

from last9_genai import (
    Last9SpanProcessor,
    agent_context,
    conversation_context,
    workflow_context,
)


provider = TracerProvider()
provider.add_span_processor(Last9SpanProcessor())
provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))
trace.set_tracer_provider(provider)

tracer = trace.get_tracer("agent-demo")
client = OpenAI()


def call_llm(model: str, prompt: str) -> str:
    """Single LLM call wrapped in its own span so the agent attrs attach."""
    with tracer.start_as_current_span(f"chat.{model}") as span:
        span.set_attribute("gen_ai.request.model", model)
        span.set_attribute("gen_ai.operation.name", "chat")
        span.set_attribute("gen_ai.system", "openai")

        response = client.chat.completions.create(
            model=model,
            messages=[{"role": "user", "content": prompt}],
        )

        span.set_attribute("gen_ai.usage.input_tokens", response.usage.prompt_tokens)
        span.set_attribute(
            "gen_ai.usage.output_tokens", response.usage.completion_tokens
        )
        return response.choices[0].message.content or ""


def router_agent(query: str) -> str:
    with agent_context(
        agent_name="Router",
        agent_id="router_v1",
        agent_description="Classifies a user query into a support topic",
        agent_version="1.0",
    ):
        return call_llm("gpt-4o-mini", f"Classify in one word: {query}")


def refund_agent(query: str) -> str:
    with agent_context(
        agent_name="Refund Agent",
        agent_id="refund_v3",
        agent_description="Handles refund-related requests",
        agent_version="3.1",
    ):
        with workflow_context(workflow_id="refund-flow", workflow_type="tool_use"):
            return call_llm(
                "gpt-4o-mini",
                f"Draft a one-line apology for this refund: {query}",
            )


def main() -> None:
    session_id = f"agent-demo-{int(time.time())}"

    with conversation_context(conversation_id=session_id, user_id="demo-user"):
        query = "I want to return my order"
        topic = router_agent(query)
        print(f"Router classified topic as: {topic.strip()}")

        reply = refund_agent(query)
        print(f"Refund Agent replied: {reply.strip()}")

    provider.force_flush()
    provider.shutdown()


if __name__ == "__main__":
    main()
