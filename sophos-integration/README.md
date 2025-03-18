# Sophos Central SIEM Integration with Last9

This integration fetches security events and alerts from Sophos Central API and forwards them to Last9 for monitoring and analysis.

## Overview

The integration:
- Fetches events and alerts from Sophos Central using their SIEM API
- Formats the data as JSON
- Forwards the data to Last9's OTLP endpoint
- Runs continuously with a 5-minute interval between fetches

## Prerequisites

1. Sophos Central API Credentials:
   - Client ID
   - Client Secret
   - Tenant ID (optional)

2. Last9 OTLP Endpoint URL:
   - Format: `https://username:password@otlp-aps1.last9.io:443/json/v2`

## Setup and Configuration

1. Clone this repository:
```bash
git clone <repository-url>
cd sophos-integration
```

2. Build the Docker image:
```bash
docker build -t sophos-siem-otel .
```

3. Run the container:
```bash
docker run -d \
  -e SOPHOS_CLIENT_ID="your-client-id" \
  -e SOPHOS_CLIENT_SECRET="your-client-secret" \
  -e SOPHOS_TENANT_ID="your-tenant-id" \
  -e LAST9_ENDPOINT="https://username:password@otlp-aps1.last9.io:443/json/v2" \
  sophos-siem-otel
```

## Configuration Details

### Environment Variables

- `SOPHOS_CLIENT_ID`: Your Sophos Central API client ID
- `SOPHOS_CLIENT_SECRET`: Your Sophos Central API client secret
- `SOPHOS_TENANT_ID`: (Optional) Your Sophos tenant ID
- `LAST9_ENDPOINT`: Complete Last9 OTLP endpoint URL with credentials

### Data Collection

The integration collects:
- Security Events
- Alerts
- System Events
- Endpoint Events

Data is collected every 5 minutes and sent to Last9 in JSON format.

## Directory Structure
```
sophos-integration/
├── Dockerfile
├── api_client.py
├── config.ini.template
├── config.py
├── name_mapping.py
├── requirements.txt
├── run.sh
├── siem.py
├── state.py
└── vercheck.py
```

## Monitoring and Troubleshooting

### Sophos API Credentials
Access to the APIs requires API Credentials that can be setup in the Sophos Central UI by going to Global Settings from the navigation bar and then selecting API Credentials Management. From this page, you can click the Add Credential button to create new credentials (client ID and client secret). Here is more information available on how to setup API Credentials: https://community.sophos.com/kb/en-us/125169

### View Logs
```bash
# Get container ID
docker ps

# View logs
docker logs -f <container_id>
```

### Debug Mode
To run with debug output:
```bash
docker run -it \
  -e SOPHOS_CLIENT_ID="your-client-id" \
  -e SOPHOS_CLIENT_SECRET="your-client-secret" \
  -e SOPHOS_TENANT_ID="your-tenant-id" \
  -e LAST9_ENDPOINT="your-last9-endpoint" \
  sophos-siem-otel python siem.py -d
```

### Common Issues

1. SSL Certificate Verification:
   - The script handles SSL verification automatically
   - No additional configuration needed

2. No Data:
   - Check Sophos credentials
   - Verify tenant ID if provided
   - Check Last9 endpoint URL format

3. JSON Parsing Errors:
   - The integration automatically formats data as valid JSON
   - Empty responses are handled gracefully

## Security

- Store credentials securely
- Never commit credentials to version control
- Use environment variables for sensitive information
- Regularly rotate API credentials

## Support

For issues with:
- Sophos API: Contact Sophos Support
- Last9 Integration: Contact Last9 Support
- This Integration: Open an issue in the repository

## License

This integration is licensed under the Apache License 2.0.
