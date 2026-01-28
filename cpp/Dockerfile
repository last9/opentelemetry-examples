# Multi-stage build for OpenTelemetry C++ application
# Stage 1: Build OpenTelemetry SDK and application
FROM ubuntu:22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    libcurl4-openssl-dev \
    libssl-dev \
    pkg-config \
    nlohmann-json3-dev \
    libprotobuf-dev \
    protobuf-compiler \
    && rm -rf /var/lib/apt/lists/*

# Clone and build opentelemetry-cpp
WORKDIR /deps

# Use a specific stable version
RUN git clone --recurse-submodules --depth 1 --branch v1.14.2 \
    https://github.com/open-telemetry/opentelemetry-cpp.git

WORKDIR /deps/opentelemetry-cpp/build

# Configure OpenTelemetry build
RUN cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DBUILD_TESTING=OFF \
    -DWITH_OTLP_HTTP=ON \
    -DWITH_OTLP_GRPC=OFF \
    -DWITH_EXAMPLES=OFF \
    -DCMAKE_INSTALL_PREFIX=/opt/opentelemetry

# Build and install
RUN make -j$(nproc) && make install

# Build the application
WORKDIR /app
COPY CMakeLists.txt main.cpp ./

RUN mkdir build && cd build && \
    cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -Dopentelemetry-cpp_DIR=/opt/opentelemetry/lib/cmake/opentelemetry-cpp && \
    make -j$(nproc)

# Stage 2: Runtime image
FROM ubuntu:22.04 AS runtime

ENV DEBIAN_FRONTEND=noninteractive

# Install runtime dependencies only
RUN apt-get update && apt-get install -y \
    libcurl4 \
    libssl3 \
    libprotobuf23 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy the built application
COPY --from=builder /app/build/sample-app /usr/local/bin/sample-app

# Copy shared libraries from OpenTelemetry
COPY --from=builder /opt/opentelemetry/lib/*.so* /usr/local/lib/

# Update library cache
RUN ldconfig

# Set working directory
WORKDIR /app

# Default environment variables (can be overridden)
ENV OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp-aps1.last9.io
ENV OTEL_SERVICE_NAME=cpp-sample-app
ENV DEPLOYMENT_ENVIRONMENT=local

# Run the application
CMD ["sample-app"]
