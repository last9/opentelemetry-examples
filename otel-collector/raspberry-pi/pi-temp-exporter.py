#!/usr/bin/env python3
"""
Raspberry Pi Temperature Exporter for Prometheus/OpenTelemetry

Exposes CPU and GPU temperature as Prometheus metrics on port 9101.
Designed to be scraped by OpenTelemetry Collector's prometheus receiver.
"""

import http.server
import socketserver
import subprocess
import os

PORT = 9101

def get_cpu_temp():
    """Read CPU temperature from thermal zone."""
    try:
        with open('/sys/class/thermal/thermal_zone0/temp', 'r') as f:
            temp = int(f.read().strip()) / 1000.0
            return temp
    except Exception:
        return None

def get_gpu_temp():
    """Read GPU temperature using vcgencmd (Pi-specific)."""
    try:
        result = subprocess.run(
            ['vcgencmd', 'measure_temp'],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            # Output format: temp=42.0'C
            temp_str = result.stdout.strip()
            temp = float(temp_str.replace("temp=", "").replace("'C", ""))
            return temp
    except Exception:
        pass
    return None

def get_throttle_state():
    """Check if Pi is throttled due to temperature/voltage."""
    try:
        result = subprocess.run(
            ['vcgencmd', 'get_throttled'],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            # Output format: throttled=0x0
            value = result.stdout.strip().split('=')[1]
            return int(value, 16)
    except Exception:
        pass
    return None

class MetricsHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != '/metrics':
            self.send_response(404)
            self.end_headers()
            return

        metrics = []
        hostname = os.uname().nodename

        # CPU Temperature
        cpu_temp = get_cpu_temp()
        if cpu_temp is not None:
            metrics.append('# HELP rpi_cpu_temperature_celsius Raspberry Pi CPU temperature in Celsius')
            metrics.append('# TYPE rpi_cpu_temperature_celsius gauge')
            metrics.append(f'rpi_cpu_temperature_celsius{{host="{hostname}"}} {cpu_temp:.2f}')

        # GPU Temperature
        gpu_temp = get_gpu_temp()
        if gpu_temp is not None:
            metrics.append('# HELP rpi_gpu_temperature_celsius Raspberry Pi GPU temperature in Celsius')
            metrics.append('# TYPE rpi_gpu_temperature_celsius gauge')
            metrics.append(f'rpi_gpu_temperature_celsius{{host="{hostname}"}} {gpu_temp:.2f}')

        # Throttle state (bit flags for undervoltage, frequency capping, throttling)
        throttle = get_throttle_state()
        if throttle is not None:
            metrics.append('# HELP rpi_throttled Raspberry Pi throttle state (0=OK, non-zero=throttled)')
            metrics.append('# TYPE rpi_throttled gauge')
            metrics.append(f'rpi_throttled{{host="{hostname}"}} {throttle}')

            # Individual throttle flags
            metrics.append('# HELP rpi_undervoltage Raspberry Pi undervoltage detected (1=yes, 0=no)')
            metrics.append('# TYPE rpi_undervoltage gauge')
            metrics.append(f'rpi_undervoltage{{host="{hostname}"}} {1 if throttle & 0x1 else 0}')

            metrics.append('# HELP rpi_freq_capped Raspberry Pi frequency capped (1=yes, 0=no)')
            metrics.append('# TYPE rpi_freq_capped gauge')
            metrics.append(f'rpi_freq_capped{{host="{hostname}"}} {1 if throttle & 0x2 else 0}')

            metrics.append('# HELP rpi_throttling Raspberry Pi currently throttled (1=yes, 0=no)')
            metrics.append('# TYPE rpi_throttling gauge')
            metrics.append(f'rpi_throttling{{host="{hostname}"}} {1 if throttle & 0x4 else 0}')

        response = '\n'.join(metrics) + '\n'

        self.send_response(200)
        self.send_header('Content-type', 'text/plain; charset=utf-8')
        self.send_header('Content-Length', len(response))
        self.end_headers()
        self.wfile.write(response.encode())

    def log_message(self, format, *args):
        pass  # Suppress logging

if __name__ == '__main__':
    with socketserver.TCPServer(("", PORT), MetricsHandler) as httpd:
        print(f"Raspberry Pi Temperature Exporter running on port {PORT}")
        httpd.serve_forever()
