import requests

# Break down the URL into parts
base_url = "https://app.last9.io/api/v4/organizations/last9/logs/api/v2/query_range"

# All the query parameters as a dictionary
params = {
    "start": 1759924800,  
    "end": 1759925400,    
    "region": "ap-south-1",
    "query": '{service="accounting"}',
    "mode": "editor"
}

headers = {
    "X-LAST9-API-TOKEN": "Bearer Read Access Token"
}

# Make the request - requests will build the full URL for you!
response = requests.get(base_url, params=params, headers=headers)

# Check if it worked
if response.status_code == 200:
    data = response.json()
    print("Success!")
    
        
        # If there's a 'result' in data, check it
    if 'result' in data['data']:
        results = data['data']['result']
        print(f"Number of result streams: {len(results)}")
            
        if len(results) > 0 and len(results[0]['values']) > 0:
            first_log = results[0]['values'][0]
            print(f"Sample log entry: {first_log}")
else:
    print(f"Error: {response.status_code}")
    print(response.text)
