#include <iostream>
#include <string>
#include <thread>
#include <chrono>
#include <random>
#include <cstdlib>

#include "opentelemetry/exporters/otlp/otlp_http_exporter_factory.h"
#include "opentelemetry/exporters/otlp/otlp_http_exporter_options.h"
#include "opentelemetry/sdk/trace/processor.h"
#include "opentelemetry/sdk/trace/batch_span_processor_factory.h"
#include "opentelemetry/sdk/trace/batch_span_processor_options.h"
#include "opentelemetry/sdk/trace/tracer_provider_factory.h"
#include "opentelemetry/sdk/trace/tracer_provider.h"
#include "opentelemetry/trace/provider.h"
#include "opentelemetry/trace/span_startoptions.h"
#include "opentelemetry/sdk/resource/resource.h"
#include "opentelemetry/sdk/resource/semantic_conventions.h"

namespace trace_api = opentelemetry::trace;
namespace trace_sdk = opentelemetry::sdk::trace;
namespace otlp = opentelemetry::exporter::otlp;
namespace resource = opentelemetry::sdk::resource;

std::string GetEnvVar(const std::string& var_name, const std::string& default_value = "") {
    const char* value = std::getenv(var_name.c_str());
    return value ? std::string(value) : default_value;
}

void InitTracer() {
    // Get configuration from environment variables
    std::string service_name = GetEnvVar("OTEL_SERVICE_NAME", "cpp-sample-app");
    std::string deployment_env = GetEnvVar("DEPLOYMENT_ENVIRONMENT", "local");

    // Configure OTLP HTTP exporter options
    // The SDK will automatically read OTEL_EXPORTER_OTLP_ENDPOINT and OTEL_EXPORTER_OTLP_HEADERS
    otlp::OtlpHttpExporterOptions opts;
    opts.content_type = otlp::HttpRequestContentType::kJson;

    std::cout << "Initializing tracer with endpoint: " << opts.url << std::endl;

    // Create exporter
    auto exporter = otlp::OtlpHttpExporterFactory::Create(opts);

    // Configure batch processor
    trace_sdk::BatchSpanProcessorOptions processor_opts;
    processor_opts.max_queue_size = 2048;
    processor_opts.max_export_batch_size = 512;

    auto processor = trace_sdk::BatchSpanProcessorFactory::Create(std::move(exporter), processor_opts);

    // Create resource with service name and deployment environment
    resource::ResourceAttributes attributes = {
        {resource::SemanticConventions::kServiceName, service_name},
        {"deployment.environment", deployment_env}
    };
    auto resource_obj = resource::Resource::Create(attributes);

    // Create tracer provider
    auto provider = trace_sdk::TracerProviderFactory::Create(std::move(processor), resource_obj);

    // Set global tracer provider
    trace_api::Provider::SetTracerProvider(std::move(provider));

    std::cout << "Tracer initialized successfully!" << std::endl;
    std::cout << "Service: " << service_name << ", Environment: " << deployment_env << std::endl;
}

void CleanupTracer() {
    // Give time for the batch processor to flush remaining spans
    std::this_thread::sleep_for(std::chrono::seconds(2));

    // Reset the global tracer provider
    std::shared_ptr<trace_api::TracerProvider> none;
    trace_api::Provider::SetTracerProvider(none);

    std::cout << "Tracer cleaned up." << std::endl;
}

int RollDice() {
    static std::random_device rd;
    static std::mt19937 gen(rd());
    static std::uniform_int_distribution<> distrib(1, 6);
    return distrib(gen);
}

void ProcessRequest(int request_id) {
    auto tracer = trace_api::Provider::GetTracerProvider()->GetTracer("cpp-sample-app", "1.0.0");

    // Create SERVER span for the incoming HTTP request
    trace_api::StartSpanOptions server_opts;
    server_opts.kind = trace_api::SpanKind::kServer;

    auto server_span = tracer->StartSpan("GET /roll-dice", server_opts);
    auto server_scope = tracer->WithActiveSpan(server_span);

    // Set HTTP server span attributes
    server_span->SetAttribute("http.method", "GET");
    server_span->SetAttribute("http.scheme", "http");
    server_span->SetAttribute("http.target", "/roll-dice");
    server_span->SetAttribute("http.route", "/roll-dice");
    server_span->SetAttribute("http.host", "localhost:8080");
    server_span->SetAttribute("http.user_agent", "curl/7.68.0");
    server_span->SetAttribute("http.request_content_length", 0);
    server_span->SetAttribute("net.host.name", "localhost");
    server_span->SetAttribute("net.host.port", 8080);
    server_span->SetAttribute("request.id", request_id);

    // Simulate some processing with an INTERNAL span
    {
        trace_api::StartSpanOptions internal_opts;
        internal_opts.kind = trace_api::SpanKind::kInternal;

        auto child_span = tracer->StartSpan("roll_dice", internal_opts);
        auto child_scope = tracer->WithActiveSpan(child_span);

        // Simulate work
        std::this_thread::sleep_for(std::chrono::milliseconds(50 + rand() % 100));

        int dice_result = RollDice();
        child_span->SetAttribute("dice.result", dice_result);

        std::cout << "Request " << request_id << ": Rolled a " << dice_result << std::endl;

        child_span->End();
    }

    // Simulate CLIENT span for database call
    {
        trace_api::StartSpanOptions client_opts;
        client_opts.kind = trace_api::SpanKind::kClient;

        auto db_span = tracer->StartSpan("postgresql.query", client_opts);
        auto db_scope = tracer->WithActiveSpan(db_span);

        db_span->SetAttribute("db.system", "postgresql");
        db_span->SetAttribute("db.name", "dice_db");
        db_span->SetAttribute("db.operation", "INSERT");
        db_span->SetAttribute("db.statement", "INSERT INTO rolls (value) VALUES ($1)");
        db_span->SetAttribute("net.peer.name", "db.example.com");
        db_span->SetAttribute("net.peer.port", 5432);

        // Simulate database operation
        std::this_thread::sleep_for(std::chrono::milliseconds(20 + rand() % 50));

        db_span->End();
    }

    // Set response attributes on server span
    server_span->SetAttribute("http.status_code", 200);
    server_span->SetAttribute("http.response_content_length", 42);
    server_span->End();
}

int main() {
    std::cout << "=== OpenTelemetry C++ Sample Application ===" << std::endl;
    std::cout << "Sending traces to Last9" << std::endl;
    std::cout << std::endl;

    // Initialize OpenTelemetry
    InitTracer();

    // Process some sample requests
    int num_requests = 10;
    std::cout << "\nProcessing " << num_requests << " requests...\n" << std::endl;

    for (int i = 1; i <= num_requests; i++) {
        ProcessRequest(i);
        // Small delay between requests
        std::this_thread::sleep_for(std::chrono::milliseconds(500));
    }

    std::cout << "\nAll requests processed. Flushing traces..." << std::endl;

    // Cleanup and flush
    CleanupTracer();

    std::cout << "Done! Check your Last9 dashboard for traces." << std::endl;

    return 0;
}
