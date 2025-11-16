from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel
from typing import Dict, Any, List
import requests
import os
from shard_manager import ShardManager

app = FastAPI()

# Load shards from env (e.g., "http://shard1:8000,http://shard2:8000")
SHARD_URLS = os.getenv("SHARD_URLS", "http://shard1:8000").split(",")
shard_manager = ShardManager(SHARD_URLS)

tables: Dict[str, Dict[str, str]] = {}  # table_name -> {partition_key, sort_key}

class TableSchema(BaseModel):
    table_name: str
    partition_key: str
    sort_key: str

@app.post("/tables")
def register_table(schema: TableSchema):
    tables[schema.table_name] = {
        "partition_key": schema.partition_key,
        "sort_key": schema.sort_key,
    }
    return {"status": "created"}

class RecordCreate(BaseModel):
    partition_key: str
    sort_key: str
    data: dict

@app.post("/tables/{table_name}/records")
def create_record(table_name: str, record: RecordCreate):
    if table_name not in tables:
        raise HTTPException(status_code=404, detail="Table not found")

    key = f"{record.partition_key}|{record.sort_key}"
    shard_url = shard_manager.get_shard_url(record.partition_key)
    resp = requests.post(f"{shard_url}/records", json={"key": key, "data": record.data})
    if resp.status_code != 200:
        raise HTTPException(status_code=500, detail="Shard error")
    return {"status": "created"}

@app.get("/tables/{table_name}/records")
def read_record(
    table_name: str,
    partition_key: str = Query(...),
    sort_key: str = Query(...)
):
    if table_name not in tables:
        raise HTTPException(status_code=404, detail="Table not found")

    key = f"{partition_key}|{sort_key}"
    shard_url = shard_manager.get_shard_url(partition_key)
    resp = requests.get(f"{shard_url}/records/{key}")
    if resp.status_code == 404:
        raise HTTPException(status_code=404, detail="Record not found")
    elif resp.status_code != 200:
        raise HTTPException(status_code=500, detail="Shard error")
    return resp.json()

@app.delete("/tables/{table_name}/records/delete")
def delete_record(
    table_name: str,
    partition_key: str = Query(...),
    sort_key: str = Query(...)
):
    if table_name not in tables:
        raise HTTPException(status_code=404, detail="Table not found")

    key = f"{partition_key}|{sort_key}"
    shard_url = shard_manager.get_shard_url(partition_key)
    resp = requests.delete(f"{shard_url}/records/{key}")
    return {"status": "deleted"}
