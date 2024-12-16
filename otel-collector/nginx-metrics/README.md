# Monitoring nginx with OpenTelemetry and Last9

This guide explains using Last9's OpenTelemetry metrics endpoint to ingest nginx metrics using OpenTelemetry Collector.

## Prerequisites

1. Install Nginx
2. Install OpenTelemetry Collector

## Installation Steps

### 1. Install OpenTelemetry Collector

Tested on Ubuntu 22.04 (LTS):

```bash
sudo apt-get update
sudo apt-get -y install wget systemctl
wget https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v0.110.0/otelcol-contrib_0.110.0_linux_amd64.deb
sudo dpkg -i otelcol-contrib_0.110.0_linux_amd64.deb
```

For more installation options, refer to the [official documentation](https://opentelemetry.io/docs/collector/installation/).

### 2. Install Nginx

```bash
# Install NGINX
sudo apt-get install -y nginx

# Start NGINX and enable it on boot
sudo systemctl start nginx
sudo systemctl enable nginx
```

## Configuration

### OpenTelemetry Collector Configuration

Edit the configuration file at `/etc/otelcol-contrib/config.yaml`:

```yaml
receivers:
  nginx:
    endpoint: "http://localhost:8080/nginx_status"
    collection_interval: 30s
processors:
  batch:
    timeout: 5s
    send_batch_size: 10000
    send_batch_max_size: 10000
  resourcedetection/system:
    detectors: ["system"]
    system:
      hostname_sources: ["os"]
  # optional: enable only if you are using EC2 instances.
  resourcedetection/ec2:
    detectors: ["ec2"]
    ec2:
      tags:
        - ^Name$
        - ^app$
  transform/ec2_metadata:
    metric_statements:
      - context: datapoint
        statements:
          - set(attributes["host.name"], resource.attributes["host.name"])
          - set(attributes["cloud.account.id"], resource.attributes["cloud.account.id"])
          - set(attributes["cloud.availability_zone"], resource.attributes["cloud.availability_zone"])
          - set(attributes["cloud.platform"], resource.attributes["cloud.platform"])
          - set(attributes["cloud.provider"], resource.attributes["cloud.provider"])
          - set(attributes["cloud.region"], resource.attributes["cloud.region"])
          - set(attributes["host.type"], resource.attributes["host.type"])
          - set(attributes["host.image.id"], resource.attributes["host.image.id"])
exporters:
  otlp/last9:
    endpoint: <last9_otlp_endpoint>
    headers:
      "Authorization": <last9_auth_header>
  debug:
    verbosity: detailed
service:
  pipelines:
    metrics:
      receivers: [nginx]
      processors: [batch, resourcedetection/system, resourcedetection/ec2, transform/ec2_metadata]
      exporters: [otlp/last9]
```

### Nginx Configuration

This guide uses the nginx [`ngx_http_stub_status_module`](https://nginx.org/en/docs/http/ngx_http_stub_status_module.html) module to monitor nginx. 
The `ngx_http_stub_status_module` module provides access to basic status information.

This module is not built by default, it should be enabled with the `--with-http_stub_status_module` configuration parameter.

Edit the configuration file at `/etc/nginx/conf.d/status.conf`:

```bash
server {
    listen 8080;
    location /nginx_status {
        stub_status on;
        access_log off;
        allow 127.0.0.1;
        deny all;
    }
}
```

## Running the Services

1. Test and reload nginx configuration:

```bash
sudo nginx -t
sudo systemctl reload nginx
```

2. Check nginx status:

```bash
curl http://localhost:8080/nginx_status
```

3. Run the OpenTelemetry Collector:

```bash
otelcol-contrib --config /etc/otelcol-contrib/config.yaml
```

## Verifying Metrics

This will push the metrics from nginx to Last9. To see the data in action, visit the [Last9](https://app.last9.io/).

## Troubleshooting

If you have any questions or issues, please contact us on Discord or via Email.
