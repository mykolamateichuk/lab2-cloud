from hashring import HashRing
from typing import List, Tuple
import hashlib

class ShardManager:
    def __init__(self, shard_urls: List[str]):
        self.shard_urls = shard_urls
        self.ring = HashRing(shard_urls)

    def get_shard_url(self, partition_key: str) -> str:
        # Only hash the partition_key (not sort_key) for sharding
        return self.ring.get_node(partition_key)

    def add_shard(self, url: str):
        self.shard_urls.append(url)
        self.ring = HashRing(self.shard_urls)

    def remove_shard(self, url: str):
        if url in self.shard_urls:
            self.shard_urls.remove(url)
            self.ring = HashRing(self.shard_urls)
