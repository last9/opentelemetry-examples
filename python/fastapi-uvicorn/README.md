# FastAPI with OpenTelemetry and Last9 GenAI Tracking

This example demonstrates how to instrument a FastAPI application with OpenTelemetry and the Last9 GenAI SDK for comprehensive LLM cost tracking and observability.

## Features

- **Standard OpenTelemetry instrumentation** for FastAPI endpoints
- **Last9 GenAI SDK integration** for LLM cost tracking
- **Automatic cost calculation** for Claude, GPT-4, Gemini, and other models
- **Workflow-level cost aggregation** across multi-step processes
- **Multi-turn conversation tracking** with context preservation
- **Tool/function call tracking** with performance metrics
- **Content events** for prompt/completion tracking

## Prerequisites

1. **Python 3.7+** installed
2. **Last9 account** - Get your OTLP credentials from [Last9 Dashboard](https://app.last9.io)
3. **Anthropic API key** - Get from [Anthropic Console](https://console.anthropic.com/)

## Quick Start

### 1. Create virtual environment and install dependencies

```bash
cd /home/karthikeyan/Documents/last9/opentelemetry-examples/python/fastapi-uvicorn

# Create and activate virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt
```

### 2. Configure environment variables

Copy the example environment file and fill in your credentials:

```bash
cp .env.example .env
```

Edit `.env` and set:

```bash
# Last9 Configuration
OTEL_SERVICE_NAME=fastapi-genai-app
OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp.last9.io
OTEL_EXPORTER_OTLP_HEADERS=Authorization=Basic%20<YOUR_BASE64_ENCODED_CREDENTIALS>
OTEL_TRACES_EXPORTER=otlp
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf

# Anthropic API Key
ANTHROPIC_API_KEY=<YOUR_ANTHROPIC_API_KEY>
```

**Important:** The `OTEL_EXPORTER_OTLP_HEADERS` value must be URL encoded. Replace spaces with `%20`.

#### How to get Last9 credentials:

1. Go to [Last9 Dashboard](https://app.last9.io)
2. Navigate to Settings → OTLP
3. Copy the Basic Auth header
4. URL encode it (replace spaces with `%20`)

Example:
- Original: `Basic dXNlcjpwYXNz`
- Encoded: `Basic%20dXNlcjpwYXNz`

For more details: [Python OTEL SDK - Whitespace in OTLP Headers](https://last9.io/blog/whitespace-in-otlp-headers-and-opentelemetry-python-sdk/)

### 3. Run the application

Load environment variables and start:

```bash
# Load environment variables
source .env  # or: export $(cat .env | xargs)

# Start the application
./start.sh
```

The script will automatically:
- Use Gunicorn + Uvicorn workers in production mode (if `OTEL_EXPORTER_OTLP_ENDPOINT` is set)
- Use simple Uvicorn for local development (if endpoint not set)

### 4. Test the API

**Check health:**
```bash
curl http://localhost:8000/health
```

**Simple chat (with cost tracking):**
```bash
curl -X POST http://localhost:8000/chat \
  -H "Content-Type: application/json" \
  -d '{
    "message": "What is the capital of France?",
    "model": "claude-sonnet-4-5-20250929",
    "max_tokens": 100
  }'
```

Response:
```json
{
  "response": "The capital of France is Paris...",
  "model": "claude-sonnet-4-5-20250929",
  "cost": 0.000045,
  "input_tokens": 15,
  "output_tokens": 25
}
```

**Multi-step workflow (with cost aggregation):**
```bash
curl -X POST http://localhost:8000/workflow \
  -H "Content-Type: application/json" \
  -d '{
    "task": "Analyze the benefits of serverless architecture"
  }'
```

Response:
```json
{
  "result": "Based on the analysis, serverless architecture offers...",
  "workflow_id": "workflow_1234567890",
  "total_cost": 0.000123,
  "llm_calls": 2,
  "tool_calls": 1
}
```

**Multi-turn conversation:**
```bash
curl -X POST http://localhost:8000/conversation \
  -H "Content-Type: application/json" \
  -d '{
    "conversation_id": "conv_user123_session456",
    "message": "Hello, how are you?"
  }'

# Second turn
curl -X POST http://localhost:8000/conversation \
  -H "Content-Type: application/json" \
  -d '{
    "conversation_id": "conv_user123_session456",
    "message": "Tell me about AI"
  }'
```

### 5. View traces in Last9

1. Go to [Last9 Dashboard](https://app.last9.io)
2. Navigate to APM → Traces
3. You should see traces with:
   - Cost attributes for each LLM call
   - Workflow-level cost aggregation
   - Conversation tracking
   - Content events (prompts/completions)
   - Tool call events

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | API information and available endpoints |
| `/health` | GET | Health check |
| `/chat` | POST | Simple LLM chat with cost tracking |
| `/workflow` | POST | Multi-step workflow with cost aggregation |
| `/conversation` | POST | Multi-turn conversation tracking |

## Last9 GenAI SDK Features

The `last9_genai_attributes.py` file provides:

### 1. Automatic Cost Tracking

```python
cost_breakdown = last9_genai.add_llm_cost_attributes(
    span=span,
    model="claude-sonnet-4-5-20250929",
    usage={
        "input_tokens": 100,
        "output_tokens": 200
    }
)
```

Supports 20+ models:
- Anthropic: Claude 3.5 Sonnet, Claude 3 Opus, Claude 3 Haiku
- OpenAI: GPT-4o, GPT-4, GPT-3.5 Turbo
- Google: Gemini Pro, Gemini 1.5 Pro/Flash
- Cohere: Command R, Command R+

### 2. Workflow Cost Aggregation

```python
# Initialize workflow
last9_genai.add_workflow_attributes(
    span=span,
    workflow_id="workflow_123",
    workflow_type="customer_support"
)

# Add costs from multiple LLM calls
last9_genai.add_llm_cost_attributes(
    span=span1,
    model="claude-sonnet-4-5-20250929",
    usage=usage1,
    workflow_id="workflow_123"
)

last9_genai.add_llm_cost_attributes(
    span=span2,
    model="claude-3-haiku-20240307",
    usage=usage2,
    workflow_id="workflow_123"
)

# Get total cost
workflow_cost = global_workflow_tracker.get_workflow_cost("workflow_123")
# Returns: {total_cost: 0.000123, llm_call_count: 2, tool_call_count: 0}
```

### 3. Conversation Tracking

```python
# Start conversation
global_conversation_tracker.start_conversation(
    conversation_id="conv_123",
    user_id="user_456"
)

# Add turns
global_conversation_tracker.add_turn(
    conversation_id="conv_123",
    user_message="Hello",
    assistant_message="Hi there!",
    model="claude-sonnet-4-5-20250929",
    usage=usage,
    cost=0.000012
)

# Get stats
stats = global_conversation_tracker.get_conversation_stats("conv_123")
# Returns: {turn_count: 5, total_cost: 0.000234, ...}
```

### 4. Tool/Function Call Tracking

```python
last9_genai.add_tool_attributes(
    span=span,
    tool_name="database_query",
    function_name="get_user_profile",
    arguments={"user_id": "123"},
    result={"name": "John", "email": "john@example.com"},
    workflow_id="workflow_123"
)
```

### 5. Content Events

```python
# Add prompt/completion as span events
last9_genai.add_content_events(
    span=span,
    prompt="What is AI?",
    completion="Artificial Intelligence is...",
    truncate_at=1000  # Optional truncation
)
```

## Last9 Attributes Reference

The SDK adds these custom attributes to your traces:

| Attribute | Description | Example |
|-----------|-------------|---------|
| `gen_ai.l9.span.kind` | Span classification | `llm`, `tool`, `prompt` |
| `gen_ai.l9.cost.input` | Input cost in USD | `0.000015` |
| `gen_ai.l9.cost.output` | Output cost in USD | `0.000030` |
| `gen_ai.l9.cost.total` | Total cost in USD | `0.000045` |
| `gen_ai.l9.workflow.id` | Workflow identifier | `workflow_123` |
| `gen_ai.l9.workflow.type` | Workflow type | `customer_support` |
| `gen_ai.l9.workflow.cost.total` | Total workflow cost | `0.000234` |
| `gen_ai.l9.conversation.id` | Conversation ID | `conv_user123` |
| `gen_ai.l9.conversation.turn` | Turn number | `3` |
| `gen_ai.l9.tool.name` | Tool/function name | `database_query` |
| `gen_ai.l9.performance.response_time` | Response time (seconds) | `1.234` |

## Architecture

```
FastAPI Application
    ↓
OpenTelemetry Auto-Instrumentation
    ↓
Last9 GenAI SDK (Manual Instrumentation)
    ├─→ Cost Calculation
    ├─→ Workflow Tracking
    ├─→ Conversation Tracking
    └─→ Content Events
    ↓
OTLP Exporter → Last9 Backend
```

## Local Development (Console Exporter)

For local testing without sending to Last9:

```bash
# Don't set OTEL_EXPORTER_OTLP_ENDPOINT
unset OTEL_EXPORTER_OTLP_ENDPOINT

# Set console exporter
export OTEL_TRACES_EXPORTER=console
export OTEL_SERVICE_NAME=fastapi-genai-app

# Set Anthropic key
export ANTHROPIC_API_KEY=<your-key>

# Run
./start.sh
```

This will print traces to console instead of sending to Last9.

## Production Deployment

### Using Gunicorn + Circus

The included configuration supports production deployment with:

- **Gunicorn** with Uvicorn workers (2 workers by default)
- **Circus** process manager for monitoring and restarts
- **OpenTelemetry auto-instrumentation** via `opentelemetry-instrument` wrapper
- **Graceful worker lifecycle management**

Configuration files:
- `gunicorn.conf.py` - Gunicorn configuration (workers, timeouts, etc.)
- `circus.ini` - Circus process manager configuration
- `start.sh` - Startup script with conditional logic

### Start in production mode:

```bash
# Ensure OTEL_EXPORTER_OTLP_ENDPOINT is set
export OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp.last9.io
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic%20<credentials>"
export ANTHROPIC_API_KEY=<your-key>

# Start
./start.sh
```

## Troubleshooting

### Issue: "Anthropic client not configured"

**Solution:** Set the `ANTHROPIC_API_KEY` environment variable:
```bash
export ANTHROPIC_API_KEY=<your-anthropic-api-key>
```

### Issue: Traces not showing in Last9

**Solutions:**
1. Check `OTEL_EXPORTER_OTLP_ENDPOINT` is set correctly
2. Verify `OTEL_EXPORTER_OTLP_HEADERS` is URL encoded
3. Check Last9 credentials are valid
4. Look for errors in application logs

### Issue: Import error for `last9_genai_attributes`

**Solution:** Ensure `last9_genai_attributes.py` is in the same directory as `app.py`

### Issue: Cost calculation seems wrong

**Solution:** Check model name matches exactly. The SDK uses model name to look up pricing.

## Additional Resources

- [Last9 Documentation](https://docs.last9.io/)
- [OpenTelemetry Python Docs](https://opentelemetry.io/docs/instrumentation/python/)
- [Anthropic API Reference](https://docs.anthropic.com/)
- [Last9 GenAI SDK Repository](https://github.com/last9/ai/tree/master/sdk/python)

## Project Structure

```
fastapi-uvicorn/
├── app.py                      # FastAPI application with GenAI endpoints
├── last9_genai_attributes.py   # Last9 GenAI SDK (single file utility)
├── requirements.txt            # Python dependencies
├── .env.example               # Environment configuration template
├── start.sh                   # Startup script
├── gunicorn.conf.py          # Gunicorn configuration
├── circus.ini                # Circus process manager config
└── README.md                 # This file
```

## License

MIT
