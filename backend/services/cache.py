"""Cache service with Redis + in-memory fallback.

Uses Upstash Redis when configured, falls back to a Python dict with TTL.
Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7, 5.8
"""

from __future__ import annotations

import json
import logging
import time
from typing import Any, Optional

import redis

from backend.config import settings

logger = logging.getLogger(__name__)

DEFAULT_TTL = 86400  # 24 hours in seconds

_redis_client: Optional[redis.Redis] = None

# In-memory fallback: key -> (json_value, expires_at_timestamp)
_memory_store: dict[str, tuple[str, float]] = {}


def get_redis_client() -> Optional[redis.Redis]:
    """Return a lazily-initialised Redis client, or None when unconfigured."""
    global _redis_client
    if not settings.upstash_redis_url:
        return None
    if _redis_client is None:
        try:
            _redis_client = redis.from_url(
                settings.upstash_redis_url,
                decode_responses=True,
            )
        except Exception:
            logger.warning("Failed to create Redis client, using in-memory fallback")
            return None
    return _redis_client


def get_cached(key: str) -> Optional[Any]:
    """Retrieve a cached value by key.

    Tries Redis first, falls back to in-memory on failure or when unconfigured.
    Returns the deserialised Python object, or None on cache miss.
    """
    client = get_redis_client()
    if client is not None:
        try:
            raw = client.get(key)
            if raw is not None:
                return json.loads(raw)
            # Redis returned None — key doesn't exist in Redis.
            # Don't fall through to memory; treat as a miss.
            return None
        except Exception:
            logger.warning("Redis get failed for key=%s, falling back to memory", key)

    # In-memory fallback
    entry = _memory_store.get(key)
    if entry is None:
        return None
    value, expires_at = entry
    if time.time() > expires_at:
        del _memory_store[key]
        return None
    return json.loads(value)


def set_cached(key: str, value: Any, ttl: int = DEFAULT_TTL) -> None:
    """Store a value in the cache with a TTL (seconds).

    Tries Redis first, falls back to in-memory on failure or when unconfigured.
    """
    serialized = json.dumps(value)
    client = get_redis_client()
    if client is not None:
        try:
            client.set(key, serialized, ex=ttl)
            return
        except Exception:
            logger.warning("Redis set failed for key=%s, falling back to memory", key)

    # In-memory fallback
    _memory_store[key] = (serialized, time.time() + ttl)
