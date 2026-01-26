import os
import time
import uvicorn
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import Optional, List
from opentelemetry import trace
from opentelemetry.trace import Status, StatusCode

# Import Last9 GenAI SDK
from last9_genai_attributes import (
    Last9GenAI,
    global_workflow_tracker,
    global_conversation_tracker,
)

# Import Anthropic SDK (optional, graceful fallback if not installed)
try:
    from anthropic import Anthropic
    ANTHROPIC_AVAILABLE = True
except ImportError:
    ANTHROPIC_AVAILABLE = False
    print("⚠️  Anthropic SDK not installed. Install with: pip install anthropic")

# Create a FastAPI application
app = FastAPI(title="Last9 GenAI FastAPI Example")

# Initialize Last9 GenAI utility
last9_genai = Last9GenAI()

# Get tracer
tracer = trace.get_tracer(__name__)

# Initialize Anthropic client if available
anthropic_client = None
if ANTHROPIC_AVAILABLE and os.getenv("ANTHROPIC_API_KEY"):
    anthropic_client = Anthropic(api_key=os.getenv("ANTHROPIC_API_KEY"))
    print("✅ Anthropic client initialized")
else:
    print("⚠️  Anthropic API key not set. Set ANTHROPIC_API_KEY environment variable.")


# Request/Response Models
class ChatRequest(BaseModel):
    message: str
    model: Optional[str] = "claude-sonnet-4-5-20250929"
    max_tokens: Optional[int] = 1024


class ChatResponse(BaseModel):
    response: str
    model: str
    cost: float
    input_tokens: int
    output_tokens: int


class WorkflowRequest(BaseModel):
    task: str


class WorkflowResponse(BaseModel):
    result: str
    workflow_id: str
    total_cost: float
    llm_calls: int
    tool_calls: int


class ConversationRequest(BaseModel):
    conversation_id: str
    message: str
    model: Optional[str] = "claude-sonnet-4-5-20250929"


class ConversationResponse(BaseModel):
    response: str
    conversation_id: str
    turn_count: int
    total_cost: float


# Basic endpoints
@app.get("/")
async def root():
    return {
        "message": "Last9 GenAI FastAPI Example",
        "endpoints": {
            "/chat": "POST - Simple LLM chat with cost tracking",
            "/workflow": "POST - Multi-step workflow with cost aggregation",
            "/conversation": "POST - Multi-turn conversation tracking",
            "/health": "GET - Health check"
        },
        "anthropic_available": ANTHROPIC_AVAILABLE and anthropic_client is not None
    }


@app.get("/health")
async def health():
    return {
        "status": "healthy",
        "anthropic_configured": ANTHROPIC_AVAILABLE and anthropic_client is not None
    }


@app.post("/chat", response_model=ChatResponse)
async def chat(request: ChatRequest):
    """
    Simple chat endpoint with Last9 GenAI cost tracking.

    This demonstrates:
    - LLM span creation and classification
    - Automatic cost calculation
    - Token usage tracking
    - Content events (prompt/completion)
    """
    if not anthropic_client:
        raise HTTPException(
            status_code=503,
            detail="Anthropic client not configured. Set ANTHROPIC_API_KEY environment variable."
        )

    # Create a span for the LLM operation
    with tracer.start_as_current_span("chat_endpoint") as parent_span:
        try:
            # Classify the span and add workflow attributes
            last9_genai.set_span_kind(parent_span, "llm")

            # Create LLM span
            with tracer.start_as_current_span("anthropic.chat") as llm_span:
                try:
                    # Set span kind as LLM
                    last9_genai.set_span_kind(llm_span, "llm")

                    # Add standard LLM attributes
                    last9_genai.add_standard_llm_attributes(
                        span=llm_span,
                        model=request.model,
                        operation="chat",
                        request_params={
                            "max_tokens": request.max_tokens,
                            "temperature": 1.0
                        }
                    )

                    # Add prompt as content event
                    last9_genai.add_content_events(
                        span=llm_span,
                        prompt=request.message,
                        completion=None  # Will add after response
                    )

                    # Track performance
                    start_time = time.time()

                    # Call Anthropic API
                    response = anthropic_client.messages.create(
                        model=request.model,
                        max_tokens=request.max_tokens,
                        messages=[{"role": "user", "content": request.message}]
                    )

                    response_time = time.time() - start_time

                    # Extract response
                    completion_text = response.content[0].text

                    # Add completion as content event
                    last9_genai.add_content_events(
                        span=llm_span,
                        prompt=None,
                        completion=completion_text
                    )

                    # Add cost attributes
                    usage = {
                        "input_tokens": response.usage.input_tokens,
                        "output_tokens": response.usage.output_tokens
                    }

                    cost_breakdown = last9_genai.add_llm_cost_attributes(
                        span=llm_span,
                        model=request.model,
                        usage=usage
                    )

                    # Add performance attributes
                    last9_genai.add_performance_attributes(
                        span=llm_span,
                        response_time_ms=response_time * 1000,  # Convert to milliseconds
                        response_size_bytes=len(completion_text)
                    )

                    # Set span status as OK
                    llm_span.set_status(Status(StatusCode.OK))
                    parent_span.set_status(Status(StatusCode.OK))

                    return ChatResponse(
                        response=completion_text,
                        model=request.model,
                        cost=cost_breakdown.total,
                        input_tokens=usage["input_tokens"],
                        output_tokens=usage["output_tokens"]
                    )

                except Exception as e:
                    # Set child span status as error
                    llm_span.set_status(Status(StatusCode.ERROR, str(e)))
                    llm_span.record_exception(e)
                    # Propagate to parent span handler
                    raise

        except Exception as e:
            # Set parent span status as error
            parent_span.set_status(Status(StatusCode.ERROR, str(e)))
            parent_span.record_exception(e)
            raise HTTPException(status_code=500, detail=str(e))


@app.post("/workflow", response_model=WorkflowResponse)
async def workflow(request: WorkflowRequest):
    """
    Multi-step workflow with cost aggregation.

    This demonstrates:
    - Workflow-level cost tracking
    - Multiple LLM calls aggregated
    - Tool calls within workflow
    - Final cost summary
    """
    if not anthropic_client:
        raise HTTPException(
            status_code=503,
            detail="Anthropic client not configured. Set ANTHROPIC_API_KEY environment variable."
        )

    workflow_id = f"workflow_{int(time.time())}"

    with tracer.start_as_current_span("workflow_endpoint") as parent_span:
        try:
            # Initialize workflow tracking
            last9_genai.add_workflow_attributes(
                span=parent_span,
                workflow_id=workflow_id,
                workflow_type="task_processing",
                user_id="user_123",
                session_id="session_456"
            )
            # Step 1: Analyze task (LLM call)
            with tracer.start_as_current_span("step_1_analyze") as step1_span:
                last9_genai.set_span_kind(step1_span, "llm")
                last9_genai.add_standard_llm_attributes(
                    span=step1_span,
                    model="claude-sonnet-4-5-20250929",
                    operation="chat"
                )

                analyze_response = anthropic_client.messages.create(
                    model="claude-sonnet-4-5-20250929",
                    max_tokens=200,
                    messages=[{
                        "role": "user",
                        "content": f"Analyze this task and provide 3 key points: {request.task}"
                    }]
                )

                usage1 = {
                    "input_tokens": analyze_response.usage.input_tokens,
                    "output_tokens": analyze_response.usage.output_tokens
                }

                last9_genai.add_llm_cost_attributes(
                    span=step1_span,
                    model="claude-sonnet-4-5-20250929",
                    usage=usage1,
                    workflow_id=workflow_id
                )

                analysis = analyze_response.content[0].text

            # Step 2: Simulate tool call (database lookup)
            with tracer.start_as_current_span("step_2_database_lookup") as step2_span:
                last9_genai.set_span_kind(step2_span, "tool")

                start_time = time.time()
                time.sleep(0.1)  # Simulate database query
                duration_ms = (time.time() - start_time) * 1000

                last9_genai.add_tool_attributes(
                    span=step2_span,
                    tool_name="database_query",
                    tool_type="datastore",
                    description="Lookup context from database",
                    arguments={"query": "task_context"},
                    result={"context": "Additional context from database"},
                    duration_ms=duration_ms,
                    workflow_id=workflow_id
                )

            # Step 3: Generate final response (LLM call - using faster Haiku model)
            with tracer.start_as_current_span("step_3_generate_response") as step3_span:
                last9_genai.set_span_kind(step3_span, "llm")
                last9_genai.add_standard_llm_attributes(
                    span=step3_span,
                    model="claude-haiku-4-5-20251001",
                    operation="chat"
                )

                final_response = anthropic_client.messages.create(
                    model="claude-haiku-4-5-20251001",
                    max_tokens=300,
                    messages=[{
                        "role": "user",
                        "content": f"Based on this analysis, provide a concise solution: {analysis}"
                    }]
                )

                usage2 = {
                    "input_tokens": final_response.usage.input_tokens,
                    "output_tokens": final_response.usage.output_tokens
                }

                last9_genai.add_llm_cost_attributes(
                    span=step3_span,
                    model="claude-haiku-4-5-20251001",
                    usage=usage2,
                    workflow_id=workflow_id
                )

                solution = final_response.content[0].text

            # Get workflow cost summary
            workflow_cost = global_workflow_tracker.get_workflow_cost(workflow_id)

            # Clean up workflow tracking
            global_workflow_tracker.delete_workflow(workflow_id)

            # Set span status as OK
            parent_span.set_status(Status(StatusCode.OK))

            return WorkflowResponse(
                result=solution,
                workflow_id=workflow_id,
                total_cost=workflow_cost["total_cost"],
                llm_calls=workflow_cost["llm_call_count"],
                tool_calls=workflow_cost["tool_call_count"]
            )

        except Exception as e:
            # Set parent span status as error
            parent_span.set_status(Status(StatusCode.ERROR, str(e)))
            parent_span.record_exception(e)
            raise HTTPException(status_code=500, detail=str(e))


@app.post("/conversation", response_model=ConversationResponse)
async def conversation(request: ConversationRequest):
    """
    Multi-turn conversation tracking.

    This demonstrates:
    - Conversation ID tracking
    - Turn-by-turn cost tracking
    - Conversation statistics
    - Context preservation
    """
    if not anthropic_client:
        raise HTTPException(
            status_code=503,
            detail="Anthropic client not configured. Set ANTHROPIC_API_KEY environment variable."
        )

    with tracer.start_as_current_span("conversation_endpoint") as parent_span:
        try:
            # Start or continue conversation
            if not global_conversation_tracker.get_conversation_stats(request.conversation_id):
                global_conversation_tracker.start_conversation(
                    conversation_id=request.conversation_id,
                    user_id="user_123",
                    metadata={"session_id": "session_456"}
                )

            with tracer.start_as_current_span("conversation_turn") as turn_span:
                try:
                    last9_genai.set_span_kind(turn_span, "llm")

                    # Add conversation tracking
                    turn_number = len(global_conversation_tracker._conversations[request.conversation_id]) + 1
                    last9_genai.add_conversation_tracking(
                        span=turn_span,
                        conversation_id=request.conversation_id,
                        turn_number=turn_number,
                        user_id="user_123"
                    )

                    last9_genai.add_standard_llm_attributes(
                        span=turn_span,
                        model=request.model,
                        operation="chat"
                    )

                    # Add content events
                    last9_genai.add_content_events(
                        span=turn_span,
                        prompt=request.message,
                        completion=None
                    )

                    # Call Anthropic API
                    start_time = time.time()
                    response = anthropic_client.messages.create(
                        model=request.model,
                        max_tokens=1024,
                        messages=[{"role": "user", "content": request.message}]
                    )
                    response_time = time.time() - start_time

                    completion_text = response.content[0].text

                    # Add completion event
                    last9_genai.add_content_events(
                        span=turn_span,
                        prompt=None,
                        completion=completion_text
                    )

                    # Calculate costs
                    usage = {
                        "input_tokens": response.usage.input_tokens,
                        "output_tokens": response.usage.output_tokens
                    }

                    cost_breakdown = last9_genai.add_llm_cost_attributes(
                        span=turn_span,
                        model=request.model,
                        usage=usage
                    )

                    # Add to conversation tracker
                    global_conversation_tracker.add_turn(
                        conversation_id=request.conversation_id,
                        user_message=request.message,
                        assistant_message=completion_text,
                        model=request.model,
                        usage=usage,
                        cost=cost_breakdown
                    )

                    # Get conversation stats
                    conv_stats = global_conversation_tracker.get_conversation_stats(request.conversation_id)

                    # Set span status as OK
                    turn_span.set_status(Status(StatusCode.OK))
                    parent_span.set_status(Status(StatusCode.OK))

                    return ConversationResponse(
                        response=completion_text,
                        conversation_id=request.conversation_id,
                        turn_count=conv_stats["turn_count"],
                        total_cost=conv_stats["total_cost"]
                    )

                except Exception as e:
                    # Set child span status as error
                    turn_span.set_status(Status(StatusCode.ERROR, str(e)))
                    turn_span.record_exception(e)
                    # Propagate to parent span handler
                    raise

        except Exception as e:
            # Set parent span status as error
            parent_span.set_status(Status(StatusCode.ERROR, str(e)))
            parent_span.record_exception(e)
            raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
