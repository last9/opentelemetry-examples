# Monitoring Docker Containers with OpenTelemetry and Last9

A guide for setting up Docker container monitoring using OpenTelemetry Collector with Last9. It collects container metrics, and logs from docker containers and sends them to Last9.

## Installation

### 1. Prerequisites

Ensure Docker and Docker Compose are installed on your system:

```bash
# Check Docker installation
docker --version

# Check Docker Compose installation
docker compose version
```

### 2. Configure OpenTelemetry Collector

The setup uses the `otel-config.yaml` file which defines:
- Docker stats receiver for container metrics
- TCP log receiver for container logs
- Processors for batch processing and resource detection
- Last9 exporter configuration

Before proceeding, update the Last9 authorization token:

```bash
# Edit the config file
nano otel-config.yaml
```

In the `exporters` section, replace `<Last9 Basic Auth Token>` with your actual Last9 authorization auth header. You can get the auth header from [Last9 Integrations](https://app.last9.io/integrations).

### 3. Set Up with Docker Compose

This setup demonstrates how to monitor multiple Docker containers using multiple Docker Compose files to create a complete monitoring stack:

#### Start Apache Server

```bash
docker compose -f apache-compose.yaml up -d
```

This launches an Apache httpd server on port 8002.

#### Start Nginx Server (Optional)

```bash
docker compose -f nginx-compose.yaml up -d
```

This launches an Nginx server on port 8000.

#### Start OpenTelemetry Collector

```bash
docker compose -f otel-compose.yaml up -d
```

This starts:
- OpenTelemetry Collector with the configuration from `otel-config.yaml`
- Logspout container that forwards logs from Docker containers to the collector

## Understanding the Setup

### Docker Networks

The setup creates three Docker networks:
- `nginx_network`: Network for Nginx server
- `apache_network`: Network for Apache server
- `otel_network`: Network for OpenTelemetry components

Logspout connects to all three networks to collect logs.

### Container Metrics

The OpenTelemetry Collector is configured to collect various metrics:
- CPU usage and utilization
- Memory usage and limits
- Network I/O statistics
- Block I/O information
- Container process information

### Log Collection

Container logs are collected using Logspout and sent to OpenTelemetry Collector for processing before being exported to Last9.

## Verification

1. Verify the containers are running:
```bash
docker ps
```

2. Test Apache server:
```bash
curl http://localhost:8002
```

3. Test Nginx server (if installed):
```bash
curl http://localhost:8000
```

4. Check OpenTelemetry Collector logs:
```bash
docker logs otel-collector
```

## Troubleshooting

1. Container issues:
```bash
# Check container status
docker ps -a

# View container logs
docker logs apache-server
docker logs nginx-server
docker logs otel-collector
docker logs logspout
```

2. Network issues:
```bash
# List networks
docker network ls

# Inspect a network
docker network inspect apache_network
docker network inspect nginx_network
docker network inspect otel_network
```

3. OpenTelemetry Collector issues:
```bash
# Check configuration
docker exec otel-collector cat /etc/otel-collector-config.yaml

# Restart collector
docker compose -f otel-compose.yaml restart otel-collector
```

## Stopping the Stack

```bash
docker compose -f otel-compose.yaml down
docker compose -f nginx-compose.yaml down
docker compose -f apache-compose.yaml down
```