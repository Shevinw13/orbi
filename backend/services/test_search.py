"""Unit tests for the destination search service."""

from __future__ import annotations

import os

# Provide dummy env vars so backend.config.Settings can initialise
os.environ.setdefault("SUPABASE_URL", "https://test.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "test-key")
os.environ.setdefault("UPSTASH_REDIS_URL", "redis://localhost:6379")
os.environ.setdefault("OPENAI_API_KEY", "test-openai-key")
os.environ.setdefault("GOOGLE_PLACES_API_KEY", "test-places-key")
os.environ.setdefault("JWT_SECRET", "test-jwt-secret")

from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from backend.services.search import _cache_key, search_destinations


@pytest.fixture(autouse=True)
def _mock_redis(monkeypatch):
    """Replace Redis with a dict-backed fake."""
    store: dict[str, str] = {}
    mock_client = MagicMock()

    import json

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


# -- Helpers --

AUTOCOMPLETE_OK = {
    "status": "OK",
    "predictions": [
        {"place_id": "ChIJ1", "description": "Tokyo, Japan"},
        {"place_id": "ChIJ2", "description": "Toronto, Canada"},
    ],
}

AUTOCOMPLETE_ZERO = {"status": "ZERO_RESULTS", "predictions": []}

DETAIL_TOKYO = {
    "result": {
        "name": "Tokyo",
        "geometry": {"location": {"lat": 35.6762, "lng": 139.6503}},
    }
}

DETAIL_TORONTO = {
    "result": {
        "name": "Toronto",
        "geometry": {"location": {"lat": 43.6532, "lng": -79.3832}},
    }
}


def _mock_response(json_data, status_code=200):
    resp = MagicMock()
    resp.status_code = status_code
    resp.json.return_value = json_data
    resp.raise_for_status = MagicMock()
    return resp


class TestCacheKey:
    def test_deterministic(self):
        assert _cache_key("tokyo") == _cache_key("tokyo")

    def test_case_insensitive(self):
        assert _cache_key("Tokyo") == _cache_key("tokyo")

    def test_strips_whitespace(self):
        assert _cache_key("  tokyo  ") == _cache_key("tokyo")

    def test_different_queries_differ(self):
        assert _cache_key("tokyo") != _cache_key("paris")


class TestSearchDestinations:
    @pytest.mark.asyncio
    async def test_returns_results_from_api(self):
        """Happy path: autocomplete + details calls produce correct output."""
        responses = [
            _mock_response(AUTOCOMPLETE_OK),
            _mock_response(DETAIL_TOKYO),
            _mock_response(DETAIL_TORONTO),
        ]
        mock_client = AsyncMock()
        mock_client.get = AsyncMock(side_effect=responses)
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("backend.services.search.httpx.AsyncClient", return_value=mock_client):
            results = await search_destinations("tok")

        assert len(results) == 2
        assert results[0]["name"] == "Tokyo, Japan"
        assert results[0]["place_id"] == "ChIJ1"
        assert results[0]["latitude"] == 35.6762
        assert results[1]["name"] == "Toronto, Canada"

    @pytest.mark.asyncio
    async def test_returns_empty_on_zero_results(self):
        mock_client = AsyncMock()
        mock_client.get = AsyncMock(return_value=_mock_response(AUTOCOMPLETE_ZERO))
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("backend.services.search.httpx.AsyncClient", return_value=mock_client):
            results = await search_destinations("xyznonexistent")

        assert results == []

    @pytest.mark.asyncio
    async def test_returns_cached_results(self, _mock_redis):
        """When cache has data, no HTTP calls should be made."""
        import json

        _, store = _mock_redis
        cached_data = [{"name": "Cached City", "place_id": "c1", "latitude": 1.0, "longitude": 2.0}]
        key = _cache_key("cached")
        store[key] = json.dumps(cached_data)

        results = await search_destinations("cached")
        assert len(results) == 1
        assert results[0]["name"] == "Cached City"

    @pytest.mark.asyncio
    async def test_raises_on_api_error(self):
        error_resp = _mock_response({"status": "REQUEST_DENIED", "error_message": "bad key"})
        mock_client = AsyncMock()
        mock_client.get = AsyncMock(return_value=error_resp)
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("backend.services.search.httpx.AsyncClient", return_value=mock_client):
            with pytest.raises(RuntimeError, match="REQUEST_DENIED"):
                await search_destinations("denied")
