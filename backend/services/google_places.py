"""Google Places Service — integration with Google Places API (New).

Provides nearby search and place details with Redis caching.
Uses the new Google Places API endpoint (places.googleapis.com/v1).

Requirements: 10.1, 10.2, 11.1, 11.2, 11.3
"""

from __future__ import annotations

import hashlib
import json
import logging
from typing import Any

import httpx

from backend.config import settings
from backend.models.places import GooglePlaceResult
from backend.services.cache import get_cached, set_cached

logger = logging.getLogger(__name__)

NEARBY_SEARCH_URL = "https://places.googleapis.com/v1/places:searchNearby"
PLACE_DETAILS_URL = "https://places.googleapis.com/v1/places"
CACHE_TTL = 86400  # 24 hours

# Google price_level (0-4) to dollar-sign display mapping
PRICE_LEVEL_DISPLAY: dict[int, str] = {
    0: "$",
    1: "$",
    2: "$$",
    3: "$$$",
    4: "$$$$",
}

# Budget tier to Google price_level range mapping
BUDGET_TO_PRICE_LEVELS: dict[str, list[int]] = {
    "$": [0, 1],
    "$$": [1, 2],
    "$$$": [2, 3],
    "$$$$": [3, 4],
    "$$$$$": [4],
}


def map_price_level(price_level: int | None) -> str:
    """Map Google price_level (0-4) to dollar-sign display string.

    Requirements: 10.2
    """
    if price_level is None:
        return ""
    return PRICE_LEVEL_DISPLAY.get(price_level, "")


def _build_cache_key(place_type: str, latitude: float, longitude: float,
                     radius: int, budget_tier: str | None,
                     keyword: str | None) -> str:
    """Build a deterministic cache key for Google Places queries.

    Key format: gplaces:{type}:{hash(params)}
    Requirements: 11.3
    """
    raw = json.dumps(
        {
            "type": place_type,
            "lat": round(latitude, 5),
            "lng": round(longitude, 5),
            "radius": radius,
            "budget": budget_tier or "",
            "keyword": keyword or "",
        },
        sort_keys=True,
    )
    h = hashlib.sha256(raw.encode()).hexdigest()[:16]
    return f"gplaces:{place_type}:{h}"


def _parse_place_result(place: dict[str, Any]) -> GooglePlaceResult:
    """Parse a single place from the Google Places API response."""
    location = place.get("location", {})
    price_level_int = place.get("priceLevel")

    # Map string price levels from the new API
    price_level_map = {
        "PRICE_LEVEL_FREE": 0,
        "PRICE_LEVEL_INEXPENSIVE": 1,
        "PRICE_LEVEL_MODERATE": 2,
        "PRICE_LEVEL_EXPENSIVE": 3,
        "PRICE_LEVEL_VERY_EXPENSIVE": 4,
    }
    if isinstance(price_level_int, str):
        price_level_int = price_level_map.get(price_level_int)

    # Determine if we have real pricing data
    has_real_pricing = price_level_int is not None

    # Extract photo references
    photos = place.get("photos", [])
    photo_refs = [p.get("name", "") for p in photos if p.get("name")]

    # Opening hours
    opening_hours = None
    if place.get("regularOpeningHours"):
        opening_hours = place["regularOpeningHours"]

    return GooglePlaceResult(
        place_id=place.get("id", place.get("name", "")),
        name=place.get("displayName", {}).get("text", ""),
        rating=float(place.get("rating", 0.0)),
        user_ratings_total=int(place.get("userRatingCount", 0)),
        price_level=price_level_int,
        price_level_display=map_price_level(price_level_int),
        photo_references=photo_refs,
        latitude=float(location.get("latitude", 0.0)),
        longitude=float(location.get("longitude", 0.0)),
        formatted_address=place.get("formattedAddress", ""),
        opening_hours=opening_hours,
        is_estimated=not has_real_pricing,
    )


async def search_nearby_places(
    place_type: str,
    latitude: float,
    longitude: float,
    radius: int = 5000,
    budget_tier: str | None = None,
    keyword: str | None = None,
) -> list[GooglePlaceResult]:
    """Search Google Places Nearby Search API with caching.

    Args:
        place_type: "lodging" or "restaurant"
        latitude: Search center latitude
        longitude: Search center longitude
        radius: Search radius in meters (default 5000)
        budget_tier: Budget tier string ($-$$$$$)
        keyword: Optional keyword filter

    Returns:
        List of GooglePlaceResult objects

    Requirements: 10.1, 10.2, 11.1, 11.2, 11.3
    """
    if not settings.google_places_api_key:
        logger.warning("Google Places API key not configured")
        return []

    cache_key = _build_cache_key(place_type, latitude, longitude, radius, budget_tier, keyword)
    cached = get_cached(cache_key)
    if cached is not None:
        logger.info("Google Places cache hit: %s", cache_key)
        return [GooglePlaceResult(**r) for r in cached]

    # Map place_type to Google Places included types
    type_mapping = {
        "lodging": ["lodging"],
        "restaurant": ["restaurant"],
    }
    included_types = type_mapping.get(place_type, ["restaurant"])

    # Build request body for the new API
    body: dict[str, Any] = {
        "includedTypes": included_types,
        "maxResultCount": 10,
        "locationRestriction": {
            "circle": {
                "center": {"latitude": latitude, "longitude": longitude},
                "radius": float(radius),
            }
        },
    }

    # Add price level filter based on budget tier
    if budget_tier and budget_tier in BUDGET_TO_PRICE_LEVELS:
        price_levels = BUDGET_TO_PRICE_LEVELS[budget_tier]
        price_level_strings = {
            0: "PRICE_LEVEL_FREE",
            1: "PRICE_LEVEL_INEXPENSIVE",
            2: "PRICE_LEVEL_MODERATE",
            3: "PRICE_LEVEL_EXPENSIVE",
            4: "PRICE_LEVEL_VERY_EXPENSIVE",
        }
        body["includedPrimaryTypes"] = included_types

    headers = {
        "X-Goog-Api-Key": settings.google_places_api_key,
        "X-Goog-FieldMask": (
            "places.id,places.displayName,places.rating,places.userRatingCount,"
            "places.priceLevel,places.photos,places.location,places.formattedAddress,"
            "places.regularOpeningHours"
        ),
        "Content-Type": "application/json",
    }

    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.post(
                NEARBY_SEARCH_URL,
                headers=headers,
                json=body,
            )
            resp.raise_for_status()

        data = resp.json()
        places = data.get("places", [])
        results = [_parse_place_result(p) for p in places]

        # Cache results
        if results:
            set_cached(cache_key, [r.model_dump() for r in results], ttl=CACHE_TTL)

        return results

    except Exception as exc:
        logger.warning("Google Places nearby search failed: %s", exc)
        return []


async def get_place_details(place_id: str) -> GooglePlaceResult | None:
    """Fetch detailed info for a specific place (photos, hours, pricing).

    Requirements: 10.1, 10.2
    """
    if not settings.google_places_api_key:
        return None

    cache_key = f"gplaces:detail:{place_id}"
    cached = get_cached(cache_key)
    if cached is not None:
        return GooglePlaceResult(**cached)

    url = f"{PLACE_DETAILS_URL}/{place_id}"
    headers = {
        "X-Goog-Api-Key": settings.google_places_api_key,
        "X-Goog-FieldMask": (
            "id,displayName,rating,userRatingCount,priceLevel,"
            "photos,location,formattedAddress,regularOpeningHours"
        ),
    }

    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.get(url, headers=headers)
            resp.raise_for_status()

        data = resp.json()
        result = _parse_place_result(data)

        # Cache the detail
        set_cached(cache_key, result.model_dump(), ttl=CACHE_TTL)
        return result

    except Exception as exc:
        logger.warning("Google Places detail fetch failed for %s: %s", place_id, exc)
        return None
