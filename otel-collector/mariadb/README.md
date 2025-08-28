# Monitoring MariaDB with OpenTelemetry

A guide for setting up MariaDB/MySQL monitoring using `mysqld_exporter` and OpenTelemetry Collector with Last9. It collects host metrics, MySQL metrics, and MySQL logs and sends them to Last9.

## Supported versions:

MySQL >= 5.6.
MariaDB >= 10.3

## Installation

### 1. MariaDB Setup

```bash
# Install MariaDB
sudo apt-get update
sudo apt-get install -y mariadb-server mariadb-client

# Verify installation
sudo systemctl status mariadb

# Run security script
sudo mysql_secure_installation
```

Configure MariaDB:
```bash
sudo nano /etc/mysql/mariadb.conf.d/50-server.cnf
```

Add configuration:
```ini
[mysqld]
bind-address = 0.0.0.0
max_connections = 100
innodb_buffer_pool_size = 256M
thread_cache_size = 8
slow_query_log = 1
slow_query_log_file = /var/log/mysql/mariadb-slow.log
long_query_time = 2
```

```bash
# Restart MariaDB
sudo systemctl restart mariadb
```

### 2. Create Monitoring User

```sql
sudo mysql -u root -p

CREATE USER 'exporter'@'localhost' IDENTIFIED BY 'strong_password';
GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'localhost';
FLUSH PRIVILEGES;
EXIT;
```

### 3. Install mysqld_exporter

```bash
# Create system user
sudo useradd --no-create-home --shell /bin/false mysqld_exporter

# Download and install
cd /tmp
curl -s https://api.github.com/repos/prometheus/mysqld_exporter/releases/latest \
  | grep browser_download_url \
  | grep linux-amd64 \
  | cut -d '"' -f 4 \
  | wget -qi -

tar xvf mysqld_exporter*.tar.gz
sudo mv mysqld_exporter-*.linux-amd64/mysqld_exporter /usr/local/bin/
sudo chown mysqld_exporter:mysqld_exporter /usr/local/bin/mysqld_exporter
```

Configure exporter:
```bash
sudo tee /etc/.mysqld_exporter.cnf << EOF
[client]
user=exporter
password=strong_password
EOF

sudo chown mysqld_exporter:mysqld_exporter /etc/.mysqld_exporter.cnf
sudo chmod 600 /etc/.mysqld_exporter.cnf
```

Create service:
```bash
sudo tee /etc/systemd/system/mysqld_exporter.service << EOF
[Unit]
Description=MySQLd Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=mysqld_exporter
Group=mysqld_exporter
Type=simple
ExecStart=/usr/local/bin/mysqld_exporter \
  --config.my-cnf=/etc/.mysqld_exporter.cnf \
  --collect.global_status \
  --collect.global_variables \
  --collect.info_schema.innodb_metrics \
  --collect.info_schema.processlist \
  --collect.info_schema.tables \
  --collect.info_schema.tables.databases='*' \
  --collect.perf_schema.eventsstatements \
  --collect.perf_schema.file_events \
  --collect.perf_schema.indexiowaits \
  --collect.perf_schema.tableiowaits \
  --collect.perf_schema.tablelocks \
  --collect.slave_status \
  --web.listen-address=:9104

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl start mysqld_exporter
sudo systemctl enable mysqld_exporter
```

### 4. Install OpenTelemetry Collector

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

1. Check MariaDB:
```bash
mysql -u root -p -e "SELECT VERSION();"
```

2. Verify configuration:
```bash
mysql -u root -p -e "SHOW VARIABLES LIKE '%max_connections%';"
mysql -u root -p -e "SHOW VARIABLES LIKE '%innodb_buffer_pool_size%';"
mysql -u root -p -e "SHOW VARIABLES LIKE '%slow_query%';"
```

3. Test exporter:
```bash
mysql -u exporter -p -e "SELECT 1;"
curl http://localhost:9104/metrics | grep mysql_up
```

## Troubleshooting

1. MariaDB issues:
```bash
sudo systemctl status mariadb
sudo journalctl -u mariadb
```

2. Exporter issues:
```bash
sudo systemctl status mysqld_exporter
sudo journalctl -u mysqld_exporter
```

3. Collector issues:
```bash
sudo systemctl status otelcol-contrib
sudo journalctl -u otelcol-contrib
```