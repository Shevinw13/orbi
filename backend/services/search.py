"""Search service — Nominatim geocoding for destination suggestions.

Uses OpenStreetMap Nominatim API for free city search.
Results are cached with 24h TTL.

Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 8.4, 10.1, 10.2, 10.3
"""

from __future__ import annotations

import hashlib
import logging
from typing import Any

import httpx

from backend.services.cache import get_cached, set_cached

logger = logging.getLogger(__name__)

NOMINATIM_SEARCH_URL = "https://nominatim.openstreetmap.org/search"
USER_AGENT = "Orbi/1.0 (travel-planner)"

CACHE_TTL = 86400  # 24 hours

# Valid Nominatim result types for city-level results
_CITY_TYPES = {"city", "town", "administrative", "village"}


def _cache_key(query: str) -> str:
    """Deterministic cache key for a destination search query."""
    h = hashlib.sha256(query.lower().strip().encode()).hexdigest()[:16]
    return f"search:destinations:{h}"


async def search_destinations(query: str) -> list[dict[str, Any]]:
    """Return city suggestions matching *query* via Nominatim.

    1. Check cache for this query.
    2. On miss, call Nominatim /search with featuretype=city.
    3. Filter results to city/town/administrative/village types.
    4. Cache and return results.
    Returns empty list on error.
    """
    cache_k = _cache_key(query)
    cached = get_cached(cache_k)
    if cached is not None:
        return cached

    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.get(
                NOMINATIM_SEARCH_URL,
                params={
                    "q": query,
                    "format": "json",
                    "addressdetails": "1",
                    "featuretype": "city",
                    "limit": "5",
                },
                headers={"User-Agent": USER_AGENT},
            )
            resp.raise_for_status()
            data = resp.json()
    except Exception:
        logger.warning("Nominatim request failed for query=%s", query)
        return []

    results = [
        {
            "name": item.get("display_name", ""),
            "place_id": str(item.get("place_id", "")),
            "latitude": float(item.get("lat", 0)),
            "longitude": float(item.get("lon", 0)),
        }
        for item in data
        if item.get("type") in _CITY_TYPES or item.get("class") == "place"
    ]

    set_cached(cache_k, results, CACHE_TTL)
    return results


# ---------------------------------------------------------------------------
# Popular Cities (Task 4.2)
# ---------------------------------------------------------------------------

POPULAR_CITIES_CACHE_KEY = "search:popular_cities"
POPULAR_CITIES_TTL = 604800  # 7 days

POPULAR_CITIES: list[dict[str, Any]] = [
    {"name": "Tokyo, Japan", "latitude": 35.6762, "longitude": 139.6503},
    {"name": "Paris, France", "latitude": 48.8566, "longitude": 2.3522},
    {"name": "London, UK", "latitude": 51.5074, "longitude": -0.1278},
    {"name": "New York, USA", "latitude": 40.7128, "longitude": -74.0060},
    {"name": "Rome, Italy", "latitude": 41.9028, "longitude": 12.4964},
    {"name": "Barcelona, Spain", "latitude": 41.3851, "longitude": 2.1734},
    {"name": "Bangkok, Thailand", "latitude": 13.7563, "longitude": 100.5018},
    {"name": "Dubai, UAE", "latitude": 25.2048, "longitude": 55.2708},
    {"name": "Istanbul, Turkey", "latitude": 41.0082, "longitude": 28.9784},
    {"name": "Sydney, Australia", "latitude": -33.8688, "longitude": 151.2093},
    {"name": "Singapore", "latitude": 1.3521, "longitude": 103.8198},
    {"name": "Amsterdam, Netherlands", "latitude": 52.3676, "longitude": 4.9041},
    {"name": "Seoul, South Korea", "latitude": 37.5665, "longitude": 126.9780},
    {"name": "Lisbon, Portugal", "latitude": 38.7223, "longitude": -9.1393},
    {"name": "Prague, Czech Republic", "latitude": 50.0755, "longitude": 14.4378},
    {"name": "Bali, Indonesia", "latitude": -8.3405, "longitude": 115.0920},
    {"name": "Cape Town, South Africa", "latitude": -33.9249, "longitude": 18.4241},
    {"name": "Rio de Janeiro, Brazil", "latitude": -22.9068, "longitude": -43.1729},
    {"name": "Marrakech, Morocco", "latitude": 31.6295, "longitude": -7.9811},
    {"name": "Kyoto, Japan", "latitude": 35.0116, "longitude": 135.7681},
    {"name": "Buenos Aires, Argentina", "latitude": -34.6037, "longitude": -58.3816},
    {"name": "Mexico City, Mexico", "latitude": 19.4326, "longitude": -99.1332},
    {"name": "Cairo, Egypt", "latitude": 30.0444, "longitude": 31.2357},
    {"name": "Mumbai, India", "latitude": 19.0760, "longitude": 72.8777},
    {"name": "Athens, Greece", "latitude": 37.9838, "longitude": 23.7275},
    {"name": "Vienna, Austria", "latitude": 48.2082, "longitude": 16.3738},
    {"name": "Berlin, Germany", "latitude": 52.5200, "longitude": 13.4050},
    {"name": "Havana, Cuba", "latitude": 23.1136, "longitude": -82.3666},
    {"name": "Reykjavik, Iceland", "latitude": 64.1466, "longitude": -21.9426},
    {"name": "Santorini, Greece", "latitude": 36.3932, "longitude": 25.4615},
    {"name": "Cancun, Mexico", "latitude": 21.1619, "longitude": -86.8515},
    {"name": "Maldives", "latitude": 3.2028, "longitude": 73.2207},
    {"name": "Petra, Jordan", "latitude": 30.3285, "longitude": 35.4444},
    {"name": "Machu Picchu, Peru", "latitude": -13.1631, "longitude": -72.5450},
    {"name": "Queenstown, New Zealand", "latitude": -45.0312, "longitude": 168.6626},
    {"name": "Dubrovnik, Croatia", "latitude": 42.6507, "longitude": 18.0944},
    {"name": "Hanoi, Vietnam", "latitude": 21.0278, "longitude": 105.8342},
    {"name": "Nairobi, Kenya", "latitude": -1.2921, "longitude": 36.8219},
    {"name": "Zanzibar, Tanzania", "latitude": -6.1659, "longitude": 39.2026},
    {"name": "Cartagena, Colombia", "latitude": 10.3910, "longitude": -75.5364},
]


async def get_popular_cities() -> list[dict[str, Any]]:
    """Return curated list of popular travel cities with 7-day cache."""
    cached = get_cached(POPULAR_CITIES_CACHE_KEY)
    if cached is not None:
        return cached
    set_cached(POPULAR_CITIES_CACHE_KEY, POPULAR_CITIES, ttl=POPULAR_CITIES_TTL)
    return POPULAR_CITIES
