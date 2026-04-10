"""Search service — Google Places Autocomplete for destination suggestions.

Uses Places Autocomplete API to find city matches, then Places Details
to resolve lat/lng for each suggestion.  Results are cached in Redis.

Requirements: 2.2
"""

from __future__ import annotations

import hashlib
import json
import logging
from typing import Any

import httpx

from backend.config import settings
from backend.services.cache import get_cached, set_cached

logger = logging.getLogger(__name__)

AUTOCOMPLETE_URL = (
    "https://maps.googleapis.com/maps/api/place/autocomplete/json"
)
PLACE_DETAILS_URL = (
    "https://maps.googleapis.com/maps/api/place/details/json"
)

CACHE_TTL = 86400  # 24 hours


def _cache_key(query: str) -> str:
    """Deterministic Redis key for a destination search query."""
    h = hashlib.sha256(query.lower().strip().encode()).hexdigest()[:16]
    return f"search:destinations:{h}"


async def search_destinations(query: str) -> list[dict[str, Any]]:
    """Return city suggestions matching *query*.

    Flow:
    1. Check Redis cache for this query.
    2. On miss, call Google Places Autocomplete (types=(cities)).
    3. For each prediction, call Places Details to get lat/lng.
    4. Cache the assembled results and return them.
    """
    cache_k = _cache_key(query)
    cached = get_cached(cache_k)
    if cached is not None:
        return cached

    # Step 1 — Autocomplete
    async with httpx.AsyncClient(timeout=10.0) as client:
        ac_resp = await client.get(
            AUTOCOMPLETE_URL,
            params={
                "input": query,
                "types": "(cities)",
                "key": settings.google_places_api_key,
            },
        )
        ac_resp.raise_for_status()
        ac_data = ac_resp.json()

    status = ac_data.get("status", "")
    if status not in ("OK", "ZERO_RESULTS"):
        logger.error(
            "Places Autocomplete error: %s – %s",
            status,
            ac_data.get("error_message", ""),
        )
        raise RuntimeError(f"Google Places Autocomplete returned status {status}")

    predictions = ac_data.get("predictions", [])
    if not predictions:
        set_cached(cache_k, [], CACHE_TTL)
        return []

    # Step 2 — Fetch lat/lng via Place Details for each prediction
    results: list[dict[str, Any]] = []
    async with httpx.AsyncClient(timeout=10.0) as client:
        for pred in predictions[:5]:  # cap at 5 suggestions
            place_id = pred.get("place_id", "")
            detail_resp = await client.get(
                PLACE_DETAILS_URL,
                params={
                    "place_id": place_id,
                    "fields": "geometry,name",
                    "key": settings.google_places_api_key,
                },
            )
            detail_resp.raise_for_status()
            detail_data = detail_resp.json()

            result = detail_data.get("result", {})
            location = result.get("geometry", {}).get("location", {})

            results.append(
                {
                    "name": pred.get("description", ""),
                    "place_id": place_id,
                    "latitude": location.get("lat", 0.0),
                    "longitude": location.get("lng", 0.0),
                }
            )

    set_cached(cache_k, results, CACHE_TTL)
    return results
