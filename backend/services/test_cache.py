"""Unit tests for the cache service with in-memory fallback."""

from __future__ import annotations

import os
import time

os.environ.setdefault("SUPABASE_URL", "https://test.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "test-key")
os.environ.setdefault("OPENAI_API_KEY", "test-openai-key")
os.environ.setdefault("JWT_SECRET", "test-jwt-secret")

from unittest.mock import MagicMock, patch

import pytest

from backend.services.cache import DEFAULT_TTL, get_cached, set_cached, get_redis_client


@pytest.fixture(autouse=True)
def _clear_memory_store():
    """Clear in-memory cache and reset Redis client between tests."""
    from backend.services import cache
    cache._memory_store.clear()
    cache._redis_client = None
    yield
    cache._memory_store.clear()
    cache._redis_client = None


class TestInMemoryFallback:
    """Tests for in-memory cache when Redis is not configured."""

    def test_returns_none_on_cache_miss(self):
        assert get_cached("nonexistent") is None

    def test_roundtrip_dict(self):
        set_cached("k1", {"name": "Tokyo"})
        assert get_cached("k1") == {"name": "Tokyo"}

    def test_roundtrip_list(self):
        set_cached("k2", [1, 2, 3])
        assert get_cached("k2") == [1, 2, 3]

    def test_roundtrip_string(self):
        set_cached("k3", "hello")
        assert get_cached("k3") == "hello"

    def test_ttl_eviction(self):
        """Entries should be evicted after TTL expires."""
        set_cached("expire_me", "value", ttl=1)
        assert get_cached("expire_me") == "value"

        # Simulate time passing
        from backend.services import cache
        key_data = cache._memory_store["expire_me"]
        # Manually set expiry to the past
        cache._memory_store["expire_me"] = (key_data[0], time.time() - 1)
        assert get_cached("expire_me") is None


class TestGetRedisClient:
    """Tests for Redis client initialization."""

    def test_returns_none_when_url_empty(self):
        with patch("backend.services.cache.settings") as mock_settings:
            mock_settings.upstash_redis_url = ""
            from backend.services import cache
            cache._redis_client = None
            result = get_redis_client()
            assert result is None

    def test_returns_client_when_url_set(self):
        with patch("backend.services.cache.settings") as mock_settings:
            mock_settings.upstash_redis_url = "redis://localhost:6379"
            from backend.services import cache
            cache._redis_client = None
            with patch("backend.services.cache.redis.from_url") as mock_from_url:
                mock_client = MagicMock()
                mock_from_url.return_value = mock_client
                result = get_redis_client()
                assert result is mock_client


class TestRedisFallback:
    """Tests for Redis error -> in-memory fallback."""

    def test_get_falls_back_on_redis_error(self):
        """When Redis get raises, should fall back to in-memory."""
        from backend.services import cache

        # Pre-populate in-memory store
        import json
        cache._memory_store["fallback_key"] = (json.dumps("mem_value"), time.time() + 3600)

        mock_redis = MagicMock()
        mock_redis.get.side_effect = Exception("Redis down")

        with patch("backend.services.cache.get_redis_client", return_value=mock_redis):
            result = get_cached("fallback_key")
            assert result == "mem_value"

    def test_set_falls_back_on_redis_error(self):
        """When Redis set raises, should store in memory."""
        from backend.services import cache

        mock_redis = MagicMock()
        mock_redis.set.side_effect = Exception("Redis down")

        with patch("backend.services.cache.get_redis_client", return_value=mock_redis):
            set_cached("fb_key", {"data": 1})

        assert "fb_key" in cache._memory_store
