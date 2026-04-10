"""Place_Service — Google Places API integration with Redis caching.

Queries Google Places Nearby Search for hotels and restaurants,
returns top 3 sorted by rating, caches in Redis with 24 h TTL.

Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 13.1, 13.2, 13.3
"""

from __future__ import annotations

import hashlib
import json
import logging
from typing import Literal

import httpx

from backend.config import settings
from backend.models.places import PlaceQuery, PlaceResult, PlacesResponse
from backend.services.cache import get_cached, set_cached

logger = logging.getLogger(__name__)

NEARBY_SEARCH_URL = "https://maps.googleapis.com/maps/api/place/nearbysearch/json"

# Map user-facing price strings to Google's 0-4 integer levels.
_PRICE_MAP: dict[str, int] = {
    "$": 1,
    "$$": 2,
    "$$$": 3,
    "$$$$": 4,
}

# Reverse map for display.
_PRICE_DISPLAY: dict[int, str] = {v: k for k, v in _PRICE_MAP.items()}

TOP_N = 3


def _cache_key(place_type: str, query: PlaceQuery) -> str:
    """Build a deterministic Redis key from query params (Req 13.1)."""
    raw = json.dumps(
        {
            "type": place_type,
            "lat": query.latitude,
            "lng": query.longitude,
            "radius": query.radius,
            "price": query.price_range,
            "vibe": query.vibe,
            "cuisine": query.cuisine,
        },
        sort_keys=True,
    )
    h = hashlib.sha256(raw.encode()).hexdigest()[:16]
    return f"places:{place_type}:{h}"


def _build_params(
    place_type: str,
    query: PlaceQuery,
    *,
    keyword: str | None = None,
    max_price: int | None = None,
) -> dict:
    """Build query-string params for Google Nearby Search."""
    params: dict = {
        "location": f"{query.latitude},{query.longitude}",
        "radius": query.radius,
        "type": place_type,
        "key": settings.google_places_api_key,
    }
    if keyword:
        params["keyword"] = keyword
    if max_price is not None:
        params["maxprice"] = max_price
    return params


def _parse_result(raw: dict) -> PlaceResult:
    """Convert a single Google Places result dict into a PlaceResult."""
    price_int = raw.get("price_level")
    price_str = _PRICE_DISPLAY.get(price_int, "") if price_int is not None else ""

    # Build a photo URL if available.
    image_url: str | None = None
    photos = raw.get("photos")
    if photos:
        ref = photos[0].get("photo_reference", "")
        if ref:
            image_url = (
                f"https://maps.googleapis.com/maps/api/place/photo"
                f"?maxwidth=400&photo_reference={ref}"
                f"&key={settings.google_places_api_key}"
            )

    loc = raw.get("geometry", {}).get("location", {})
    return PlaceResult(
        place_id=raw.get("place_id", ""),
        name=raw.get("name", ""),
        rating=raw.get("rating", 0.0),
        price_level=price_str,
        image_url=image_url,
        latitude=loc.get("lat", 0.0),
        longitude=loc.get("lng", 0.0),
    )


async def _fetch_places(
    place_type: str,
    query: PlaceQuery,
    *,
    keyword: str | None = None,
    max_price: int | None = None,
) -> list[dict]:
    """Call Google Nearby Search and return the raw results list."""
    params = _build_params(place_type, query, keyword=keyword, max_price=max_price)
    async with httpx.AsyncClient(timeout=10.0) as client:
        resp = await client.get(NEARBY_SEARCH_URL, params=params)
        resp.raise_for_status()
        data = resp.json()
    status = data.get("status", "")
    if status not in ("OK", "ZERO_RESULTS"):
        logger.error("Google Places API error: %s – %s", status, data.get("error_message", ""))
        raise RuntimeError(f"Google Places API returned status {status}")
    return data.get("results", [])


async def _search_places(
    place_type: Literal["lodging", "restaurant"],
    query: PlaceQuery,
) -> PlacesResponse:
    """Core search logic shared by hotels and restaurants.

    1. Check Redis cache (Req 13.1, 13.2).
    2. On miss, call Google Places API (Req 13.3).
    3. Exclude previously-shown IDs (Req 7.4).
    4. Sort by rating, return top 3 (Req 7.1, 7.2).
    5. If empty after filtering, relax filters and flag broadening (Req 7.5).
    """
    cache_k = _cache_key(place_type, query)
    cached = get_cached(cache_k)

    if cached is not None:
        all_results = cached
    else:
        # Determine keyword / price filter.
        keyword: str | None = None
        if place_type == "lodging" and query.vibe:
            keyword = query.vibe
        elif place_type == "restaurant" and query.cuisine:
            keyword = query.cuisine

        max_price = _PRICE_MAP.get(query.price_range) if query.price_range else None

        raw = await _fetch_places(place_type, query, keyword=keyword, max_price=max_price)
        all_results = [_parse_result(r).model_dump() for r in raw]
        set_cached(cache_k, all_results)  # 24 h TTL (default)

    # Exclude already-shown IDs (refresh support, Req 7.4).
    excluded = set(query.excluded_ids)
    filtered = [r for r in all_results if r["place_id"] not in excluded]

    # Sort by rating descending, take top 3.
    filtered.sort(key=lambda r: r.get("rating", 0), reverse=True)
    top = filtered[:TOP_N]

    filters_broadened = False

    if not top:
        # Relax filters: drop keyword and price, re-fetch (Req 7.5).
        raw_broad = await _fetch_places(place_type, query)
        broad = [_parse_result(r).model_dump() for r in raw_broad]
        broad = [r for r in broad if r["place_id"] not in excluded]
        broad.sort(key=lambda r: r.get("rating", 0), reverse=True)
        top = broad[:TOP_N]
        filters_broadened = True

    return PlacesResponse(
        results=[PlaceResult(**r) for r in top],
        filters_broadened=filters_broadened,
    )


async def get_hotels(query: PlaceQuery) -> PlacesResponse:
    """Return top 3 hotel recommendations (Req 7.1)."""
    return await _search_places("lodging", query)


async def get_restaurants(query: PlaceQuery) -> PlacesResponse:
    """Return top 3 restaurant recommendations (Req 7.2)."""
    return await _search_places("restaurant", query)
