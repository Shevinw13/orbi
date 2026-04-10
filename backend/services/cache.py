"""Redis cache utility backed by Upstash Redis.

Provides get_cached / set_cached helpers with JSON serialization and TTL support.
Requirements: 13.1, 13.2, 13.3
"""

from __future__ import annotations

import json
from typing import Any, Optional

import redis

from backend.config import settings

DEFAULT_TTL = 86400  # 24 hours in seconds

_redis_client: Optional[redis.Redis] = None


def get_redis_client() -> redis.Redis:
    """Return a lazily-initialised Redis client connected to Upstash."""
    global _redis_client
    if _redis_client is None:
        _redis_client = redis.from_url(
            settings.upstash_redis_url,
            decode_responses=True,
        )
    return _redis_client


def get_cached(key: str) -> Optional[Any]:
    """Retrieve a cached value by key.

    Returns the deserialised Python object, or None on cache miss or error.
    """
    client = get_redis_client()
    raw = client.get(key)
    if raw is None:
        return None
    return json.loads(raw)


def set_cached(key: str, value: Any, ttl: int = DEFAULT_TTL) -> None:
    """Store a value in the cache with an optional TTL (seconds).

    The value is JSON-serialised before storage.  TTL defaults to 24 hours.
    """
    client = get_redis_client()
    client.set(key, json.dumps(value), ex=ttl)
