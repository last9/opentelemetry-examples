#!/usr/bin/env python3
"""
Last9 GenAI Attributes for Python OpenTelemetry

This utility provides Last9-specific gen_ai attributes that complement the standard
OpenTelemetry gen_ai semantic conventions. It adds cost tracking, workflow management,
and enhanced observability features similar to the last9-node-agent.

Usage:
    from last9_genai_attributes import Last9GenAI, model_pricing

    # Initialize the utility
    l9_genai = Last9GenAI()

    # Add Last9 attributes to your spans
    l9_genai.add_llm_cost_attributes(span, model_name, usage_data)
    l9_genai.set_span_kind(span, 'llm')
    l9_genai.add_workflow_attributes(span, workflow_id='my-workflow')

Requirements:
    pip install opentelemetry-api opentelemetry-sdk
"""

import hashlib
import time
from datetime import datetime
from typing import Dict, Any, Optional, Union, List
from dataclasses import dataclass, field
import json
import logging

try:
    from opentelemetry.trace import Span
    from opentelemetry import trace
    from opentelemetry.trace.status import Status, StatusCode
except ImportError:
    raise ImportError(
        "OpenTelemetry packages not found. Install with: "
        "pip install opentelemetry-api opentelemetry-sdk"
    )

logger = logging.getLogger(__name__)

# ============================================================================
# LAST9 GenAI Semantic Conventions - Python Implementation
# Based on last9-node-agent/src/semantic/gen-ai.ts
# ============================================================================

class GenAIAttributes:
    """OpenTelemetry GenAI semantic convention constants"""

    # Standard OpenTelemetry GenAI attributes (v1.28.0)
    PROVIDER_NAME = 'gen_ai.provider.name'
    OPERATION_NAME = 'gen_ai.operation.name'
    CONVERSATION_ID = 'gen_ai.conversation.id'

    # Request attributes
    REQUEST_MODEL = 'gen_ai.request.model'
    REQUEST_MAX_TOKENS = 'gen_ai.request.max_tokens'
    REQUEST_TEMPERATURE = 'gen_ai.request.temperature'
    REQUEST_TOP_P = 'gen_ai.request.top_p'
    REQUEST_FREQUENCY_PENALTY = 'gen_ai.request.frequency_penalty'
    REQUEST_PRESENCE_PENALTY = 'gen_ai.request.presence_penalty'

    # Response attributes
    RESPONSE_ID = 'gen_ai.response.id'
    RESPONSE_MODEL = 'gen_ai.response.model'
    RESPONSE_FINISH_REASONS = 'gen_ai.response.finish_reasons'

    # Usage attributes (v1.28.0 standard)
    USAGE_INPUT_TOKENS = 'gen_ai.usage.input_tokens'
    USAGE_OUTPUT_TOKENS = 'gen_ai.usage.output_tokens'
    USAGE_TOTAL_TOKENS = 'gen_ai.usage.total_tokens'

    # Cost tracking (Last9 custom)
    USAGE_COST_USD = 'gen_ai.usage.cost_usd'
    USAGE_COST_INPUT_USD = 'gen_ai.usage.cost_input_usd'
    USAGE_COST_OUTPUT_USD = 'gen_ai.usage.cost_output_usd'

    # Prompt attributes
    PROMPT = 'gen_ai.prompt'
    COMPLETION = 'gen_ai.completion'

    # Prompt versioning (Last9 custom)
    PROMPT_TEMPLATE = 'gen_ai.prompt.template'
    PROMPT_VERSION = 'gen_ai.prompt.version'
    PROMPT_HASH = 'gen_ai.prompt.hash'
    PROMPT_TEMPLATE_ID = 'gen_ai.prompt.template_id'

    # Tool attributes
    TOOL_NAME = 'gen_ai.tool.name'
    TOOL_TYPE = 'gen_ai.tool.type'
    TOOL_DESCRIPTION = 'gen_ai.tool.description'

class Last9Attributes:
    """Last9-specific extensions to OpenTelemetry GenAI conventions"""

    # Span classification
    L9_SPAN_KIND = 'gen_ai.l9.span.kind'

    # Workflow attributes
    WORKFLOW_ID = 'workflow.id'
    WORKFLOW_TYPE = 'workflow.type'
    WORKFLOW_USER_ID = 'workflow.user_id'
    WORKFLOW_SESSION_ID = 'workflow.session_id'
    WORKFLOW_TOTAL_COST_USD = 'workflow.total_cost_usd'
    WORKFLOW_LLM_CALLS = 'workflow.llm_calls'
    WORKFLOW_TOOL_CALLS = 'workflow.tool_calls'

    # Advanced AI attributes
    CAPABILITY_NAME = 'gen_ai.capability.name'
    STEP_NAME = 'gen_ai.step.name'
    AGENT_TYPE = 'gen_ai.agent.type'
    CHAIN_TYPE = 'gen_ai.chain.type'

    # Function/tool calling
    FUNCTION_CALL_NAME = 'gen_ai.function.call.name'
    FUNCTION_CALL_ARGUMENTS = 'gen_ai.function.call.arguments'
    FUNCTION_CALL_RESULT = 'gen_ai.function.call.result'
    FUNCTION_CALL_DURATION_MS = 'gen_ai.function.call.duration_ms'

    # Performance metrics
    RESPONSE_TIME_MS = 'gen_ai.response.time_ms'
    RESPONSE_SIZE_BYTES = 'gen_ai.response.size_bytes'
    REQUEST_SIZE_BYTES = 'gen_ai.request.size_bytes'
    QUALITY_SCORE = 'gen_ai.quality.score'

class SpanKinds:
    """Last9 span kind values for gen_ai.l9.span.kind"""
    LLM = 'llm'
    TOOL = 'tool'
    PROMPT = 'prompt'

class Operations:
    """Standard GenAI operation names"""
    CHAT_COMPLETIONS = 'chat.completions'
    EMBEDDINGS = 'embeddings'
    TEXT_COMPLETION = 'text.completion'
    TOOL_CALL = 'tool.call'

class Providers:
    """AI provider names"""
    ANTHROPIC = 'anthropic'
    OPENAI = 'openai'
    GOOGLE = 'google'
    COHERE = 'cohere'
    HUGGINGFACE = 'huggingface'

class EventNames:
    """Event names for span events (matches Node.js agent)"""
    GEN_AI_CONTENT_PROMPT = 'gen_ai.content.prompt'
    GEN_AI_CONTENT_COMPLETION = 'gen_ai.content.completion'
    GEN_AI_TOOL_CALL = 'gen_ai.tool.call'
    GEN_AI_TOOL_RESULT = 'gen_ai.tool.result'
    GEN_AI_PROMPT_VERSION = 'gen_ai.prompt.version'

# ============================================================================
# Model Pricing Configuration
# Based on last9-node-agent/src/config/defaults.js
# ============================================================================

@dataclass
class ModelPricing:
    """Pricing structure for AI models (USD per million tokens)"""
    input: float
    output: float

# Default model pricing (USD per million tokens)
# Based on last9-node-agent/src/config/defaults.js
MODEL_PRICING = {
    # Anthropic Models - Claude 4.5 Series
    'claude-sonnet-4-5-20250929': ModelPricing(input=3.0, output=15.0),
    'claude-haiku-4-5-20251001': ModelPricing(input=0.25, output=1.25),

    # Anthropic Models - Claude 3.x Series
    'claude-3-5-sonnet': ModelPricing(input=3.0, output=15.0),
    'claude-3-5-sonnet-20241022': ModelPricing(input=3.0, output=15.0),
    'claude-3-5-sonnet-20240620': ModelPricing(input=3.0, output=15.0),
    'claude-3-opus': ModelPricing(input=15.0, output=75.0),
    'claude-3-haiku': ModelPricing(input=0.25, output=1.25),
    'claude-3-haiku-20240307': ModelPricing(input=0.25, output=1.25),

    # OpenAI Models
    'gpt-4o': ModelPricing(input=2.50, output=10.0),
    'gpt-4o-mini': ModelPricing(input=0.15, output=0.60),
    'gpt-4': ModelPricing(input=30.0, output=60.0),
    'gpt-4-turbo': ModelPricing(input=10.0, output=30.0),
    'gpt-3.5-turbo': ModelPricing(input=0.50, output=1.50),
    'gpt-3.5-turbo-instruct': ModelPricing(input=1.50, output=2.0),

    # Google Models
    'gemini-pro': ModelPricing(input=0.50, output=1.50),
    'gemini-1.5-pro': ModelPricing(input=3.50, output=10.50),
    'gemini-1.5-flash': ModelPricing(input=0.075, output=0.30),

    # Cohere Models
    'command-r': ModelPricing(input=0.50, output=1.50),
    'command-r-plus': ModelPricing(input=3.0, output=15.0),

    # Default fallback pricing
    'default': ModelPricing(input=1.0, output=3.0)
}

# ============================================================================
# Cost Calculation Utilities
# Based on last9-node-agent/src/costing/token-calculator.js
# ============================================================================

@dataclass
class CostBreakdown:
    """Cost breakdown for LLM operations"""
    input: float = 0.0
    output: float = 0.0
    total: float = 0.0

def calculate_llm_cost(
    model: str,
    usage: Dict[str, int],
    custom_pricing: Optional[Dict[str, ModelPricing]] = None
) -> CostBreakdown:
    """
    Calculate cost for LLM operation based on token usage

    Args:
        model: Model name
        usage: Token usage dict with keys like 'input_tokens', 'output_tokens',
               'prompt_tokens', 'completion_tokens'
        custom_pricing: Optional custom pricing override

    Returns:
        CostBreakdown with input, output, and total costs in USD
    """
    pricing_table = custom_pricing or MODEL_PRICING

    # Get model pricing, fallback to default
    pricing = pricing_table.get(model, MODEL_PRICING['default'])

    # Extract token counts (handle both old and new naming conventions)
    input_tokens = usage.get('input_tokens', usage.get('prompt_tokens', 0))
    output_tokens = usage.get('output_tokens', usage.get('completion_tokens', 0))

    if input_tokens == 0 and output_tokens == 0:
        return CostBreakdown()

    # Calculate costs (pricing is per million tokens)
    input_cost = (input_tokens / 1_000_000) * pricing.input
    output_cost = (output_tokens / 1_000_000) * pricing.output
    total_cost = input_cost + output_cost

    return CostBreakdown(
        input=round(input_cost, 6),
        output=round(output_cost, 6),
        total=round(total_cost, 6)
    )

def detect_ai_provider(model: str) -> Optional[str]:
    """
    Detect AI provider from model name
    Based on last9-node-agent/src/spans/llm.js:detectAISystem
    """
    if not model:
        return None

    model_lower = model.lower()

    if 'claude' in model_lower:
        return Providers.ANTHROPIC
    elif 'gpt' in model_lower:
        return Providers.OPENAI
    elif 'gemini' in model_lower:
        return Providers.GOOGLE
    elif 'command' in model_lower:
        return Providers.COHERE

    return None

def estimate_tokens(text: str) -> int:
    """
    Rough estimation of token count from text
    Based on ~4 characters per token average
    """
    return len(text) // 4

# ============================================================================
# Workflow Cost Tracking
# Based on last9-node-agent/src/costing/workflow-costs.js
# ============================================================================

@dataclass
class WorkflowCost:
    """Workflow cost tracking"""
    workflow_id: str
    metadata: Dict[str, Any] = field(default_factory=dict)
    costs: List[Dict[str, Any]] = field(default_factory=list)
    total_cost: float = 0.0
    llm_calls: int = 0
    tool_calls: int = 0
    created_at: datetime = field(default_factory=datetime.now)

class WorkflowCostTracker:
    """
    Track costs across workflow operations
    Based on last9-node-agent/src/costing/workflow-costs.js
    """

    def __init__(self):
        self._workflows: Dict[str, WorkflowCost] = {}

    def initialize_workflow(self, workflow_id: str, metadata: Optional[Dict[str, Any]] = None) -> None:
        """Initialize a new workflow for cost tracking"""
        if workflow_id not in self._workflows:
            self._workflows[workflow_id] = WorkflowCost(
                workflow_id=workflow_id,
                metadata=metadata or {}
            )

    def add_cost(self, workflow_id: str, cost: CostBreakdown, operation_type: str = 'llm') -> None:
        """Add cost to workflow"""
        if workflow_id not in self._workflows:
            self.initialize_workflow(workflow_id)

        workflow = self._workflows[workflow_id]
        workflow.costs.append({
            'cost': cost,
            'operation_type': operation_type,
            'timestamp': datetime.now()
        })
        workflow.total_cost += cost.total

        if operation_type == 'llm':
            workflow.llm_calls += 1
        elif operation_type == 'tool':
            workflow.tool_calls += 1

    def get_workflow_cost(self, workflow_id: str) -> Optional[WorkflowCost]:
        """Get workflow cost summary"""
        return self._workflows.get(workflow_id)

    def get_all_workflows(self) -> Dict[str, WorkflowCost]:
        """Get all workflow cost summaries"""
        return self._workflows.copy()

    def delete_workflow(self, workflow_id: str) -> bool:
        """Delete workflow from tracking"""
        if workflow_id in self._workflows:
            del self._workflows[workflow_id]
            return True
        return False

# Global workflow tracker instance
global_workflow_tracker = WorkflowCostTracker()

# ============================================================================
# Main Last9 GenAI Utility Class
# ============================================================================

class Last9GenAI:
    """
    Last9 GenAI attributes utility for Python OpenTelemetry users

    This class provides methods to add Last9-specific gen_ai attributes
    to existing OpenTelemetry spans, complementing the standard gen_ai
    semantic conventions with cost tracking, workflow management, and
    enhanced observability features.
    """

    def __init__(self,
                 custom_pricing: Optional[Dict[str, ModelPricing]] = None,
                 workflow_tracker: Optional[WorkflowCostTracker] = None):
        """
        Initialize Last9 GenAI utility

        Args:
            custom_pricing: Custom model pricing configuration
            workflow_tracker: Custom workflow cost tracker instance
        """
        self.model_pricing = custom_pricing or MODEL_PRICING
        self.workflow_tracker = workflow_tracker or global_workflow_tracker
        self.logger = logging.getLogger(__name__)

    def set_span_kind(self, span: Span, kind: str) -> None:
        """
        Set Last9 span kind classification

        Args:
            span: OpenTelemetry span
            kind: Span kind ('llm', 'tool', 'prompt')
        """
        if kind in [SpanKinds.LLM, SpanKinds.TOOL, SpanKinds.PROMPT]:
            span.set_attribute(Last9Attributes.L9_SPAN_KIND, kind)
        else:
            self.logger.warning(f"Unknown span kind: {kind}")

    def add_llm_cost_attributes(self,
                              span: Span,
                              model: str,
                              usage: Dict[str, int],
                              workflow_id: Optional[str] = None) -> CostBreakdown:
        """
        Add LLM cost tracking attributes to span

        Args:
            span: OpenTelemetry span
            model: Model name
            usage: Token usage dictionary
            workflow_id: Optional workflow ID for cost aggregation

        Returns:
            CostBreakdown with calculated costs
        """
        cost = calculate_llm_cost(model, usage, self.model_pricing)

        if cost.total > 0:
            span.set_attribute(GenAIAttributes.USAGE_COST_USD, cost.total)
            span.set_attribute(GenAIAttributes.USAGE_COST_INPUT_USD, cost.input)
            span.set_attribute(GenAIAttributes.USAGE_COST_OUTPUT_USD, cost.output)

            # Add to workflow cost tracking if workflow_id provided
            if workflow_id:
                self.workflow_tracker.add_cost(workflow_id, cost, 'llm')

        return cost

    def add_workflow_attributes(self,
                              span: Span,
                              workflow_id: str,
                              workflow_type: Optional[str] = None,
                              user_id: Optional[str] = None,
                              session_id: Optional[str] = None) -> None:
        """
        Add workflow-level attributes to span

        Args:
            span: OpenTelemetry span
            workflow_id: Unique workflow identifier
            workflow_type: Type of workflow
            user_id: User identifier
            session_id: Session identifier
        """
        span.set_attribute(Last9Attributes.WORKFLOW_ID, workflow_id)

        if workflow_type:
            span.set_attribute(Last9Attributes.WORKFLOW_TYPE, workflow_type)
        if user_id:
            span.set_attribute(Last9Attributes.WORKFLOW_USER_ID, user_id)
        if session_id:
            span.set_attribute(Last9Attributes.WORKFLOW_SESSION_ID, session_id)

        # Initialize workflow tracking
        self.workflow_tracker.initialize_workflow(workflow_id)

        # Add aggregated cost if available
        workflow_cost = self.workflow_tracker.get_workflow_cost(workflow_id)
        if workflow_cost:
            span.set_attribute(Last9Attributes.WORKFLOW_TOTAL_COST_USD, workflow_cost.total_cost)
            span.set_attribute(Last9Attributes.WORKFLOW_LLM_CALLS, workflow_cost.llm_calls)
            span.set_attribute(Last9Attributes.WORKFLOW_TOOL_CALLS, workflow_cost.tool_calls)

    def add_prompt_versioning(self,
                            span: Span,
                            prompt_template: str,
                            template_id: Optional[str] = None,
                            version: Optional[str] = None) -> str:
        """
        Add prompt versioning attributes

        Args:
            span: OpenTelemetry span
            prompt_template: Prompt template content
            template_id: Template identifier
            version: Template version

        Returns:
            Generated hash of the prompt template
        """
        # Generate hash of template content
        prompt_hash = hashlib.sha256(prompt_template.encode()).hexdigest()[:16]

        span.set_attribute(GenAIAttributes.PROMPT_TEMPLATE, prompt_template)
        span.set_attribute(GenAIAttributes.PROMPT_HASH, prompt_hash)

        if template_id:
            span.set_attribute(GenAIAttributes.PROMPT_TEMPLATE_ID, template_id)
        if version:
            span.set_attribute(GenAIAttributes.PROMPT_VERSION, version)

        return prompt_hash

    def add_tool_attributes(self,
                          span: Span,
                          tool_name: str,
                          tool_type: Optional[str] = None,
                          description: Optional[str] = None,
                          arguments: Optional[Dict[str, Any]] = None,
                          result: Optional[Any] = None,
                          duration_ms: Optional[float] = None,
                          workflow_id: Optional[str] = None) -> None:
        """
        Add tool/function call attributes

        Args:
            span: OpenTelemetry span
            tool_name: Name of the tool/function
            tool_type: Type of tool (e.g., 'datastore', 'api')
            description: Tool description
            arguments: Tool call arguments
            result: Tool execution result
            duration_ms: Execution duration in milliseconds
            workflow_id: Optional workflow ID for tracking
        """
        span.set_attribute(GenAIAttributes.TOOL_NAME, tool_name)
        self.set_span_kind(span, SpanKinds.TOOL)

        if tool_type:
            span.set_attribute(GenAIAttributes.TOOL_TYPE, tool_type)
        if description:
            span.set_attribute(GenAIAttributes.TOOL_DESCRIPTION, description)
        if arguments:
            span.set_attribute(Last9Attributes.FUNCTION_CALL_ARGUMENTS, json.dumps(arguments))
        if result:
            span.set_attribute(Last9Attributes.FUNCTION_CALL_RESULT, str(result))
        if duration_ms:
            span.set_attribute(Last9Attributes.FUNCTION_CALL_DURATION_MS, duration_ms)

        # Track tool cost in workflow (tools typically have no direct cost)
        if workflow_id:
            self.workflow_tracker.add_cost(workflow_id, CostBreakdown(), 'tool')

    def add_performance_attributes(self,
                                 span: Span,
                                 response_time_ms: Optional[float] = None,
                                 request_size_bytes: Optional[int] = None,
                                 response_size_bytes: Optional[int] = None,
                                 quality_score: Optional[float] = None) -> None:
        """
        Add performance and quality metrics

        Args:
            span: OpenTelemetry span
            response_time_ms: Response time in milliseconds
            request_size_bytes: Request size in bytes
            response_size_bytes: Response size in bytes
            quality_score: Quality score (0.0-1.0)
        """
        if response_time_ms is not None:
            span.set_attribute(Last9Attributes.RESPONSE_TIME_MS, response_time_ms)
        if request_size_bytes is not None:
            span.set_attribute(Last9Attributes.REQUEST_SIZE_BYTES, request_size_bytes)
        if response_size_bytes is not None:
            span.set_attribute(Last9Attributes.RESPONSE_SIZE_BYTES, response_size_bytes)
        if quality_score is not None:
            span.set_attribute(Last9Attributes.QUALITY_SCORE, quality_score)

    def add_standard_llm_attributes(self,
                                  span: Span,
                                  model: str,
                                  operation: str = Operations.CHAT_COMPLETIONS,
                                  conversation_id: Optional[str] = None,
                                  request_params: Optional[Dict[str, Any]] = None,
                                  response_data: Optional[Dict[str, Any]] = None,
                                  usage: Optional[Dict[str, int]] = None) -> None:
        """
        Add standard OpenTelemetry GenAI attributes

        Args:
            span: OpenTelemetry span
            model: Model name
            operation: Operation type
            conversation_id: Conversation/session ID
            request_params: Request parameters (max_tokens, temperature, etc.)
            response_data: Response metadata (id, finish_reason, etc.)
            usage: Token usage data
        """
        # Set basic attributes
        span.set_attribute(GenAIAttributes.REQUEST_MODEL, model)
        span.set_attribute(GenAIAttributes.OPERATION_NAME, operation)

        # Set provider based on model
        provider = detect_ai_provider(model)
        if provider:
            span.set_attribute(GenAIAttributes.PROVIDER_NAME, provider)

        if conversation_id:
            span.set_attribute(GenAIAttributes.CONVERSATION_ID, conversation_id)

        # Set request parameters
        if request_params:
            if 'max_tokens' in request_params:
                span.set_attribute(GenAIAttributes.REQUEST_MAX_TOKENS, request_params['max_tokens'])
            if 'temperature' in request_params:
                span.set_attribute(GenAIAttributes.REQUEST_TEMPERATURE, request_params['temperature'])
            if 'top_p' in request_params:
                span.set_attribute(GenAIAttributes.REQUEST_TOP_P, request_params['top_p'])
            if 'frequency_penalty' in request_params:
                span.set_attribute(GenAIAttributes.REQUEST_FREQUENCY_PENALTY, request_params['frequency_penalty'])
            if 'presence_penalty' in request_params:
                span.set_attribute(GenAIAttributes.REQUEST_PRESENCE_PENALTY, request_params['presence_penalty'])

        # Set response data
        if response_data:
            if 'id' in response_data:
                span.set_attribute(GenAIAttributes.RESPONSE_ID, response_data['id'])
            if 'model' in response_data:
                span.set_attribute(GenAIAttributes.RESPONSE_MODEL, response_data['model'])
            if 'finish_reason' in response_data:
                span.set_attribute(GenAIAttributes.RESPONSE_FINISH_REASONS, [response_data['finish_reason']])

        # Set usage attributes
        if usage:
            input_tokens = usage.get('input_tokens', usage.get('prompt_tokens', 0))
            output_tokens = usage.get('output_tokens', usage.get('completion_tokens', 0))
            total_tokens = usage.get('total_tokens', input_tokens + output_tokens)

            if input_tokens > 0:
                span.set_attribute(GenAIAttributes.USAGE_INPUT_TOKENS, input_tokens)
            if output_tokens > 0:
                span.set_attribute(GenAIAttributes.USAGE_OUTPUT_TOKENS, output_tokens)
            if total_tokens > 0:
                span.set_attribute(GenAIAttributes.USAGE_TOTAL_TOKENS, total_tokens)

    def add_conversation_tracking(self,
                                span: Span,
                                conversation_id: str,
                                user_id: Optional[str] = None,
                                session_id: Optional[str] = None,
                                turn_number: Optional[int] = None) -> None:
        """
        Add conversation tracking attributes to span

        Args:
            span: OpenTelemetry span
            conversation_id: Unique conversation identifier
            user_id: User identifier
            session_id: Session identifier
            turn_number: Turn number in the conversation
        """
        span.set_attribute(GenAIAttributes.CONVERSATION_ID, conversation_id)

        if user_id:
            span.set_attribute(Last9Attributes.WORKFLOW_USER_ID, user_id)
        if session_id:
            span.set_attribute(Last9Attributes.WORKFLOW_SESSION_ID, session_id)
        if turn_number is not None:
            span.set_attribute('gen_ai.conversation.turn_number', turn_number)

    def add_content_events(self,
                          span: Span,
                          prompt: Optional[str] = None,
                          completion: Optional[str] = None,
                          truncate_length: int = 1000) -> None:
        """
        Add content events for input/output prompts (matches Node.js agent functionality)

        Args:
            span: OpenTelemetry span
            prompt: User prompt/input text
            completion: LLM completion/response text
            truncate_length: Maximum length before truncation (default: 1000)
        """
        if prompt:
            truncated_prompt = (
                prompt[:truncate_length] + '...'
                if len(prompt) > truncate_length
                else prompt
            )

            # Add prompt content as span event
            span.add_event(EventNames.GEN_AI_CONTENT_PROMPT, {
                GenAIAttributes.PROMPT: truncated_prompt,
                'gen_ai.prompt.length': len(prompt),
                'gen_ai.prompt.truncated': len(prompt) > truncate_length
            })

        if completion:
            truncated_completion = (
                completion[:truncate_length] + '...'
                if len(completion) > truncate_length
                else completion
            )

            # Add completion content as span event
            span.add_event(EventNames.GEN_AI_CONTENT_COMPLETION, {
                GenAIAttributes.COMPLETION: truncated_completion,
                'gen_ai.completion.length': len(completion),
                'gen_ai.completion.truncated': len(completion) > truncate_length
            })

    def add_tool_call_events(self,
                           span: Span,
                           tool_name: str,
                           tool_arguments: Optional[Dict[str, Any]] = None,
                           tool_result: Optional[Any] = None) -> None:
        """
        Add tool call and result events to span

        Args:
            span: OpenTelemetry span
            tool_name: Name of the tool being called
            tool_arguments: Tool call arguments
            tool_result: Tool execution result
        """
        if tool_arguments:
            span.add_event(EventNames.GEN_AI_TOOL_CALL, {
                GenAIAttributes.TOOL_NAME: tool_name,
                Last9Attributes.FUNCTION_CALL_ARGUMENTS: json.dumps(tool_arguments) if tool_arguments else None
            })

        if tool_result:
            span.add_event(EventNames.GEN_AI_TOOL_RESULT, {
                GenAIAttributes.TOOL_NAME: tool_name,
                Last9Attributes.FUNCTION_CALL_RESULT: str(tool_result)
            })

    def create_conversation_span(self,
                               tracer,
                               conversation_id: str,
                               model: str,
                               user_id: Optional[str] = None,
                               turn_number: Optional[int] = None) -> Span:
        """
        Create a conversation-aware LLM span with tracking

        Args:
            tracer: OpenTelemetry tracer
            conversation_id: Unique conversation identifier
            model: Model name
            user_id: User identifier
            turn_number: Turn number in conversation

        Returns:
            Configured span with conversation tracking
        """
        span = tracer.start_span("gen_ai.chat.completions")

        # Add standard LLM attributes
        self.add_standard_llm_attributes(
            span, model,
            conversation_id=conversation_id
        )

        # Add Last9 attributes
        self.set_span_kind(span, SpanKinds.LLM)

        # Add conversation tracking
        self.add_conversation_tracking(
            span, conversation_id, user_id=user_id, turn_number=turn_number
        )

        return span

# ============================================================================
# Conversation Management Utilities
# ============================================================================

@dataclass
class ConversationTurn:
    """Represents a single turn in a conversation"""
    turn_number: int
    user_message: str
    assistant_message: str
    model: str
    usage: Dict[str, int]
    cost: CostBreakdown
    timestamp: datetime = field(default_factory=datetime.now)

class ConversationTracker:
    """
    Track multi-turn conversations with cost aggregation
    Similar to workflow tracking but specifically for conversations
    """

    def __init__(self):
        self._conversations: Dict[str, List[ConversationTurn]] = {}
        self._conversation_metadata: Dict[str, Dict[str, Any]] = {}

    def start_conversation(self,
                         conversation_id: str,
                         user_id: Optional[str] = None,
                         metadata: Optional[Dict[str, Any]] = None) -> None:
        """Start tracking a new conversation"""
        if conversation_id not in self._conversations:
            self._conversations[conversation_id] = []
            self._conversation_metadata[conversation_id] = {
                'user_id': user_id,
                'started_at': datetime.now(),
                **(metadata or {})
            }

    def add_turn(self,
                conversation_id: str,
                user_message: str,
                assistant_message: str,
                model: str,
                usage: Dict[str, int],
                cost: CostBreakdown) -> int:
        """Add a turn to the conversation"""
        if conversation_id not in self._conversations:
            self.start_conversation(conversation_id)

        turn_number = len(self._conversations[conversation_id]) + 1
        turn = ConversationTurn(
            turn_number=turn_number,
            user_message=user_message,
            assistant_message=assistant_message,
            model=model,
            usage=usage,
            cost=cost
        )

        self._conversations[conversation_id].append(turn)
        return turn_number

    def get_conversation(self, conversation_id: str) -> Optional[List[ConversationTurn]]:
        """Get conversation history"""
        return self._conversations.get(conversation_id)

    def get_conversation_cost(self, conversation_id: str) -> float:
        """Get total cost for a conversation"""
        turns = self._conversations.get(conversation_id, [])
        return sum(turn.cost.total for turn in turns)

    def get_conversation_stats(self, conversation_id: str) -> Optional[Dict[str, Any]]:
        """Get conversation statistics"""
        turns = self._conversations.get(conversation_id)
        if not turns:
            return None

        total_cost = sum(turn.cost.total for turn in turns)
        total_input_tokens = sum(turn.usage.get('input_tokens', 0) for turn in turns)
        total_output_tokens = sum(turn.usage.get('output_tokens', 0) for turn in turns)

        return {
            'conversation_id': conversation_id,
            'turn_count': len(turns),
            'total_cost': total_cost,
            'total_input_tokens': total_input_tokens,
            'total_output_tokens': total_output_tokens,
            'models_used': list(set(turn.model for turn in turns)),
            'started_at': self._conversation_metadata.get(conversation_id, {}).get('started_at'),
            'user_id': self._conversation_metadata.get(conversation_id, {}).get('user_id')
        }

# Global conversation tracker instance
global_conversation_tracker = ConversationTracker()

# ============================================================================
# Convenience Functions for Common Use Cases
# ============================================================================

def create_llm_span(tracer,
                   span_name: str,
                   model: str,
                   operation: str = Operations.CHAT_COMPLETIONS,
                   workflow_id: Optional[str] = None,
                   conversation_id: Optional[str] = None,
                   l9_genai: Optional[Last9GenAI] = None) -> Span:
    """
    Create an LLM span with standard Last9 attributes

    Args:
        tracer: OpenTelemetry tracer
        span_name: Name of the span
        model: Model name
        operation: Operation type
        workflow_id: Workflow ID
        conversation_id: Conversation ID
        l9_genai: Last9GenAI instance (creates default if not provided)

    Returns:
        Configured span with Last9 attributes
    """
    if l9_genai is None:
        l9_genai = Last9GenAI()

    span = tracer.start_span(f"gen_ai.{operation}")

    # Add standard attributes
    l9_genai.add_standard_llm_attributes(
        span, model, operation, conversation_id
    )

    # Add Last9 attributes
    l9_genai.set_span_kind(span, SpanKinds.LLM)

    if workflow_id:
        l9_genai.add_workflow_attributes(span, workflow_id)

    return span

def create_tool_span(tracer,
                    tool_name: str,
                    tool_type: Optional[str] = None,
                    workflow_id: Optional[str] = None,
                    l9_genai: Optional[Last9GenAI] = None) -> Span:
    """
    Create a tool/function call span with Last9 attributes

    Args:
        tracer: OpenTelemetry tracer
        tool_name: Name of the tool
        tool_type: Type of tool
        workflow_id: Workflow ID
        l9_genai: Last9GenAI instance

    Returns:
        Configured span for tool usage
    """
    if l9_genai is None:
        l9_genai = Last9GenAI()

    span = tracer.start_span(f"gen_ai.tool.{tool_name}")

    l9_genai.add_tool_attributes(
        span, tool_name, tool_type=tool_type, workflow_id=workflow_id
    )

    return span

# ============================================================================
# Example Usage and Testing
# ============================================================================

def example_usage():
    """Example usage of Last9 GenAI attributes"""

    # Initialize OpenTelemetry tracer (you'll already have this in your app)
    tracer = trace.get_tracer(__name__)

    # Initialize Last9 GenAI utility
    l9_genai = Last9GenAI()

    # Example 1: LLM call with cost tracking
    with tracer.start_span("gen_ai.chat.completions") as span:
        model = "claude-3-5-sonnet"
        usage = {"input_tokens": 150, "output_tokens": 250}

        # Add standard OpenTelemetry GenAI attributes
        l9_genai.add_standard_llm_attributes(
            span, model,
            conversation_id="session_123",
            request_params={"max_tokens": 1000, "temperature": 0.7},
            usage=usage
        )

        # Add Last9-specific attributes
        l9_genai.set_span_kind(span, SpanKinds.LLM)
        cost = l9_genai.add_llm_cost_attributes(span, model, usage, "workflow_456")
        l9_genai.add_workflow_attributes(span, "workflow_456", "chat", "user_789")

        print(f"LLM call cost: ${cost.total:.6f}")

    # Example 2: Tool call
    with tracer.start_span("gen_ai.tool.database_query") as span:
        l9_genai.add_tool_attributes(
            span, "database_query",
            tool_type="datastore",
            description="Query user preferences",
            arguments={"table": "users", "user_id": 123},
            result="Found 1 record",
            duration_ms=45.2,
            workflow_id="workflow_456"
        )

    # Example 3: Prompt versioning
    with tracer.start_span("gen_ai.prompt.template") as span:
        prompt_template = "You are a helpful AI assistant. User question: {question}"
        l9_genai.set_span_kind(span, SpanKinds.PROMPT)
        prompt_hash = l9_genai.add_prompt_versioning(
            span, prompt_template,
            template_id="assistant_v1",
            version="1.2.3"
        )
        print(f"Prompt hash: {prompt_hash}")

    # View workflow cost summary
    workflow = l9_genai.workflow_tracker.get_workflow_cost("workflow_456")
    if workflow:
        print(f"Workflow total cost: ${workflow.total_cost:.6f}")
        print(f"LLM calls: {workflow.llm_calls}, Tool calls: {workflow.tool_calls}")

if __name__ == "__main__":
    # Run example usage
    print("Last9 GenAI Attributes for Python - Example Usage")
    print("=" * 50)
    example_usage()