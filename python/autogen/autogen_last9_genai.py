"""
Demo: AutoGen + last9_genai + opentelemetry-instrumentation-openai-v2.

Verifies that Last9LogToSpanProcessor bridges OTel GenAI log events (prompts,
completions, tool calls) onto the active span so the Last9 LLM dashboard can
render messages.

Run:
    export OPENAI_API_KEY=...
    uv run --python 3.12 \\
        --with autogen-agentchat \\
        --with 'autogen-ext[openai]' \\
        --with opentelemetry-instrumentation-openai-v2 \\
        --with 'last9-genai @ file:///Users/prathamesh2_/Projects/python-ai-sdk' \\
        --with openai \\
        --with 'wrapt<2' \\
        python autogen_last9_genai.py

Note: py3.14 is incompatible with wrapt's kwarg usage in opentelemetry-
instrumentation-openai-v2 2.3b0; pin python 3.12/3.13 until upstream fix.
"""
import asyncio
import os

os.environ.setdefault("OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT", "true")

from opentelemetry import trace, _logs
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor, ConsoleSpanExporter
from opentelemetry.sdk._logs import LoggerProvider

from last9_genai import (
    Last9SpanProcessor,
    Last9LogToSpanProcessor,
    conversation_context,
    workflow_context,
)

log_bridge = Last9LogToSpanProcessor()

provider = TracerProvider()
provider.add_span_processor(Last9SpanProcessor(log_processor=log_bridge))
provider.add_span_processor(BatchSpanProcessor(ConsoleSpanExporter()))
trace.set_tracer_provider(provider)

logger_provider = LoggerProvider()
logger_provider.add_log_record_processor(log_bridge)
_logs.set_logger_provider(logger_provider)

from opentelemetry.instrumentation.openai_v2 import OpenAIInstrumentor

OpenAIInstrumentor().instrument(logger_provider=logger_provider)

from autogen_agentchat.agents import AssistantAgent
from autogen_ext.models.openai import OpenAIChatCompletionClient


def get_weather(city: str) -> str:
    return f"Weather in {city}: sunny, 72F"


async def main():
    model_client = OpenAIChatCompletionClient(model="gpt-4o-mini")
    agent = AssistantAgent(
        name="weather_agent",
        model_client=model_client,
        tools=[get_weather],
        system_message="You are a weather assistant. Use get_weather when asked.",
    )

    with conversation_context(conversation_id="demo-thread-1", user_id="demo-user"):
        with workflow_context(
            workflow_id="agent_message_turn", workflow_type="message_processing"
        ):
            async for msg in agent.run_stream(
                task="Weather in Pune?", output_task_messages=False
            ):
                print("MSG:", type(msg).__name__)

    await model_client.close()
    provider.force_flush()
    provider.shutdown()


if __name__ == "__main__":
    asyncio.run(main())
