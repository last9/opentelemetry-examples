#!/bin/bash

# Generate config.ini from template
envsubst < config.ini.template > config.ini

# Construct the full Last9 URL with query parameters
FULL_LAST9_URL="${LAST9_ENDPOINT}?service_name=sophos-central&source=sophos"

# Run the SIEM script and pipe output to Last9
while true; do
    echo "Debug: Running SIEM script..."
    
    # Create a temporary directory for output
    mkdir -p /tmp/sophos_output
    
    # Run the SIEM script and capture all output
    python siem.py --quiet > /tmp/sophos_output/raw_output.txt 2>&1
    
    # Create a valid JSON array with a dummy message if no data
    if [ ! -s /tmp/sophos_output/raw_output.txt ]; then
        echo '[{"message": "No data from Sophos API", "timestamp": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"}]' > /tmp/sophos_output/final_output.json
    else
        # Ensure the output is wrapped in array brackets
        echo "[" > /tmp/sophos_output/final_output.json
        cat /tmp/sophos_output/raw_output.txt | grep -v "SSL certificate" >> /tmp/sophos_output/final_output.json
        echo "]" >> /tmp/sophos_output/final_output.json
    fi
    
    echo "Debug: Prepared JSON payload:"
    cat /tmp/sophos_output/final_output.json
    
    # Validate JSON before sending
    if jq empty /tmp/sophos_output/final_output.json 2>/dev/null; then
        echo "Debug: JSON is valid, sending to Last9..."
        RESPONSE=$(curl -v -X POST \
          -H "Content-Type: application/json" \
          "${FULL_LAST9_URL}" \
          --data-binary @/tmp/sophos_output/final_output.json 2>&1)
        
        echo "Debug: Last9 Response:"
        echo "$RESPONSE"
    else
        echo "Debug: Invalid JSON generated, skipping upload"
        echo "Debug: Raw content:"
        cat /tmp/sophos_output/raw_output.txt
    fi
    
    # Cleanup
    rm -rf /tmp/sophos_output
    
    sleep 300  # Wait 5 minutes before next fetch
done
