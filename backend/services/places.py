"""Place_Service — Google Places → Foursquare → OpenAI fallback chain.

Uses Google Places API as primary source (when API key configured),
Foursquare as secondary, and OpenAI as tertiary fallback.

Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 10.3, 10.4
"""

from __future__ import annotations

import hashlib
import json
import logging
from typing import Any, Literal

import httpx

from backend.config import settings
from backend.models.places import PlaceQuery, PlaceResult, PlacesResponse
from backend.services.cache import get_cached, set_cached
from backend.services.google_places import search_nearby_places as google_search

logger = logging.getLogger(__name__)

FOURSQUARE_SEARCH_URL = "https://api.foursquare.com/v3/places/search"
OPENAI_CHAT_URL = "https://api.openai.com/v1/chat/completions"
TOP_N = 5
CACHE_TTL = 86400  # 24 hours

# Tier-to-range mapping tables (5 tiers: Budget through Luxury)
RESTAURANT_TIER_RANGES: dict[str, tuple[float, float]] = {
    "$": (8.0, 15.0),
    "$$": (15.0, 30.0),
    "$$$": (30.0, 50.0),
    "$$$$": (50.0, 80.0),
    "$$$$$": (80.0, 150.0),
}

HOTEL_TIER_RANGES: dict[str, tuple[float, float]] = {
    "$": (40.0, 80.0),
    "$$": (80.0, 150.0),
    "$$$": (150.0, 250.0),
    "$$$$": (250.0, 400.0),
    "$$$$$": (400.0, 800.0),
}

# Mid-tier defaults for unrecognized strings
RESTAURANT_MID_TIER = (30.0, 50.0)
HOTEL_MID_TIER = (150.0, 250.0)


# Budget tier to Foursquare min_price/max_price mapping (1-4 scale)
BUDGET_TO_FSQ_PRICE: dict[str, tuple[int, int]] = {
    "$": (1, 1),
    "$$": (1, 2),
    "$$$": (2, 3),
    "$$$$": (3, 4),
    "$$$$$": (4, 4),
}


def _build_cache_key(place_type: str, query: PlaceQuery) -> str:
    """Build a deterministic cache key for place queries."""
    raw = json.dumps(
        {
            "type": place_type,
            "lat": round(query.latitude, 5),
            "lng": round(query.longitude, 5),
            "radius": query.radius,
            "price_range": query.price_range or "",
            "vibe": query.vibe or "",
            "cuisine": query.cuisine or "",
            "excluded": sorted(query.excluded_ids),
        },
        sort_keys=True,
    )
    h = hashlib.sha256(raw.encode()).hexdigest()[:16]
    return f"places:{place_type}:{h}"


def _google_to_place_result(g) -> PlaceResult:
    """Convert a GooglePlaceResult to a PlaceResult."""
    photo_url = None
    if g.photo_references:
        # Use first photo reference as image URL placeholder
        photo_url = g.photo_references[0] if g.photo_references else None

    return PlaceResult(
        place_id=g.place_id,
        name=g.name,
        rating=g.rating,
        price_level=g.price_level_display,
        image_url=photo_url,
        latitude=g.latitude,
        longitude=g.longitude,
        rating_source="google",
        review_count=g.user_ratings_total,
        price_range_min=g.price_range_min,
        price_range_max=g.price_range_max,
    )


async def _search_foursquare(
    place_type: Literal["hotel", "restaurant"],
    query: PlaceQuery,
) -> list[PlaceResult]:
    """Search Foursquare Places API as secondary fallback."""
    if not settings.foursquare_api_key:
        return []

    category_map = {
        "hotel": "19014",  # Hotel category
        "restaurant": "13065",  # Restaurant category
    }
    category_id = category_map.get(place_type, "13065")

    params: dict[str, Any] = {
        "ll": f"{query.latitude},{query.longitude}",
        "radius": query.radius,
        "categories": category_id,
        "limit": TOP_N,
        "sort": "RELEVANCE",
    }

    if query.cuisine:
        params["query"] = query.cuisine

    headers = {
        "Authorization": settings.foursquare_api_key,
        "Accept": "application/json",
    }

    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.get(FOURSQUARE_SEARCH_URL, headers=headers, params=params)
            resp.raise_for_status()

        data = resp.json()
        results: list[PlaceResult] = []
        for place in data.get("results", [])[:TOP_N]:
            fsq_id = place.get("fsq_id", "")
            if fsq_id in query.excluded_ids:
                continue
            geo = place.get("geocodes", {}).get("main", {})
            results.append(
                PlaceResult(
                    place_id=fsq_id,
                    name=place.get("name", ""),
                    rating=0.0,
                    price_level=query.price_range or "",
                    latitude=float(geo.get("latitude", 0.0)),
                    longitude=float(geo.get("longitude", 0.0)),
                    rating_source="foursquare",
                )
            )
        return results

    except Exception as exc:
        logger.warning("Foursquare search failed: %s", exc)
        return []


async def _search_openai(
    place_type: Literal["hotel", "restaurant"],
    query: PlaceQuery,
) -> list[PlaceResult]:
    """Generate place recommendations via OpenAI as tertiary fallback."""
    budget_str = query.price_range or "$$"
    cuisine_str = f" specializing in {query.cuisine}" if query.cuisine else ""
    vibe_str = f" with a {query.vibe} vibe" if query.vibe else ""

    prompt = (
        f"Suggest {TOP_N} real {place_type}s near coordinates "
        f"({query.latitude}, {query.longitude}){cuisine_str}{vibe_str} "
        f"in the {budget_str} price range. "
        f"Return ONLY a JSON array with objects containing: "
        f"name, latitude, longitude, price_level (as dollar signs)."
    )

    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.post(
                OPENAI_CHAT_URL,
                headers={
                    "Authorization": f"Bearer {settings.openai_api_key}",
                    "Content-Type": "application/json",
                },
                json={
                    "model": "gpt-4o-mini",
                    "temperature": 0.7,
                    "messages": [
                        {
                            "role": "system",
                            "content": "You are a travel recommendation engine. Return only valid JSON.",
                        },
                        {"role": "user", "content": prompt},
                    ],
                },
            )
            resp.raise_for_status()

        content = resp.json()["choices"][0]["message"]["content"].strip()
        if content.startswith("```"):
            content = content.split("\n", 1)[1] if "\n" in content else content[3:]
            if content.endswith("```"):
                content = content[:-3]

        items = json.loads(content)
        results: list[PlaceResult] = []
        for item in items[:TOP_N]:
            results.append(
                PlaceResult(
                    place_id=f"openai-{hashlib.md5(item.get('name', '').encode()).hexdigest()[:8]}",
                    name=item.get("name", ""),
                    rating=0.0,
                    price_level=item.get("price_level", budget_str),
                    latitude=float(item.get("latitude", 0.0)),
                    longitude=float(item.get("longitude", 0.0)),
                    rating_source="openai",
                )
            )
        return results

    except Exception as exc:
        logger.warning("OpenAI place generation failed: %s", exc)
        return []


async def _search_places(
    place_type: Literal["hotel", "restaurant"],
    query: PlaceQuery,
) -> PlacesResponse:
    """Search for places using the fallback chain: Google → Foursquare → OpenAI.

    Requirements: 10.3, 10.4
    """
    cache_key = _build_cache_key(place_type, query)
    cached = get_cached(cache_key)
    if cached is not None:
        return PlacesResponse(**cached)

    google_type = "lodging" if place_type == "hotel" else "restaurant"
    results: list[PlaceResult] = []
    filters_broadened = False

    # 1. Try Google Places (primary)
    if settings.google_places_api_key:
        try:
            google_results = await google_search(
                place_type=google_type,
                latitude=query.latitude,
                longitude=query.longitude,
                radius=query.radius,
                budget_tier=query.price_range,
                keyword=query.cuisine or query.vibe,
            )
            results = [
                r for r in [_google_to_place_result(g) for g in google_results]
                if r.place_id not in query.excluded_ids
            ][:TOP_N]
        except Exception as exc:
            logger.warning("Google Places failed, trying Foursquare: %s", exc)

    # 2. Fallback to Foursquare (secondary)
    if not results:
        results = await _search_foursquare(place_type, query)

    # 3. Fallback to OpenAI (tertiary)
    if not results:
        results = await _search_openai(place_type, query)

    # 4. All sources failed
    if not results:
        filters_broadened = True

    response = PlacesResponse(results=results, filters_broadened=filters_broadened)

    # Cache successful results
    if results:
        set_cached(cache_key, response.model_dump(), ttl=CACHE_TTL)

    return response


async def get_hotels(query: PlaceQuery) -> PlacesResponse:
    """Get hotel recommendations (Req 7.1).

    Uses Google Places → Foursquare → OpenAI fallback chain.
    Accepts budget_tier via query.price_range.
    """
    return await _search_places("hotel", query)


async def get_restaurants(query: PlaceQuery) -> PlacesResponse:
    """Get restaurant recommendations (Req 7.2).

    Uses Google Places → Foursquare → OpenAI fallback chain.
    Accepts budget_tier via query.price_range.
    """
    return await _search_places("restaurant", query)
