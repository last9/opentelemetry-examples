FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY *.csproj .
RUN dotnet restore
COPY . .
RUN dotnet publish -c Release -o /app/publish

FROM mcr.microsoft.com/dotnet/aspnet:8.0
WORKDIR /app
COPY --from=build /app/publish .

# Install OpenTelemetry .NET auto-instrumentation agent
ARG OTEL_DOTNET_AUTO_VERSION=1.10.0
ENV OTEL_DOTNET_AUTO_HOME=/otel-dotnet-auto
RUN apt-get update && apt-get install -y unzip curl \
    && curl -sSfL "https://github.com/open-telemetry/opentelemetry-dotnet-instrumentation/releases/download/v${OTEL_DOTNET_AUTO_VERSION}/otel-dotnet-auto-install.sh" -o otel-dotnet-auto-install.sh \
    && sh otel-dotnet-auto-install.sh \
    && rm otel-dotnet-auto-install.sh \
    && apt-get purge -y unzip curl && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

# Enable .NET CLR profiler for auto-instrumentation
ENV CORECLR_ENABLE_PROFILING=1
ENV CORECLR_PROFILER={918728DD-259F-4A6A-AC2B-B85E1B658571}
ENV CORECLR_PROFILER_PATH=/otel-dotnet-auto/linux-x64/OpenTelemetry.AutoInstrumentation.Native.so
ENV DOTNET_ADDITIONAL_DEPS=/otel-dotnet-auto/AdditionalDeps
ENV DOTNET_SHARED_STORE=/otel-dotnet-auto/store
ENV DOTNET_STARTUP_HOOKS=/otel-dotnet-auto/net/OpenTelemetry.AutoInstrumentation.StartupHook.dll

EXPOSE 8080
ENTRYPOINT ["dotnet", "HttpBodyCapture.dll"]
