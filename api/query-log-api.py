import requests
import time
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
    query = '{service=~"example.*"}'
    
    # Convert query to required URL-encoded format
    encoded_query = quote(query)
    
    # Calculate epoch timestamps (nanoseconds)
    end_epoc = int(time.time() * 1000000000)  # Current time
    start_epoc = end_epoc - (15 * 60 * 1000000000)  # 15 minutes ago in nanoseconds
    
    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Starting log fetch from Last9")
    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Query: {query}")
    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Physical Index: {physical_index}")
    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Time range: {start_epoc} to {end_epoc} (last 15 minutes)")
    
    while True:
        # Set headers
        headers = {"Authorization": f"Basic {token}"}
        
        # Construct URL with parameters
        url = (
            f"{base_url}"
            f"?query={encoded_query}"
            f"&start={start_epoc}"
            f"&end={end_epoc}"
            f"&offset={offset}"
            f"&limit={limit}"
            f"&index=physical_index:{physical_index}"
        )
        
        try:
            # Make API request
            response = requests.get(url, headers=headers)
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
    # Get your API token from: https://app.last9.io/settings/api-access
    
    # Replace with your actual token
    auth_token = "your_token_here"
    # Replace with your base url
    base_url = "https://otlp-aps1.last9.io/loki/logs/api/v2/query_range"
    
    logs = fetch_logs(auth_token)
    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Final count: {len(logs)} log entries")
