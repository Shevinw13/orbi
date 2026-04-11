"""Unit tests for the destination search service (Nominatim)."""

from __future__ import annotations

import os

# Provide dummy env vars so backend.config.Settings can initialise
os.environ.setdefault("SUPABASE_URL", "https://test.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "test-key")
os.environ.setdefault("OPENAI_API_KEY", "test-openai-key")
os.environ.setdefault("JWT_SECRET", "test-jwt-secret")

from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from backend.services.search import (
    _cache_key,
    search_destinations,
    get_popular_cities,
    POPULAR_CITIES,
)


@pytest.fixture(autouse=True)
def _clear_memory_store():
    """Clear in-memory cache between tests."""
    from backend.services import cache
    cache._memory_store.clear()
    # Ensure Redis client returns None (use in-memory)
    cache._redis_client = None
    yield
    cache._memory_store.clear()


# -- Helpers --

NOMINATIM_RESULTS = [
    {
        "place_id": 123,
        "display_name": "Tokyo, Japan",
        "lat": "35.6762",
        "lon": "139.6503",
        "type": "city",
        "class": "place",
    },
    {
        "place_id": 456,
        "display_name": "Toronto, Ontario, Canada",
        "lat": "43.6532",
        "lon": "-79.3832",
        "type": "city",
        "class": "place",
    },
]

NOMINATIM_MIXED_TYPES = [
    {
        "place_id": 1,
        "display_name": "Tokyo, Japan",
        "lat": "35.6762",
        "lon": "139.6503",
        "type": "city",
        "class": "place",
    },
    {
        "place_id": 2,
        "display_name": "Tokyo Tower",
        "lat": "35.6586",
        "lon": "139.7454",
        "type": "attraction",
        "class": "tourism",
    },
]


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
    async def test_returns_results_from_nominatim(self):
        """Happy path: Nominatim returns city results."""
        mock_client = AsyncMock()
        mock_client.get = AsyncMock(return_value=_mock_response(NOMINATIM_RESULTS))
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("backend.services.search.httpx.AsyncClient", return_value=mock_client):
            results = await search_destinations("tok")

        assert len(results) == 2
        assert results[0]["name"] == "Tokyo, Japan"
        assert results[0]["place_id"] == "123"
        assert results[0]["latitude"] == 35.6762
        assert results[1]["name"] == "Toronto, Ontario, Canada"

    @pytest.mark.asyncio
    async def test_filters_non_city_types(self):
        """Only city/town/administrative/village types should pass."""
        mock_client = AsyncMock()
        mock_client.get = AsyncMock(return_value=_mock_response(NOMINATIM_MIXED_TYPES))
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("backend.services.search.httpx.AsyncClient", return_value=mock_client):
            results = await search_destinations("tokyo")

        assert len(results) == 1
        assert results[0]["name"] == "Tokyo, Japan"

    @pytest.mark.asyncio
    async def test_returns_empty_on_error(self):
        """API errors should return empty list, not raise."""
        mock_client = AsyncMock()
        mock_client.get = AsyncMock(side_effect=Exception("Network error"))
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("backend.services.search.httpx.AsyncClient", return_value=mock_client):
            results = await search_destinations("fail")

        assert results == []

    @pytest.mark.asyncio
    async def test_returns_cached_results(self):
        """When cache has data, no HTTP calls should be made."""
        from backend.services.cache import set_cached

        cached_data = [{"name": "Cached City", "place_id": "c1", "latitude": 1.0, "longitude": 2.0}]
        key = _cache_key("cached")
        set_cached(key, cached_data)

        results = await search_destinations("cached")
        assert len(results) == 1
        assert results[0]["name"] == "Cached City"


class TestGetPopularCities:
    @pytest.mark.asyncio
    async def test_returns_all_cities(self):
        cities = await get_popular_cities()
        assert len(cities) == 40

    @pytest.mark.asyncio
    async def test_cities_have_required_fields(self):
        cities = await get_popular_cities()
        for city in cities:
            assert "name" in city
            assert "latitude" in city
            assert "longitude" in city
            assert "category" in city

    @pytest.mark.asyncio
    async def test_caches_results(self):
        from backend.services.cache import get_cached

        await get_popular_cities()
        cached = get_cached("search:popular_cities:all")
        assert cached is not None
        assert len(cached) == 40

    @pytest.mark.asyncio
    async def test_filter_by_category(self):
        cities = await get_popular_cities(category="Foodie")
        assert len(cities) > 0
        for city in cities:
            assert city["category"] == "Foodie"

    @pytest.mark.asyncio
    async def test_filter_unknown_category_returns_empty(self):
        cities = await get_popular_cities(category="Unknown")
        assert len(cities) == 0
