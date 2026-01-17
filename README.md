# OpenTelemetry Examples

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![OpenTelemetry](https://img.shields.io/badge/OpenTelemetry-enabled-blue?logo=opentelemetry)](https://opentelemetry.io/)
[![Last9](https://img.shields.io/badge/Last9-compatible-purple)](https://last9.io)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

Production-ready examples for instrumenting applications with [OpenTelemetry](https://opentelemetry.io/) and sending telemetry data (traces, metrics, and logs) to [Last9](https://last9.io) or any OTLP-compatible observability platform.

## Why This Repository?

Getting OpenTelemetry instrumentation right can be tricky. This repository provides:

- **Copy-paste ready examples** - Each example is a complete, working application
- **Real-world patterns** - Covers HTTP servers, databases, message queues, external APIs, and more
- **Multiple languages** - Go, Python, JavaScript/Node.js, Ruby, Java, PHP, .NET, Elixir, and Kotlin
- **Cloud-native deployments** - AWS (ECS, Lambda, EC2), GCP (Cloud Run), Kubernetes
- **Collector configurations** - Ready-to-use OTel Collector configs for various use cases

## Quick Start

1. **Get your OTLP credentials** from [Last9](https://app.last9.io) (or use any OTLP-compatible backend)

2. **Set environment variables:**
   ```bash
   export OTEL_EXPORTER_OTLP_ENDPOINT="https://otlp.last9.io"
   export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <YOUR_AUTH_TOKEN>"
   ```

3. **Browse the language directories** below and follow the README in each example

## Examples by Language

### Go (`go/`)

| Framework | Description | Signals |
|-----------|-------------|---------|
| Gin | Web framework with middleware instrumentation | Traces, Metrics |
| Gin + Redis | Gin with Redis client tracing | Traces, Metrics |
| Chi | Lightweight router instrumentation | Traces, Metrics |
| Gorilla Mux | Classic router with OTel middleware | Traces |
| net/http | Standard library HTTP server | Traces |
| FastHTTP | High-performance HTTP framework | Traces |
| Beego | Full-featured web framework | Traces |
| Iris | Fast web framework | Traces |
| gRPC | gRPC server and client instrumentation | Traces |
| gRPC-Gateway | REST to gRPC gateway with tracing | Traces |
| Kafka (Sarama) | Kafka producer/consumer with Sarama | Traces |
| Kafka (Confluent) | Kafka with Confluent client | Traces |
| SQLX | SQL database instrumentation | Traces |
| PGX | PostgreSQL driver tracing | Traces |
| eBPF | eBPF-based instrumentation | Traces |

### Python (`python/`)

| Framework | Description | Signals |
|-----------|-------------|---------|
| FastAPI | Modern async API framework | Traces, Metrics |
| FastAPI + Uvicorn | Production ASGI deployment | Traces, Metrics |
| Flask | Lightweight WSGI framework | Traces |
| Django | Full-featured web framework | Traces |
| Sanic | Async web framework | Traces |
| GCP Cloud Functions | Serverless function instrumentation | Traces |

### JavaScript / Node.js (`javascript/`)

| Framework | Description | Signals |
|-----------|-------------|---------|
| Express | Classic Node.js framework (JS & TS) | Traces, Metrics |
| Fastify | Fast and low overhead framework | Traces |
| NestJS | Enterprise Node.js framework | Traces |
| Next.js | React framework with SSR | Traces |
| Koa | Expressive middleware framework | Traces |
| Hono | Ultrafast web framework | Traces |
| Polka | Micro web server | Traces |
| GraphQL | GraphQL server instrumentation | Traces |
| Sails | MVC framework | Traces |
| Winston | Logging library integration | Logs |
| Cloudflare Workers | Edge runtime with itty-router | Traces |

### Ruby (`ruby/`)

| Framework | Description | Signals |
|-----------|-------------|---------|
| Rails API | Modern Rails API-only app | Traces |
| Rails 5.2 | Legacy Rails support | Traces |
| Sinatra | Lightweight DSL framework | Traces |
| Roda | Routing tree framework | Traces |
| Karafka | Kafka for Ruby | Traces |
| File Logs | Log file collection | Logs |

### Java (`java/`)

| Framework | Description | Signals |
|-----------|-------------|---------|
| Spring Boot | Popular Java framework | Traces, Metrics |
| Tomcat | Servlet container | Traces |
| JBoss EAP | Enterprise application platform | Traces |

### PHP (`php/`)

| Framework | Description | Signals |
|-----------|-------------|---------|
| Laravel | Popular PHP framework | Traces |
| WordPress Plugin | WordPress instrumentation | Traces |
| Core PHP 7.3 | Vanilla PHP instrumentation | Traces |
| Core PHP 8 | Modern PHP instrumentation | Traces |

### Other Languages

| Directory | Language | Framework | Description |
|-----------|----------|-----------|-------------|
| `dotnet/` | .NET | ASP.NET Core | Web API example |
| `elixir/` | Elixir | Phoenix | Functional web framework |
| `kotlin/` | Kotlin | KMP | Real User Monitoring |

### Frontend

| Directory | Framework | Description |
|-----------|-----------|-------------|
| `react/` | React | SPA instrumentation |
| `angular/` | Angular | SPA instrumentation |

## Cloud & Infrastructure

### AWS (`aws/`)

| Example | Description |
|---------|-------------|
| ECS Fargate | Container deployment with OTel sidecar |
| Lambda (Go) | Serverless Go function |
| EC2 | Virtual machine deployment |
| RDS PostgreSQL + ECS | Database monitoring with CDK/CloudFormation |

### GCP (`gcp/`)

| Example | Description |
|---------|-------------|
| Cloud Run | Serverless containers (Go, Python, Node.js, Java) |

### OpenTelemetry Collector (`otel-collector/`)

Pre-configured collector setups for common use cases:

| Configuration | Description |
|---------------|-------------|
| Kubernetes Operator | K8s native deployment |
| OTel Operator | Auto-instrumentation for K8s |
| Fluent Bit | Log collection pipeline |
| Logstash | ELK stack integration |
| FireLens | AWS FireLens for ECS |
| Apache Server | Apache httpd metrics |
| Nginx Metrics | Nginx server metrics |
| MariaDB | Database metrics |
| Oracle | Oracle DB monitoring |
| Multiline Logs | Stack trace aggregation |
| YACE Metrics | AWS CloudWatch exporter |

### Migration Guides

| Directory | Description |
|-----------|-------------|
| `datadog-k8s-operator/` | Migrate from Datadog Agent to OpenTelemetry |

## Documentation

### Last9 Integration Guides

**Getting Started**
- [OpenTelemetry Overview](https://last9.io/docs/integrations/observability/opentelemetry/) - OTLP endpoints, credentials, and setup
- [OpenTelemetry Collector](https://last9.io/docs/integrations/observability/opentelemetry-collector/) - Collector configuration

**Go Frameworks**
- [Gin](https://last9.io/docs/integrations/frameworks/go/gin/) ・ [gRPC](https://last9.io/docs/integrations/frameworks/go/grpc/) ・ [FastHTTP](https://last9.io/docs/integrations/frameworks/go/fasthttp/) ・ [Iris](https://last9.io/docs/integrations/frameworks/go/iris/) ・ [Gorilla Mux](https://last9.io/docs/integrations/frameworks/go/gorilla-mux/)

**Python Frameworks**
- [FastAPI](https://last9.io/docs/integrations/frameworks/python/fastapi/) ・ [Flask](https://last9.io/docs/integrations/frameworks/python/flask/) ・ [Django](https://last9.io/docs/integrations/frameworks/python/django/)

**JavaScript/Node.js Frameworks**
- [Express](https://last9.io/docs/integrations/frameworks/javascript/express/) ・ [NestJS](https://last9.io/docs/integrations/frameworks/javascript/nestjs/) ・ [Next.js](https://last9.io/docs/integrations/frameworks/javascript/nextjs/) ・ [Koa](https://last9.io/docs/integrations/frameworks/javascript/koa/)

**Ruby Frameworks**
- [Rails](https://last9.io/docs/integrations/frameworks/ruby/rails/) ・ [Sinatra](https://last9.io/docs/integrations/frameworks/ruby/sinatra/) ・ [Roda](https://last9.io/docs/integrations/frameworks/ruby/roda/)

**Java Frameworks**
- [Spring Boot](https://last9.io/docs/integrations/frameworks/java/spring-boot/)

**Other Languages**
- [Elixir Phoenix](https://last9.io/docs/integrations/frameworks/elixir/phoenix/)

**Cloud & Infrastructure**
- [AWS Lambda](https://last9.io/docs/integrations/cloud-providers/aws-lambda/) ・ [AWS ECS](https://last9.io/docs/integrations/containers-and-k8s/aws-ecs/) ・ [Kubernetes](https://last9.io/docs/integrations/containers-and-k8s/kubernetes-cluster-monitoring/)

**Messaging & Databases**
- [Kafka](https://last9.io/docs/integrations/messaging/kafka/) ・ [Fluent Bit](https://last9.io/docs/integrations/observability/fluent-bit/)

### External Resources

- [Last9 Documentation](https://last9.io/docs/) - Full platform documentation
- [OpenTelemetry Official Docs](https://opentelemetry.io/docs/) - Specification and SDKs

## Works With Any OTLP Backend

While these examples are configured for [Last9](https://last9.io), they work with **any OTLP-compatible backend**:

- Grafana Cloud / Tempo / Mimir
- Honeycomb
- Jaeger
- Zipkin
- Datadog
- New Relic
- Dynatrace
- Splunk
- And many more...

Just update the `OTEL_EXPORTER_OTLP_ENDPOINT` and authentication headers for your backend.

## Contributing

We welcome contributions! Whether it's adding new framework examples, improving documentation, or fixing bugs - PRs are appreciated.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

<p align="center">
  <a href="https://last9.io">
    <img src="https://last9.io/favicon.ico" width="32" alt="Last9">
  </a>
  <br>
  <strong>Built with love by <a href="https://last9.io">Last9</a></strong>
  <br>
  <sub>High cardinality observability, simplified.</sub>
</p>
