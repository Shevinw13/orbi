"""Place_Service — Foursquare with OpenAI fallback.

Uses Foursquare Places API when a key is configured, otherwise uses
OpenAI to generate realistic place recommendations. Results cached 24h.
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

logger = logging.getLogger(__name__)

FOURSQUARE_SEARCH_URL = "https://api.foursquare.com/v3/places/search"
TOP_N = 3


def _use_foursquare() -> bool:
    return bool(settings.foursquare_api_key)


def _cache_key(place_type: str, query: PlaceQuery) -> str:
    raw = json.dumps(
        {"type": place_type, "lat": query.latitude, "lng": query.longitude,
         "radius": query.radius, "price": query.price_range,
         "vibe": query.vibe, "cuisine": query.cuisine},
        sort_keys=True,
    )
    h = hashlib.sha256(raw.encode()).hexdigest()[:16]
    return f"places:{place_type}:{h}"


async def _fetch_foursquare(place_type: str, query: PlaceQuery, keyword: str | None = None) -> list[dict[str, Any]]:
    categories = "19014" if place_type == "lodging" else "13000"
    params: dict[str, Any] = {
        "ll": f"{query.latitude},{query.longitude}",
        "radius": query.radius,
        "categories": categories,
        "limit": 10,
    }
    if keyword:
        params["query"] = keyword
    headers = {"Authorization": settings.foursquare_api_key, "Accept": "application/json"}
    async with httpx.AsyncClient(timeout=10.0) as client:
        resp = await client.get(FOURSQUARE_SEARCH_URL, params=params, headers=headers)
        resp.raise_for_status()
    return resp.json().get("results", [])


def _parse_foursquare_result(venue: dict[str, Any]) -> PlaceResult:
    location = venue.get("location", {})
    return PlaceResult(
        place_id=venue.get("fsq_id", ""),
        name=venue.get("name", ""),
        rating=float(venue.get("rating", 0.0)),
        price_level="",
        image_url=None,
        latitude=float(location.get("latitude", 0.0)),
        longitude=float(location.get("longitude", 0.0)),
    )


async def _fetch_openai_places(place_type: str, query: PlaceQuery) -> list[dict[str, Any]]:
    """Use OpenAI to generate realistic place recommendations."""
    kind = "hotels" if place_type == "lodging" else "restaurants"
    price_hint = f" in the {query.price_range} price range" if query.price_range else ""
    cuisine_hint = f" specializing in {query.cuisine} cuisine" if query.cuisine else ""
    vibe_hint = f" with a {query.vibe} vibe" if query.vibe else ""

    prompt = (
        f"Return a JSON array of 6 real {kind}{price_hint}{cuisine_hint}{vibe_hint} "
        f"near latitude {query.latitude}, longitude {query.longitude}. "
        f"Each object must have: name (string), rating (number 1-5), "
        f"price_level (string like $ or $$), latitude (number), longitude (number). "
        f"Only return the JSON array, no other text."
    )

    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.post(
                "https://api.openai.com/v1/chat/completions",
                headers={
                    "Authorization": f"Bearer {settings.openai_api_key}",
                    "Content-Type": "application/json",
                },
                json={
                    "model": "gpt-4o-mini",
                    "temperature": 0.7,
                    "messages": [
                        {"role": "system", "content": "You are a travel recommendation engine. Return only valid JSON arrays."},
                        {"role": "user", "content": prompt},
                    ],
                },
            )
            resp.raise_for_status()
            content = resp.json()["choices"][0]["message"]["content"].strip()
            # Strip markdown fences if present
            if content.startswith("```"):
                content = content.split("\n", 1)[1] if "\n" in content else content[3:]
                if content.endswith("```"):
                    content = content[:-3]
            places = json.loads(content)
            return [
                {
                    "place_id": f"ai-{i}-{p.get('name', '').replace(' ', '-')[:20]}",
                    "name": p.get("name", ""),
                    "rating": float(p.get("rating", 4.0)),
                    "price_level": p.get("price_level", "$$"),
                    "image_url": None,
                    "latitude": float(p.get("latitude", query.latitude)),
                    "longitude": float(p.get("longitude", query.longitude)),
                }
                for i, p in enumerate(places)
            ]
    except Exception as e:
        logger.warning("OpenAI places fallback failed: %s", e)
        return []


async def _search_places(place_type: Literal["lodging", "restaurant"], query: PlaceQuery) -> PlacesResponse:
    cache_k = _cache_key(place_type, query)
    cached = get_cached(cache_k)

    if cached is not None:
        all_results = cached
    else:
        keyword: str | None = None
        if place_type == "lodging" and query.vibe:
            keyword = query.vibe
        elif place_type == "restaurant" and query.cuisine:
            keyword = query.cuisine

        try:
            if _use_foursquare():
                raw = await _fetch_foursquare(place_type, query, keyword=keyword)
                all_results = [_parse_foursquare_result(r).model_dump() for r in raw]
            else:
                all_results = await _fetch_openai_places(place_type, query)
        except Exception:
            logger.warning("Place search failed for %s", place_type)
            all_results = []

        if all_results:
            set_cached(cache_k, all_results)

    excluded = set(query.excluded_ids)
    filtered = [r for r in all_results if r["place_id"] not in excluded]
    filtered.sort(key=lambda r: r.get("rating", 0), reverse=True)
    top = filtered[:TOP_N]

    filters_broadened = False
    if not top and not cached:
        # Try without filters
        try:
            if _use_foursquare():
                raw_broad = await _fetch_foursquare(place_type, query)
                broad = [_parse_foursquare_result(r).model_dump() for r in raw_broad]
            else:
                broad = await _fetch_openai_places(place_type, query)
        except Exception:
            broad = []
        broad = [r for r in broad if r["place_id"] not in excluded]
        broad.sort(key=lambda r: r.get("rating", 0), reverse=True)
        top = broad[:TOP_N]
        filters_broadened = True

    return PlacesResponse(
        results=[PlaceResult(**r) for r in top],
        filters_broadened=filters_broadened,
    )


async def get_hotels(query: PlaceQuery) -> PlacesResponse:
    return await _search_places("lodging", query)


async def get_restaurants(query: PlaceQuery) -> PlacesResponse:
    return await _search_places("restaurant", query)
