#!/usr/bin/env python3
"""
Prometheus exporter for Apache Cassandra nodetool metrics.
Exposes metrics not available via JMX: node status, thread pool stats,
compaction backlog, cache hit rates, and cluster topology.
"""
import os
import re
import subprocess
from http.server import BaseHTTPRequestHandler, HTTPServer

CASSANDRA_HOST = os.environ.get("CASSANDRA_HOST", "localhost")
CASSANDRA_JMX_PORT = os.environ.get("CASSANDRA_JMX_PORT", "7199")
EXPORTER_PORT = int(os.environ.get("EXPORTER_PORT", "9500"))


def run_nodetool(*args):
    try:
        result = subprocess.run(
            ["nodetool", "-h", CASSANDRA_HOST, "-p", CASSANDRA_JMX_PORT, *args],
            capture_output=True, text=True, timeout=30,
        )
        return result.stdout if result.returncode == 0 else None
    except Exception:
        return None


def parse_info():
    output = run_nodetool("info")
    if not output:
        return []

    metrics = []
    for line in output.splitlines():
        if m := re.search(r"Heap Memory \(MB\)\s*:\s*([\d.]+)\s*/\s*([\d.]+)", line):
            metrics += [
                f"cassandra_nodetool_heap_used_mb {m.group(1)}",
                f"cassandra_nodetool_heap_max_mb {m.group(2)}",
            ]
        elif m := re.search(r"Uptime \(seconds\)\s*:\s*(\d+)", line):
            metrics.append(f"cassandra_nodetool_uptime_seconds {m.group(1)}")
        elif m := re.search(r"Exceptions\s*:\s*(\d+)", line):
            metrics.append(f"cassandra_nodetool_exceptions_total {m.group(1)}")
        elif re.search(r"^Load\s*:", line):
            if m := re.search(r":\s*([\d.]+)\s*(\w+)", line):
                val, unit = float(m.group(1)), m.group(2)
                mult = {"B": 1, "KiB": 1024, "MiB": 1024**2, "GiB": 1024**3, "TiB": 1024**4}
                metrics.append(f"cassandra_nodetool_load_bytes {val * mult.get(unit, 1):.0f}")
        elif "Key Cache" in line:
            _append_cache_metrics(metrics, line, "key")
        elif "Row Cache" in line:
            _append_cache_metrics(metrics, line, "row")

    return metrics


def _append_cache_metrics(metrics, line, cache_type):
    if hits := re.search(r"(\d+) hits", line):
        metrics.append(f'cassandra_nodetool_{cache_type}_cache_hits_total {hits.group(1)}')
    if reqs := re.search(r"(\d+) requests", line):
        metrics.append(f'cassandra_nodetool_{cache_type}_cache_requests_total {reqs.group(1)}')
    if rate := re.search(r"([\d.]+) recent hit rate", line):
        metrics.append(f'cassandra_nodetool_{cache_type}_cache_hit_rate {rate.group(1)}')


def parse_tpstats():
    output = run_nodetool("tpstats")
    if not output:
        return []

    metrics = []
    for line in output.splitlines():
        parts = line.split()
        if len(parts) >= 4 and parts[0] not in ("Pool", "Message", ""):
            pool = parts[0].lower()
            try:
                active, pending, completed = int(parts[1]), int(parts[2]), int(parts[3])
                blocked = int(parts[4]) if len(parts) > 4 else 0
                lbl = f'pool="{pool}"'
                metrics += [
                    f"cassandra_nodetool_thread_pool_active{{{lbl}}} {active}",
                    f"cassandra_nodetool_thread_pool_pending{{{lbl}}} {pending}",
                    f"cassandra_nodetool_thread_pool_completed_total{{{lbl}}} {completed}",
                    f"cassandra_nodetool_thread_pool_blocked{{{lbl}}} {blocked}",
                ]
            except (ValueError, IndexError):
                pass

    return metrics


def parse_compactionstats():
    output = run_nodetool("compactionstats")
    if not output:
        return []

    metrics = []
    for line in output.splitlines():
        if m := re.search(r"pending tasks:\s*(\d+)", line):
            metrics.append(f"cassandra_nodetool_compaction_pending_tasks {m.group(1)}")
    return metrics


def parse_status():
    output = run_nodetool("status")
    if not output:
        return []

    up, down = 0, 0
    for line in output.splitlines():
        if re.match(r"^[UD][NLJM]\s+", line):
            if line[0] == "U":
                up += 1
            else:
                down += 1

    return [
        f"cassandra_nodetool_nodes_up {up}",
        f"cassandra_nodetool_nodes_down {down}",
    ]


def collect():
    lines = (
        parse_info()
        + parse_tpstats()
        + parse_compactionstats()
        + parse_status()
    )
    return "\n".join(lines) + "\n"


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/metrics":
            self.send_response(404)
            self.end_headers()
            return
        body = collect().encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


if __name__ == "__main__":
    print(f"nodetool exporter listening on :{EXPORTER_PORT} (cassandra={CASSANDRA_HOST}:{CASSANDRA_JMX_PORT})")
    HTTPServer(("0.0.0.0", EXPORTER_PORT), Handler).serve_forever()
