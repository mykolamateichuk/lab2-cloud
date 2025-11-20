import hashlib
import bisect
from typing import List

class ShardManager:
    def __init__(self, shard_urls: List[str], replicas=100):
        self.replicas = replicas
        self.ring = {}  # virtual_node_hash -> shard_url
        self.sorted_keys = []  # sorted list of virtual node hashes

        for url in shard_urls:
            self.add_shard(url)

    def _hash(self, key: str) -> int:
        """Return a consistent integer hash."""
        return int(hashlib.md5(key.encode()).hexdigest(), 16)

    def add_shard(self, url: str):
        for i in range(self.replicas):
            virtual_node = f"{url}#{i}"
            key = self._hash(virtual_node)
            self.ring[key] = url
        self.sorted_keys = sorted(self.ring.keys())

    def remove_shard(self, url: str):
        keys_to_remove = []
        for i in range(self.replicas):
            virtual_node = f"{url}#{i}"
            key = self._hash(virtual_node)
            if key in self.ring and self.ring[key] == url:
                keys_to_remove.append(key)
        for key in keys_to_remove:
            del self.ring[key]
        self.sorted_keys = sorted(self.ring.keys())

    def get_shard_url(self, partition_key: str) -> str:
        if not self.ring:
            raise Exception("No shards available")
        key = self._hash(partition_key)
        idx = bisect.bisect(self.sorted_keys, key)
        # Wrap around if needed
        selected_key = self.sorted_keys[idx % len(self.sorted_keys)]
        return self.ring[selected_key]