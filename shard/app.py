from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import Dict, Any

app = FastAPI()
store: Dict[str, Any] = {}

class Record(BaseModel):
    key: str  # format: "partition_key|sort_key"
    data: dict

@app.post("/records")
def create_record(record: Record):
    store[record.key] = record.data
    return {"status": "created"}

@app.get("/records/{key}")
def read_record(key: str):
    if key not in store:
        raise HTTPException(status_code=404, detail="Not found")
    return store[key]

@app.delete("/records/{key}")
def delete_record(key: str):
    if key in store:
        del store[key]
    return {"status": "deleted"}

@app.get("/health")
def health():
    return {"status": "ok"}
