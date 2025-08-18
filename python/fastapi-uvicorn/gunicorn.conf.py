import os

# Server socket
bind = "0.0.0.0:8000"
backlog = 2048

# Worker processes
workers = 2
worker_class = "uvicorn.workers.UvicornWorker"
worker_connections = 1000
timeout = 60
keepalive = 2

# Restart workers after this many requests, to prevent memory leaks
max_requests = 5000
max_requests_jitter = 1000

# Logging
loglevel = "info"
errorlog = "-"
accesslog = "-"

# Process naming
proc_name = "fastapi-otel-app"

# Server mechanics
daemon = False
pidfile = "/tmp/gunicorn.pid"
user = None
group = None
tmp_upload_dir = None

# Pre-load app for better performance
preload_app = False

