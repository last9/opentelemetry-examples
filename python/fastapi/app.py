from fastapi import FastAPI, HTTPException
from opensearchpy import OpenSearch, RequestsHttpConnection
from pydantic import BaseModel
from typing import Dict, List, Optional, Any
import uvicorn
import json
import memcache
import time

# OpenTelemetry imports
from opentelemetry.instrumentation.opensearch import OpenSearchInstrumentor
from opentelemetry.instrumentation.python_memcached import PythonMemcachedInstrumentor

# Auto-instrument all python-memcached operations
PythonMemcachedInstrumentor().instrument()

# Initialize OpenSearch instrumentation after client creation
OpenSearchInstrumentor().instrument()

# Create a FastAPI application
app = FastAPI()

# OpenSearch client configuration
OPENSEARCH_HOST = "localhost"  # Change this to your OpenSearch host
OPENSEARCH_PORT = 9200  # Change this to your OpenSearch port
INDEX_NAME = "test-index"

# Initialize OpenSearch client
client = OpenSearch(
    hosts=[{"host": OPENSEARCH_HOST, "port": OPENSEARCH_PORT}],
    http_auth=None,  # Add credentials if needed
    use_ssl=False,   # Set to True for HTTPS
    verify_certs=False,
    connection_class=RequestsHttpConnection
)

# Initialize OpenSearch instrumentation after client creation

# Memcached client configuration
MEMCACHED_HOST = "localhost:11211"  # Change this to your Memcached host:port

# Initialize Memcached client
mc = memcache.Client([MEMCACHED_HOST], debug=0)


# Create index if it doesn't exist
try:
    if not client.indices.exists(INDEX_NAME):
        client.indices.create(INDEX_NAME)
except Exception as e:
    print(f"Error creating index: {e}")

# Pydantic models for request validation
class Document(BaseModel):
    content: Dict

class BulkDocuments(BaseModel):
    documents: List[Dict]

class SearchQuery(BaseModel):
    query: Dict

class CacheItem(BaseModel):
    key: str
    value: Any
    expiry: Optional[int] = 0  # 0 means no expiry

class CacheValue(BaseModel):
    value: Any

class MultiCacheItems(BaseModel):
    items: Dict[str, Any]
    expiry: Optional[int] = 0

class CounterValue(BaseModel):
    key: str
    delta: int = 1

@app.get("/")
async def root():
    return {"message": "Hello World from FastAPI with auto-instrumentation!"}

@app.post("/documents")
async def index_document(document: Document):
    try:
        response = client.index(
            index=INDEX_NAME,
            body=document.content,
            refresh=True
        )
        return {"message": "Document indexed successfully", "id": response["_id"]}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/documents/{doc_id}")
async def get_document(doc_id: str):
    try:
        response = client.get(
            index=INDEX_NAME,
            id=doc_id
        )
        return response["_source"]
    except Exception as e:
        raise HTTPException(status_code=404, detail="Document not found")

@app.put("/documents/{doc_id}")
async def update_document(doc_id: str, document: Document):
    try:
        response = client.update(
            index=INDEX_NAME,
            id=doc_id,
            body={"doc": document.content},
            refresh=True
        )
        return {"message": "Document updated successfully"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/documents/{doc_id}")
async def delete_document(doc_id: str):
    try:
        response = client.delete(
            index=INDEX_NAME,
            id=doc_id,
            refresh=True
        )
        return {"message": "Document deleted successfully"}
    except Exception as e:
        raise HTTPException(status_code=404, detail="Document not found")

@app.post("/documents/_bulk")
async def bulk_index(documents: BulkDocuments):
    try:
        bulk_data = []
        for doc in documents.documents:
            bulk_data.extend([
                {"index": {"_index": INDEX_NAME}},
                doc
            ])
        response = client.bulk(body=bulk_data, refresh=True)
        return {"message": "Bulk indexing completed", "items": response["items"]}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/documents/_search")
async def search_documents(query: SearchQuery):
    try:
        # Ensure proper query structure
        search_body = {}
        if isinstance(query.query, dict):
            if "query" not in query.query:
                # If query is not wrapped in a "query" object, wrap it
                search_body["query"] = query.query
            else:
                search_body = query.query
        
        response = client.search(
            index=INDEX_NAME,
            body=search_body
        )
        
        total_hits = response["hits"]["total"]["value"]
        
        return {
            "hits": response["hits"]["hits"],
            "total": total_hits
        }
    except Exception as e:
        # Add more context to the error message
        error_msg = f"Search error: {str(e)}"
        raise HTTPException(status_code=400, detail=error_msg)

@app.post("/documents/_match")
async def match_search(term: str, field: str):
    try:
        query = {
            "query": {
                "match": {
                    field: term
                }
            }
        }
        response = client.search(
            index=INDEX_NAME,
            body=query
        )
        return {
            "hits": response["hits"]["hits"],
            "total": response["hits"]["total"]["value"]
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/documents/_range")
async def range_search(field: str, gte: Optional[float] = None, lte: Optional[float] = None):
    try:
        range_params = {}
        if gte is not None:
            range_params["gte"] = gte
        if lte is not None:
            range_params["lte"] = lte
            
        query = {
            "query": {
                "range": {
                    field: range_params
                }
            }
        }
        response = client.search(
            index=INDEX_NAME,
            body=query
        )
        return {
            "hits": response["hits"]["hits"],
            "total": response["hits"]["total"]["value"]
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# Memcached endpoints
@app.post("/cache")
async def set_cache(item: CacheItem):
    try:
        success = mc.set(item.key, item.value, time=item.expiry)
        if success:
            return {"message": "Cache item set successfully", "key": item.key}
        else:
            raise HTTPException(status_code=500, detail="Failed to set cache item")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/cache/{key}")
async def get_cache(key: str):
    try:
        value = mc.get(key)
        if value is None:
            raise HTTPException(status_code=404, detail="Cache key not found")
        return {"key": key, "value": value}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.put("/cache/{key}")
async def update_cache(key: str, item: CacheValue):
    try:
        # Check if key exists first
        existing = mc.get(key)
        if existing is None:
            raise HTTPException(status_code=404, detail="Cache key not found")
        
        success = mc.set(key, item.value)
        if success:
            return {"message": "Cache item updated successfully", "key": key}
        else:
            raise HTTPException(status_code=500, detail="Failed to update cache item")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/cache/{key}")
async def delete_cache(key: str):
    try:
        success = mc.delete(key)
        if success:
            return {"message": "Cache item deleted successfully", "key": key}
        else:
            raise HTTPException(status_code=404, detail="Cache key not found")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/cache/_multi_set")
async def multi_set_cache(items: MultiCacheItems):
    try:
        success = mc.set_multi(items.items, time=items.expiry)
        failed_keys = [key for key in items.items.keys() if key not in success]
        
        if failed_keys:
            return {
                "message": "Some cache items failed to set",
                "successful_keys": list(success),
                "failed_keys": failed_keys
            }
        else:
            return {
                "message": "All cache items set successfully",
                "successful_keys": list(success),
                "count": len(success)
            }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/cache/_multi_get")
async def multi_get_cache(keys: List[str]):
    try:
        results = mc.get_multi(keys)
        missing_keys = [key for key in keys if key not in results]
        
        return {
            "results": results,
            "found_count": len(results),
            "missing_keys": missing_keys
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/cache/{key}/increment")
async def increment_cache(key: str, counter: CounterValue):
    try:
        # Use the delta from the request body, fallback to key if not provided
        delta = counter.delta if counter.key == key else 1
        result = mc.incr(key, delta=delta)
        
        if result is None:
            # Key doesn't exist, set it to the delta value
            success = mc.set(key, delta)
            if success:
                return {"message": "Cache counter initialized", "key": key, "value": delta}
            else:
                raise HTTPException(status_code=500, detail="Failed to initialize counter")
        
        return {"message": "Cache counter incremented", "key": key, "value": result}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/cache/{key}/decrement")
async def decrement_cache(key: str, counter: CounterValue):
    try:
        # Use the delta from the request body, fallback to key if not provided
        delta = counter.delta if counter.key == key else 1
        result = mc.decr(key, delta=delta)
        
        if result is None:
            # Key doesn't exist, set it to negative delta value
            success = mc.set(key, -delta)
            if success:
                return {"message": "Cache counter initialized", "key": key, "value": -delta}
            else:
                raise HTTPException(status_code=500, detail="Failed to initialize counter")
        
        return {"message": "Cache counter decremented", "key": key, "value": result}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/cache/_flush")
async def flush_cache():
    try:
        result = mc.flush_all()
        # flush_all() returns 1 on success for most memcached servers
        # or None/empty dict for some configurations
        if result is not None and result != {}:
            return {"message": "Cache flushed successfully", "result": result}
        else:
            # Even if result is None/empty, the flush may have succeeded
            # Let's return success with debug info
            return {"message": "Cache flush attempted", "result": result, "note": "Flush may have succeeded despite empty result"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Flush error: {str(e)}")

@app.get("/cache/_stats")
async def get_cache_stats():
    try:
        stats = mc.get_stats()
        # get_stats() returns a list of tuples: [(server, stats_dict), ...]
        if stats:
            return {"stats": stats, "server_count": len(stats)}
        else:
            return {"stats": [], "server_count": 0, "note": "No memcached servers responded or no stats available"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Stats error: {str(e)}")

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
