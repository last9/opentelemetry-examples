import requests
import time
import json
from datetime import datetime
from urllib.parse import quote

def fetch_logs(token, base_url):
    """
    Fetch logs from Last9 with pagination support.
    
    Args:
        token: Authentication token (Basic auth)
        base_url: Last9 API endpoint URL
    
    Returns:
        List of all log records retrieved
    """
    all_data = []
    offset = 0
    limit = 10000
    
    # Set physical index
    physical_index = "Default"
    
    # Define query in plain text
    query = '{service="ab-testing"}'
    
    # Convert query to required URL-encoded format
    encoded_query = quote(query)
    
    # Calculate epoch timestamps (seconds)
    end_epoc = int(time.time())  # Current time
    start_epoc = end_epoc - (5 * 60)  # 5 minutes ago in seconds
    
    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Starting log fetch from Last9")
    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Query: {query}")
    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Physical Index: {physical_index}")
    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Time range: {start_epoc} to {end_epoc} (last 15 minutes)")
    
    while True:
        # Set headers
        headers = {"Authorization": f"{token}"}
        
        # Construct URL with parameters
        url = (
            f"{base_url}"
            f"?query={encoded_query}"
            f"&start={start_epoc}"
            f"&end={end_epoc}"
            f"&offset={offset}"
            f"&limit={limit}"
            #f"&index=physical_index:{physical_index}"
        )
        
        try:
            # Debug: Print the curl command equivalent
            curl_command = f"curl -H 'Authorization: {headers['Authorization']}' '{url}'"
            print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] DEBUG: Equivalent curl command:")
            print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {curl_command}")
            
            # Make API request
            response = requests.get(url, headers=headers)
            print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] DEBUG: Response status code: {response.status_code}")
            print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] DEBUG: Response headers: {dict(response.headers)}")
            response.raise_for_status()
            
            # Parse response
            data = response.json()
            results = data['data']['result']
            
            # Append results to collection
            all_data.extend(results)
            
            batch_number = offset // limit + 1
            print(
                f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] "
                f"Batch {batch_number}: Retrieved {len(results)} records. "
                f"Total so far: {len(all_data)}"
            )
            
            # Break if we got fewer results than requested OR if results is empty
            if len(results) < limit or not results:
                break
            
            # Increment offset for next batch
            offset += limit
            
        except requests.exceptions.RequestException as e:
            print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Request failed: {e}")
            if hasattr(e, 'response') and e.response is not None:
                print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] DEBUG: Error response status: {e.response.status_code}")
                print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] DEBUG: Error response content: {e.response.text}")
            break
        except KeyError as e:
            print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Unexpected response format: {e}")
            break
    
    print(
        f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] "
        f"✅ Finished! Total records retrieved: {len(all_data)}"
    )
    
    return all_data


# Usage example:
if __name__ == "__main__":
    
    # API Documentation: https://last9.io/docs/query-logs-api/
    
    # Replace with your actual token
    auth_token="Basic auth token"
    # Replace with your base url
    base_url = "https://otlp-aps1.last9.io/loki/logs/api/v2/query_range"
    
    logs = fetch_logs(auth_token, base_url)
    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Final count: {len(logs)} log entries")
    
    # Write output to file
    output_file = "output.json"
    with open(output_file, 'w') as f:
        json.dump(logs, f, indent=2)
    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Output written to {output_file}")
