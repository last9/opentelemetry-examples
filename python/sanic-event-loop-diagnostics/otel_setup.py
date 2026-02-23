"""
OpenTelemetry setup module for event loop diagnostics.

Configures both tracing and metrics providers with OTLP exporters.
This module combines:
1. Standard OTEL tracing (TracerProvider)
2. OTEL metrics for custom event loop instrumentation (MeterProvider)
3. Resource detection for service, process, OS, and Kubernetes attributes
4. Optional: Standard asyncio instrumentation from OTEL contrib
"""

import os
from typing import Optional, Dict, List

from opentelemetry import trace, metrics
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.trace.sampling import (
    ParentBased,
    ALWAYS_ON,
    ALWAYS_OFF,
    TraceIdRatioBased
)
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.sdk.resources import (
    Resource,
    SERVICE_NAME,
    get_aggregated_resources,
    OTELResourceDetector,
    ProcessResourceDetector,
)
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter

# OpenTelemetry Semantic Convention keys
# https://opentelemetry.io/docs/specs/semconv/resource/
SERVICE_VERSION = "service.version"
SERVICE_NAMESPACE = "service.namespace"
DEPLOYMENT_ENVIRONMENT = "deployment.environment"

# Try to import optional resource detectors
# These provide automatic detection of runtime environment
try:
    from opentelemetry.sdk.resources import OsResourceDetector
    HAS_OS_DETECTOR = True
except ImportError:
    HAS_OS_DETECTOR = False

# Host detector (provides host.name, host.arch)
# Note: This is a private API but widely used
try:
    from opentelemetry.sdk.resources import _HostResourceDetector
    HAS_HOST_DETECTOR = True
except ImportError:
    HAS_HOST_DETECTOR = False

# AWS resource detectors (optional package)
# Install with: pip install opentelemetry-sdk-extension-aws
# Provides: EC2, ECS, EKS, Lambda, Beanstalk detection
try:
    from opentelemetry.sdk.extension.aws.resource.ec2 import AwsEc2ResourceDetector
    HAS_AWS_EC2_DETECTOR = True
except ImportError:
    HAS_AWS_EC2_DETECTOR = False

try:
    from opentelemetry.sdk.extension.aws.resource.ecs import AwsEcsResourceDetector
    HAS_AWS_ECS_DETECTOR = True
except ImportError:
    HAS_AWS_ECS_DETECTOR = False

try:
    from opentelemetry.sdk.extension.aws.resource.eks import AwsEksResourceDetector
    HAS_AWS_EKS_DETECTOR = True
except ImportError:
    HAS_AWS_EKS_DETECTOR = False

try:
    from opentelemetry.sdk.extension.aws.resource._lambda import AwsLambdaResourceDetector
    HAS_AWS_LAMBDA_DETECTOR = True
except ImportError:
    HAS_AWS_LAMBDA_DETECTOR = False

# GCP resource detector (optional package)
# Install with: pip install opentelemetry-resourcedetector-gcp
# Provides: GCE, GKE, Cloud Run, Cloud Functions detection
try:
    from opentelemetry.resourcedetector.gcp_resource_detector import GoogleCloudResourceDetector
    HAS_GCP_DETECTOR = True
except ImportError:
    HAS_GCP_DETECTOR = False

# Kubernetes resource detector (optional package)
# Install with: pip install opentelemetry-resourcedetector-kubernetes
try:
    from opentelemetry_resourcedetector_kubernetes import (
        KubernetesResourceDetector,
        KubernetesDownwardAPIEnvironmentResourceDetector,
    )
    HAS_K8S_DETECTOR = True
except ImportError:
    HAS_K8S_DETECTOR = False

# Semantic conventions for K8s attributes
try:
    from opentelemetry.semconv.resource import ResourceAttributes
    HAS_SEMCONV = True
except ImportError:
    HAS_SEMCONV = False

# Docker/Container resource detector (optional package)
# Install with: pip install opentelemetry-resourcedetector-docker-cgroup
try:
    from opentelemetry_resourcedetector_docker_cgroup import DockerCGroupResourceDetector
    HAS_DOCKER_DETECTOR = True
except ImportError:
    HAS_DOCKER_DETECTOR = False

# Optional: Import standard asyncio instrumentation if available
try:
    from opentelemetry.instrumentation.asyncio import AsyncioInstrumentor
    HAS_ASYNCIO_INSTRUMENTOR = True
except ImportError:
    HAS_ASYNCIO_INSTRUMENTOR = False


def parse_resource_attributes() -> Dict[str, str]:
    """Parse OTEL_RESOURCE_ATTRIBUTES environment variable."""
    resource_attrs = os.getenv("OTEL_RESOURCE_ATTRIBUTES", "")
    attrs = {}

    if resource_attrs:
        for attr in resource_attrs.split(","):
            if "=" in attr:
                key, value = attr.split("=", 1)
                attrs[key.strip()] = value.strip()

    return attrs


def get_kubernetes_env_attributes() -> Dict[str, str]:
    """
    Get Kubernetes attributes from environment variables.

    This is a fallback for when we're not actually running in Kubernetes
    (e.g., local development, Docker outside K8s) but want to set K8s
    attributes for testing or consistency.

    The KubernetesDownwardAPIEnvironmentResourceDetector only works when
    actually running in K8s (it checks /proc/self/cgroup). This function
    provides a way to manually set K8s attributes via environment variables.

    Environment variables (using OTEL_RD_ prefix to match K8s detector):
        OTEL_RD_K8S_POD_NAME -> k8s.pod.name
        OTEL_RD_K8S_POD_UID -> k8s.pod.uid
        OTEL_RD_K8S_NAMESPACE_NAME -> k8s.namespace.name
        OTEL_RD_K8S_CONTAINER_NAME -> k8s.container.name
        OTEL_RD_K8S_DEPLOYMENT_NAME -> k8s.deployment.name
        OTEL_RD_K8S_NODE_NAME -> k8s.node.name
        OTEL_RD_K8S_CLUSTER_NAME -> k8s.cluster.name
        OTEL_RD_CONTAINER_ID -> container.id
        OTEL_RD_CONTAINER_NAME -> container.name
    """
    attrs = {}

    # Map of env var suffix -> semantic convention attribute name
    # These match the ResourceAttributes constants
    env_to_attr = {
        "K8S_POD_NAME": "k8s.pod.name",
        "K8S_POD_UID": "k8s.pod.uid",
        "K8S_NAMESPACE_NAME": "k8s.namespace.name",
        "K8S_CONTAINER_NAME": "k8s.container.name",
        "K8S_DEPLOYMENT_NAME": "k8s.deployment.name",
        "K8S_NODE_NAME": "k8s.node.name",
        "K8S_CLUSTER_NAME": "k8s.cluster.name",
        "K8S_REPLICASET_NAME": "k8s.replicaset.name",
        "CONTAINER_ID": "container.id",
        "CONTAINER_NAME": "container.name",
        "CONTAINER_IMAGE_NAME": "container.image.name",
        "CONTAINER_IMAGE_TAG": "container.image.tag",
    }

    prefix = "OTEL_RD_"

    for env_suffix, attr_name in env_to_attr.items():
        value = os.getenv(f"{prefix}{env_suffix}")
        if value:
            attrs[attr_name] = value

    return attrs


def parse_otlp_headers() -> Dict[str, str]:
    """Parse OTEL_EXPORTER_OTLP_HEADERS environment variable."""
    headers_str = os.getenv("OTEL_EXPORTER_OTLP_HEADERS", "")
    headers = {}

    if headers_str:
        for header in headers_str.split(","):
            if "=" in header:
                key, value = header.split("=", 1)
                headers[key.strip()] = value.strip()

    return headers


def get_sampler():
    """Get sampler based on OTEL_TRACES_SAMPLER environment variable."""
    sampler_name = os.getenv("OTEL_TRACES_SAMPLER", "always_on").lower()

    if sampler_name == "always_on":
        return ParentBased(root=ALWAYS_ON)
    elif sampler_name == "always_off":
        return ParentBased(root=ALWAYS_OFF)
    elif sampler_name == "traceidratio":
        ratio = float(os.getenv("OTEL_TRACES_SAMPLER_ARG", "0.1"))
        return ParentBased(root=TraceIdRatioBased(ratio))
    else:
        return ParentBased(root=ALWAYS_ON)


def create_resource(service_name: str) -> Resource:
    """
    Create a Resource with automatic detection of environment attributes.

    Uses official OpenTelemetry resource detectors:
    - OTELResourceDetector: Reads OTEL_RESOURCE_ATTRIBUTES env var
    - ProcessResourceDetector: Captures process.pid, process.executable.name, etc.
    - OsResourceDetector: Captures os.type, os.description (if available)
    - KubernetesResourceDetector: Captures k8s.pod.uid, container.id (if available)
    - DockerCGroupResourceDetector: Captures container.id from cgroups (if available)

    Resource attributes that will be populated:
    - service.name: Your service identifier
    - service.version: From SERVICE_VERSION or APP_VERSION env var
    - deployment.environment: From DEPLOYMENT_ENVIRONMENT, ENVIRONMENT, or ENV
    - process.pid, process.executable.name, process.command_line
    - os.type, os.description
    - k8s.pod.name, k8s.pod.uid, k8s.namespace.name (in Kubernetes)
    - container.id (in containers)
    """
    # Build list of available detectors
    detectors: List = [
        OTELResourceDetector(),  # Reads OTEL_RESOURCE_ATTRIBUTES
        ProcessResourceDetector(),  # process.pid, process.executable.name, etc.
    ]

    if HAS_OS_DETECTOR:
        detectors.append(OsResourceDetector())  # os.type, os.version

    if HAS_HOST_DETECTOR:
        detectors.append(_HostResourceDetector())  # host.name, host.arch

    # Add AWS detectors (auto-detect EC2, ECS, EKS, Lambda)
    # These only return attributes when actually running in AWS
    if HAS_AWS_EC2_DETECTOR:
        detectors.append(AwsEc2ResourceDetector())
    if HAS_AWS_ECS_DETECTOR:
        detectors.append(AwsEcsResourceDetector())
    if HAS_AWS_EKS_DETECTOR:
        detectors.append(AwsEksResourceDetector())
    if HAS_AWS_LAMBDA_DETECTOR:
        detectors.append(AwsLambdaResourceDetector())

    # Add GCP detector (auto-detect GCE, GKE, Cloud Run, Cloud Functions)
    if HAS_GCP_DETECTOR:
        detectors.append(GoogleCloudResourceDetector())

    # Add Kubernetes detectors if available and running in k8s
    if HAS_K8S_DETECTOR:
        # KubernetesResourceDetector detects container.id and k8s.pod.uid from cgroups
        detectors.append(KubernetesResourceDetector())
        # Environment detector reads OTEL_RD_* prefixed env vars for k8s attributes
        # This works with Kubernetes Downward API
        detectors.append(KubernetesDownwardAPIEnvironmentResourceDetector())

    # Add Docker detector for container.id if not using k8s detector
    elif HAS_DOCKER_DETECTOR:
        detectors.append(DockerCGroupResourceDetector())

    # Get aggregated resource from all detectors
    detected_resource = get_aggregated_resources(
        detectors=detectors,
        timeout=5  # 5 second timeout for detection
    )

    # Build service attributes that we always want to set
    service_attrs = {
        SERVICE_NAME: service_name,
    }

    # Service version
    service_version = os.getenv("SERVICE_VERSION") or os.getenv("APP_VERSION")
    if service_version:
        service_attrs[SERVICE_VERSION] = service_version

    # Service namespace (logical grouping)
    service_namespace = os.getenv("SERVICE_NAMESPACE")
    if service_namespace:
        service_attrs[SERVICE_NAMESPACE] = service_namespace

    # Deployment environment - critical for Last9 filtering
    deployment_env = (
        os.getenv("DEPLOYMENT_ENVIRONMENT") or
        os.getenv("ENVIRONMENT") or
        os.getenv("ENV") or
        "development"
    )
    service_attrs[DEPLOYMENT_ENVIRONMENT] = deployment_env

    # Parse any additional attributes from OTEL_RESOURCE_ATTRIBUTES
    # (OTELResourceDetector handles this, but we also support our parsing)
    extra_attrs = parse_resource_attributes()

    # Get Kubernetes attributes from environment variables
    # This works even outside K8s (fallback for the K8s detector)
    k8s_env_attrs = get_kubernetes_env_attributes()

    # Create service resource and merge with detected resource
    # Order matters: later resources override earlier ones
    service_resource = Resource.create(service_attrs)

    # Merge: detected_resource -> service_resource -> k8s_env_attrs -> extra_attrs
    final_resource = detected_resource.merge(service_resource)
    if k8s_env_attrs:
        final_resource = final_resource.merge(Resource.create(k8s_env_attrs))
    if extra_attrs:
        final_resource = final_resource.merge(Resource.create(extra_attrs))

    return final_resource


def setup_opentelemetry(
    service_name: Optional[str] = None,
    enable_asyncio_instrumentation: bool = True,
    metric_export_interval_ms: Optional[int] = None
) -> tuple:
    """
    Initialize OpenTelemetry with both tracing and metrics.

    Args:
        service_name: Service name override (uses OTEL_SERVICE_NAME env var if not provided)
        enable_asyncio_instrumentation: Whether to enable the standard OTEL asyncio instrumentation
        metric_export_interval_ms: How often to export metrics in milliseconds.
            Override for OTEL_METRIC_EXPORT_INTERVAL_MS env var. Default: 60000 (60 seconds)

    Returns:
        Tuple of (tracer, meter) for use in the application

    Environment Variables:
        OTEL_SERVICE_NAME: Service name
        OTEL_EXPORTER_OTLP_ENDPOINT: Base OTLP endpoint (e.g., https://otlp.last9.io)
        OTEL_EXPORTER_OTLP_HEADERS: Auth headers (e.g., Authorization=Basic xxx)
        OTEL_METRIC_EXPORT_INTERVAL_MS: Metric export interval in milliseconds (default: 10000)
        DEPLOYMENT_ENVIRONMENT / ENVIRONMENT / ENV: Environment name
        SERVICE_VERSION / APP_VERSION: Service version
        SERVICE_NAMESPACE: Logical service grouping

        For Kubernetes (with opentelemetry-resourcedetector-kubernetes):
        OTEL_RD_K8S_POD_NAME: Pod name
        OTEL_RD_K8S_NAMESPACE_NAME: Namespace
        OTEL_RD_K8S_CONTAINER_NAME: Container name
        OTEL_RD_K8S_DEPLOYMENT_NAME: Deployment name
        OTEL_RD_K8S_NODE_NAME: Node name
    """
    # Get service name from arg or environment
    service_name = service_name or os.getenv("OTEL_SERVICE_NAME", "sanic-event-loop-demo")

    # Get metric export interval from arg or environment (default: 60 seconds / 1 minute)
    if metric_export_interval_ms is None:
        metric_export_interval_ms = int(os.getenv("OTEL_METRIC_EXPORT_INTERVAL_MS", "60000"))

    # Get OTLP endpoint
    endpoint = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
    traces_endpoint = os.getenv("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT", f"{endpoint}/v1/traces" if endpoint else None)
    metrics_endpoint = os.getenv("OTEL_EXPORTER_OTLP_METRICS_ENDPOINT", f"{endpoint}/v1/metrics" if endpoint else None)

    # Parse headers for authentication
    headers = parse_otlp_headers()

    # Create resource with automatic detection
    resource = create_resource(service_name)

    # Log detected resource attributes for debugging
    print(f"OpenTelemetry Configuration:")
    print(f"  Metric export interval: {metric_export_interval_ms}ms")
    print(f"  OTLP endpoint: {endpoint or 'not configured'}")
    print(f"\nOpenTelemetry Resource Attributes:")
    for key, value in sorted(resource.attributes.items()):
        print(f"  {key}: {value}")

    # ============================================
    # TRACING SETUP
    # ============================================
    sampler = get_sampler()
    tracer_provider = TracerProvider(resource=resource, sampler=sampler)

    if traces_endpoint:
        trace_exporter = OTLPSpanExporter(
            endpoint=traces_endpoint,
            headers=headers
        )
        tracer_provider.add_span_processor(BatchSpanProcessor(trace_exporter))

    trace.set_tracer_provider(tracer_provider)
    tracer = trace.get_tracer(__name__)

    # ============================================
    # METRICS SETUP
    # ============================================
    meter_provider = None

    if metrics_endpoint:
        metric_exporter = OTLPMetricExporter(
            endpoint=metrics_endpoint,
            headers=headers
        )

        # PeriodicExportingMetricReader handles the export interval
        metric_reader = PeriodicExportingMetricReader(
            exporter=metric_exporter,
            export_interval_millis=metric_export_interval_ms
        )

        meter_provider = MeterProvider(
            resource=resource,
            metric_readers=[metric_reader]
        )
        metrics.set_meter_provider(meter_provider)
    else:
        # No endpoint configured - use default provider (no-op in production)
        # This allows the code to run without OTLP configured (e.g., local dev)
        meter_provider = MeterProvider(resource=resource)
        metrics.set_meter_provider(meter_provider)

    meter = metrics.get_meter(__name__)

    # ============================================
    # OPTIONAL: STANDARD ASYNCIO INSTRUMENTATION
    # ============================================
    # This provides coroutine duration/count metrics from OTEL contrib
    # Our custom EventLoopMonitor provides the event loop health metrics
    if enable_asyncio_instrumentation and HAS_ASYNCIO_INSTRUMENTOR:
        AsyncioInstrumentor().instrument()

    return tracer, meter


def shutdown_opentelemetry():
    """Gracefully shutdown OpenTelemetry providers."""
    tracer_provider = trace.get_tracer_provider()
    if hasattr(tracer_provider, 'shutdown'):
        tracer_provider.shutdown()

    meter_provider = metrics.get_meter_provider()
    if hasattr(meter_provider, 'shutdown'):
        meter_provider.shutdown()
