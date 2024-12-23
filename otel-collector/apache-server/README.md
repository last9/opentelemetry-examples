# Monitoring Apache Server Metrics with OpenTelemetry

A guide for setting up Apache Server monitoring using OpenTelemetry Collector with Last9. It collects host metrics, Apache Server metrics and sends them to Last9.

## Installation

### 1. Apache Server Setup

```bash
# Install apache
sudo apt-get update
sudo apt-get install -y apache2
sudo systemctl start apache2

# Verify installation
sudo systemctl status apache2
```

Configure Apache Server:
```bash
sudo nano /etc/apache2/apache2.conf
```

Add the below configuration in the conf file:
```ini
<Location "/server-status">
    SetHandler server-status
    Require host localhost
</Location>
```
Note: Replace `localhost` with your domain name.

```bash
# Restart Apache
sudo systemctl restart apache2
```

### 2. Install OpenTelemetry Collector

```bash
sudo apt-get update
sudo apt-get -y install wget systemctl
wget https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v0.110.0/otelcol-contrib_0.110.0_linux_amd64.deb
sudo dpkg -i otelcol-contrib_0.110.0_linux_amd64.deb
```

Configure collector:
```bash
sudo nano /etc/otelcol-contrib/config.yaml
```

Copy the configuration from [here](./otel-config.yaml) and update in `/etc/otelcol-contrib/config.yaml`.

Start collector:
```bash
otelcol-contrib --config /etc/otelcol-contrib/config.yaml
```

## Verification

1. Test exporter:
You can access the following link - http://localhost/server-status in your browser to check the metrics of the apache server

```bash
curl http://localhost/server-status
```

## Troubleshooting

1. Apache issues:
```bash
sudo systemctl status apache2
sudo journalctl -u apache2
```
2. Collector issues:
```bash
sudo systemctl status otelcol-contrib
sudo journalctl -u otelcol-contrib
```