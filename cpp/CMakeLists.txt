cmake_minimum_required(VERSION 3.14)
project(cpp-otel-sample VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Find required dependencies
find_package(CURL REQUIRED)
find_package(Protobuf REQUIRED)
find_package(nlohmann_json REQUIRED)

# Find OpenTelemetry packages
find_package(opentelemetry-cpp CONFIG REQUIRED)

# Create executable
add_executable(sample-app main.cpp)

# Link OpenTelemetry libraries and dependencies
target_link_libraries(sample-app PRIVATE
    opentelemetry-cpp::trace
    opentelemetry-cpp::otlp_http_exporter
    opentelemetry-cpp::resources
    CURL::libcurl
    protobuf::libprotobuf
    nlohmann_json::nlohmann_json
)
