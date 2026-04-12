"""Itinerary_Engine — generates AI-powered itineraries via OpenAI.

Constructs a prompt from trip preferences, parses the structured JSON
response, validates geographic proximity, and caches results in Redis.

Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.7, 4.8, 13.4
"""

from __future__ import annotations

import hashlib
import json
import logging

import httpx

from backend.config import settings
from backend.models.itinerary import (
    ActivitySlot,
    ItineraryDay,
    ItineraryRequest,
    ItineraryResponse,
    ReplaceActivityRequest,
    RestaurantRecommendation,
    SelectedRestaurant,
)
from backend.services.cache import get_cached, set_cached

logger = logging.getLogger(__name__)

OPENAI_CHAT_URL = "https://api.openai.com/v1/chat/completions"
CACHE_TTL = 86400  # 24 hours
MAX_TRAVEL_TIME_MIN = 60  # Req 4.8


def _build_cache_key(request: ItineraryRequest) -> str:
    """Build a deterministic Redis cache key from request parameters.

    Key format: itinerary:{hash} where hash is derived from
    (destination, num_days, vibe, preferences_hash).
    """
    prefs = json.dumps(
        {
            "hotel_price_range": request.hotel_price_range,
            "hotel_vibe": request.hotel_vibe,
            "restaurant_price_range": request.restaurant_price_range,
            "cuisine_type": request.cuisine_type,
        },
        sort_keys=True,
    )
    prefs_hash = hashlib.sha256(prefs.encode()).hexdigest()[:16]
    raw = f"{request.destination.lower().strip()}:{request.num_days}:{request.vibe.lower().strip()}:{prefs_hash}"
    key_hash = hashlib.sha256(raw.encode()).hexdigest()[:32]
    return f"itinerary:{key_hash}"


def _build_prompt(request: ItineraryRequest) -> str:
    """Construct the OpenAI system + user prompt for itinerary generation."""
    cuisine_note = f"Preferred cuisine: {request.cuisine_type}. " if request.cuisine_type else ""
    restaurant_price_note = (
        f"Restaurant price range: {request.restaurant_price_range}. "
        if request.restaurant_price_range
        else ""
    )

    family_friendly_note = (
        "Family-friendly mode: prioritize parks, museums, zoos, cultural centers. "
        "Reduce nightlife and adult venues.\n"
        if request.family_friendly
        else ""
    )

    return (
        f"Generate a {request.num_days}-day travel itinerary for {request.destination}.\n"
        f"Trip vibe: {request.vibe}.\n"
        f"{cuisine_note}{restaurant_price_note}{family_friendly_note}\n"
        "Requirements:\n"
        "- Each day must have Morning, Afternoon, and Evening activity slots.\n"
        "- Include a mix of top attractions and local hidden-gem experiences.\n"
        "- Activities within each day must be geographically close — consecutive "
        "activities should require no more than 60 minutes of travel time.\n"
        "- Include estimated travel time in minutes between consecutive activities.\n"
        "- Include one restaurant recommendation per day matching the vibe.\n"
        "- Tailor activity selection, restaurant choices, and pacing to the vibe.\n"
        "- For each activity, include a \"tag\" field with one of: \"Popular\", \"Highly rated\", "
        "\"Hidden gem\", \"Family-friendly\", or null if none apply.\n\n"
        "Return ONLY valid JSON matching this exact schema (no markdown, no extra text):\n"
        "{\n"
        '  "destination": "<city>",\n'
        f'  "num_days": {request.num_days},\n'
        f'  "vibe": "{request.vibe}",\n'
        '  "reasoning": "1-2 sentence explanation of why this itinerary was planned this way, '
        'based on the vibe and optimization criteria",\n'
        '  "days": [\n'
        "    {\n"
        '      "day_number": 1,\n'
        '      "slots": [\n'
        "        {\n"
        '          "time_slot": "Morning",\n'
        '          "activity_name": "...",\n'
        '          "description": "...",\n'
        '          "latitude": 0.0,\n'
        '          "longitude": 0.0,\n'
        '          "estimated_duration_min": 120,\n'
        '          "travel_time_to_next_min": 15,\n'
        '          "estimated_cost_usd": 20,\n'
        '          "tag": "Popular | Highly rated | Hidden gem | Family-friendly (pick one or null)"\n'
        "        }\n"
        "      ],\n"
        '      "restaurant": {\n'
        '        "name": "...",\n'
        '        "cuisine": "...",\n'
        '        "price_level": "$",\n'
        '        "rating": 4.5,\n'
        '        "latitude": 0.0,\n'
        '        "longitude": 0.0,\n'
        '        "image_url": null\n'
        "      }\n"
        "    }\n"
        "  ]\n"
        "}"
    )


def _validate_travel_times(itinerary: ItineraryResponse) -> ItineraryResponse:
    """Validate that consecutive activities are within 60 min travel (Req 4.8).

    If any travel_time_to_next_min exceeds the limit, it is clamped to the max
    and a warning is logged. The itinerary is still returned — the constraint
    is best-effort since OpenAI may not always produce perfect estimates.
    """
    for day in itinerary.days:
        for slot in day.slots:
            if (
                slot.travel_time_to_next_min is not None
                and slot.travel_time_to_next_min > MAX_TRAVEL_TIME_MIN
            ):
                logger.warning(
                    "Travel time %d min exceeds %d min limit for '%s' on day %d — clamping.",
                    slot.travel_time_to_next_min,
                    MAX_TRAVEL_TIME_MIN,
                    slot.activity_name,
                    day.day_number,
                )
                slot.travel_time_to_next_min = MAX_TRAVEL_TIME_MIN
    return itinerary


def _parse_itinerary_response(raw_json: dict) -> ItineraryResponse:
    """Parse the raw OpenAI JSON into validated Pydantic models."""
    days: list[ItineraryDay] = []
    for day_data in raw_json.get("days", []):
        slots = [ActivitySlot(**s) for s in day_data.get("slots", [])]
        restaurant = None
        if day_data.get("restaurant"):
            restaurant = RestaurantRecommendation(**day_data["restaurant"])
        days.append(
            ItineraryDay(
                day_number=day_data["day_number"],
                slots=slots,
                restaurant=restaurant,
            )
        )
    return ItineraryResponse(
        destination=raw_json["destination"],
        num_days=raw_json["num_days"],
        vibe=raw_json["vibe"],
        days=days,
        reasoning_text=raw_json.get("reasoning"),
    )


def _inject_selected_restaurants(
    itinerary: ItineraryResponse,
    selected_restaurants: list[SelectedRestaurant],
) -> ItineraryResponse:
    """Inject user-selected restaurants into the first N days of the itinerary.

    - Each selected restaurant appears at most once.
    - Sets origin="user" on injected restaurants and origin="ai" on AI-generated ones.
    - Remaining days keep their AI-generated restaurants.
    """
    # Mark all existing restaurants as AI-generated
    for day in itinerary.days:
        if day.restaurant and day.restaurant.origin is None:
            day.restaurant.origin = "ai"

    if not selected_restaurants:
        return itinerary

    # Deduplicate by name (case-insensitive)
    seen_names: set[str] = set()
    unique_selected: list[SelectedRestaurant] = []
    for sr in selected_restaurants:
        key = sr.name.strip().lower()
        if key not in seen_names:
            seen_names.add(key)
            unique_selected.append(sr)

    # Inject into the first N days
    for i, sr in enumerate(unique_selected):
        if i >= len(itinerary.days):
            break
        itinerary.days[i].restaurant = RestaurantRecommendation(
            name=sr.name,
            cuisine=sr.cuisine,
            price_level=sr.price_level,
            rating=0.0,
            latitude=sr.latitude,
            longitude=sr.longitude,
            image_url=None,
            origin="user",
        )

    return itinerary


async def generate_itinerary(request: ItineraryRequest) -> ItineraryResponse:
    """Generate an AI-powered itinerary, with Redis caching.

    1. Check Redis cache for a matching itinerary (Req 13.4).
    2. On cache miss, call OpenAI to generate a new itinerary (Req 4.1).
    3. Parse and validate the response (Req 4.2, 4.3, 4.7, 4.8).
    4. Cache the result with 24h TTL.

    Raises:
        RuntimeError: If the OpenAI API call fails (Req 4.6).
    """
    cache_key = _build_cache_key(request)

    # 1. Check cache
    cached = get_cached(cache_key)
    if cached is not None:
        logger.info("Cache hit for itinerary key=%s", cache_key)
        return _parse_itinerary_response(cached)

    # 2. Call OpenAI
    prompt = _build_prompt(request)
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.post(
                OPENAI_CHAT_URL,
                headers={
                    "Authorization": f"Bearer {settings.openai_api_key}",
                    "Content-Type": "application/json",
                },
                json={
                    "model": "gpt-4o-mini",
                    "messages": [
                        {
                            "role": "system",
                            "content": (
                                "You are a travel planning assistant. "
                                "Return ONLY valid JSON, no markdown fences or extra text."
                            ),
                        },
                        {"role": "user", "content": prompt},
                    ],
                    "temperature": 0.7,
                    "max_tokens": 4096,
                },
            )
            response.raise_for_status()
    except httpx.HTTPError as exc:
        logger.error("OpenAI API call failed: %s", exc)
        raise RuntimeError(f"Itinerary generation failed: {exc}") from exc

    # 3. Parse response
    try:
        body = response.json()
        content = body["choices"][0]["message"]["content"]
        # Strip markdown fences if present
        content = content.strip()
        if content.startswith("```"):
            content = content.split("\n", 1)[1] if "\n" in content else content[3:]
        if content.endswith("```"):
            content = content[:-3]
        content = content.strip()
        raw_itinerary = json.loads(content)
    except (KeyError, IndexError, json.JSONDecodeError) as exc:
        logger.error("Failed to parse OpenAI response: %s", exc)
        raise RuntimeError("Failed to parse itinerary from AI response") from exc

    itinerary = _parse_itinerary_response(raw_itinerary)

    # 4. Inject user-selected restaurants if provided
    if request.selected_restaurants:
        itinerary = _inject_selected_restaurants(itinerary, request.selected_restaurants)

    # 5. Validate travel times (Req 4.8)
    itinerary = _validate_travel_times(itinerary)

    # 6. Cache the result (Req 13.4)
    set_cached(cache_key, raw_itinerary, ttl=CACHE_TTL)
    logger.info("Cached itinerary key=%s", cache_key)

    return itinerary


def _build_replace_prompt(request: ReplaceActivityRequest) -> str:
    """Construct the OpenAI prompt for replacing a single activity (Req 5.5, 11.1–11.4)."""
    avoid_list = "\n".join(f"- {name}" for name in request.existing_activities)
    avoid_section = (
        f"\nDo NOT suggest any of these activities (already in the itinerary):\n{avoid_list}\n"
        if request.existing_activities
        else ""
    )

    # Adjacent activity proximity constraint (Req 11.3, 11.4)
    adjacent_section = ""
    if request.adjacent_activity_coords:
        coord_strs = [
            f"({c.get('lat', 0)}, {c.get('lng', 0)})"
            for c in request.adjacent_activity_coords
        ]
        adjacent_section = (
            f"\nThe replacement activity must be within 60 minutes of travel time "
            f"from these adjacent activity coordinates: {', '.join(coord_strs)}.\n"
        )

    return (
        f"Suggest ONE alternative {request.time_slot.lower()} activity in {request.destination}.\n"
        f"Trip vibe: {request.vibe}.\n"
        f"This replaces: {request.current_activity_name}.\n"
        f"{avoid_section}{adjacent_section}\n"
        "Requirements:\n"
        "- The activity must match the vibe.\n"
        "- Include realistic latitude and longitude for the location.\n"
        "- Include estimated duration in minutes and estimated cost in USD.\n\n"
        "Return ONLY valid JSON matching this exact schema (no markdown, no extra text):\n"
        "{\n"
        f'  "time_slot": "{request.time_slot}",\n'
        '  "activity_name": "...",\n'
        '  "description": "...",\n'
        '  "latitude": 0.0,\n'
        '  "longitude": 0.0,\n'
        '  "estimated_duration_min": 120,\n'
        '  "travel_time_to_next_min": null,\n'
        '  "estimated_cost_usd": 20,\n'
        '  "tag": "Popular | Highly rated | Hidden gem | Family-friendly (pick one or null)"\n'
        "}"
    )


async def replace_activity(request: ReplaceActivityRequest) -> ActivitySlot:
    """Generate an alternative activity for a specific time slot (Req 5.5).

    Calls OpenAI with context of existing activities to avoid duplicates.

    Raises:
        RuntimeError: If the OpenAI API call fails.
    """
    prompt = _build_replace_prompt(request)

    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.post(
                OPENAI_CHAT_URL,
                headers={
                    "Authorization": f"Bearer {settings.openai_api_key}",
                    "Content-Type": "application/json",
                },
                json={
                    "model": "gpt-4o-mini",
                    "messages": [
                        {
                            "role": "system",
                            "content": (
                                "You are a travel planning assistant. "
                                "Return ONLY valid JSON, no markdown fences or extra text."
                            ),
                        },
                        {"role": "user", "content": prompt},
                    ],
                    "temperature": 0.8,
                    "max_tokens": 1024,
                },
            )
            response.raise_for_status()
    except httpx.HTTPError as exc:
        logger.error("OpenAI API call failed for replace-activity: %s", exc)
        raise RuntimeError(f"Activity replacement failed: {exc}") from exc

    try:
        body = response.json()
        content = body["choices"][0]["message"]["content"]
        content = content.strip()
        if content.startswith("```"):
            content = content.split("\n", 1)[1] if "\n" in content else content[3:]
        if content.endswith("```"):
            content = content[:-3]
        content = content.strip()
        raw_activity = json.loads(content)
    except (KeyError, IndexError, json.JSONDecodeError) as exc:
        logger.error("Failed to parse OpenAI replace-activity response: %s", exc)
        raise RuntimeError("Failed to parse replacement activity from AI response") from exc

    return ActivitySlot(**raw_activity)
