from fastapi import FastAPI

# Create a FastAPI application
app = FastAPI()

@app.get("/")
async def root():
    return {"message": "Hello World from FastAPI with auto-instrumentation!"}

@app.get("/items/{item_id}")
async def read_item(item_id: int):
    return {"item_id": item_id}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
