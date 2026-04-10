"""Unit tests for the Redis cache utility."""

from unittest.mock import MagicMock, patch

import pytest

from backend.services.cache import DEFAULT_TTL, get_cached, set_cached


@pytest.fixture(autouse=True)
def _mock_redis(monkeypatch):
    """Replace the Redis client with a simple dict-backed fake for every test."""
    store: dict[str, str] = {}
    mock_client = MagicMock()

    def fake_get(key):
        return store.get(key)

    def fake_set(key, value, ex=None):
        store[key] = value

    mock_client.get = MagicMock(side_effect=fake_get)
    mock_client.set = MagicMock(side_effect=fake_set)

    monkeypatch.setattr(
        "backend.services.cache.get_redis_client", lambda: mock_client
    )
    yield mock_client, store


class TestGetCached:
    def test_returns_none_on_cache_miss(self):
        assert get_cached("nonexistent") is None

    def test_returns_deserialized_value(self, _mock_redis):
        _, store = _mock_redis
        store["key1"] = '{"name": "Tokyo"}'
        result = get_cached("key1")
        assert result == {"name": "Tokyo"}

    def test_returns_list_value(self, _mock_redis):
        _, store = _mock_redis
        store["list_key"] = '[1, 2, 3]'
        assert get_cached("list_key") == [1, 2, 3]

    def test_returns_string_value(self, _mock_redis):
        _, store = _mock_redis
        store["str_key"] = '"hello"'
        assert get_cached("str_key") == "hello"


class TestSetCached:
    def test_stores_value_with_default_ttl(self, _mock_redis):
        mock_client, _ = _mock_redis
        set_cached("k", {"a": 1})
        mock_client.set.assert_called_once_with("k", '{"a": 1}', ex=DEFAULT_TTL)

    def test_stores_value_with_custom_ttl(self, _mock_redis):
        mock_client, _ = _mock_redis
        set_cached("k", [1, 2], ttl=60)
        mock_client.set.assert_called_once_with("k", "[1, 2]", ex=60)

    def test_roundtrip(self):
        set_cached("rt", {"x": 42})
        assert get_cached("rt") == {"x": 42}
