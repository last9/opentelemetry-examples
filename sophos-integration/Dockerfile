FROM python:3.9-slim as siem

# Install required system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    wget \
    gnupg \
    gettext-base \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy the SIEM script and related files
COPY siem.py .
COPY api_client.py .
COPY config.py .
COPY name_mapping.py .
COPY state.py .
COPY vercheck.py .
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Create necessary directories
RUN mkdir -p /app/log /app/state

# Copy configuration files
COPY config.ini.template .
COPY run.sh .
RUN chmod +x run.sh

# Environment variables
ENV SOPHOS_CLIENT_ID=""
ENV SOPHOS_CLIENT_SECRET=""
ENV SOPHOS_TENANT_ID=""
ENV LAST9_ENDPOINT=""

ENTRYPOINT ["./run.sh"]
