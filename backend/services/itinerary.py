"""Itinerary_Engine — generates AI-powered itineraries via OpenAI.

Constructs a prompt from trip preferences, parses the structured JSON
response, validates geographic proximity, and caches results in Redis.

Requirements: 2.5, 2.6, 3.7, 4.1, 5.1, 5.4, 5.5, 13.1, 13.2, 13.3, 13.4, 14.1, 14.2
"""

from __future__ import annotations

import hashlib
import json
import logging
from typing import Union

import httpx

from backend.config import settings
from backend.models.itinerary import (
    ActivitySlot,
    ItineraryDay,
    ItineraryRequest,
    ItineraryResponse,
    MealSlot,
    ReplaceActivityRequest,
    ReplaceSuggestionsResponse,
)
from backend.services.cache import get_cached, set_cached

logger = logging.getLogger(__name__)

OPENAI_CHAT_URL = "https://api.openai.com/v1/chat/completions"
CACHE_TTL = 86400  # 24 hours
MAX_TRAVEL_TIME_MIN = 60  # Req 4.8

# Budget tier mapping for prompt calibration
BUDGET_TIER_MAP: dict[str, str] = {
    "$": "Budget",
    "$$": "Casual",
    "$$$": "Comfortable",
    "$$$$": "Premium",
    "$$$$$": "Luxury",
}

# Budget tier cost guidance for the prompt
BUDGET_TIER_GUIDANCE: dict[str, dict[str, str]] = {
    "$": {
        "hotel": "$40-80/night",
        "restaurant": "$8-15/person",
        "activity": "$0-20/day",
    },
    "$$": {
        "hotel": "$80-150/night",
        "restaurant": "$15-30/person",
        "activity": "$20-50/day",
    },
    "$$$": {
        "hotel": "$150-250/night",
        "restaurant": "$30-50/person",
        "activity": "$50-100/day",
    },
    "$$$$": {
        "hotel": "$250-400/night",
        "restaurant": "$50-80/person",
        "activity": "$100-200/day",
    },
    "$$$$$": {
        "hotel": "$400+/night",
        "restaurant": "$80+/person",
        "activity": "$200+/day",
    },
}


def _build_cache_key(request: ItineraryRequest) -> str:
    """Build a deterministic Redis cache key from request parameters.

    Key format: itinerary:{hash} where hash is derived from
    (destination, num_days, budget_tier, vibes).
    """
    vibes_str = ",".join(sorted(v.lower().strip() for v in request.vibes))
    raw = (
        f"{request.destination.lower().strip()}:"
        f"{request.num_days}:"
        f"{request.budget_tier}:"
        f"{vibes_str}:"
        f"{request.family_friendly}"
    )
    key_hash = hashlib.sha256(raw.encode()).hexdigest()[:32]
    return f"itinerary:{key_hash}"


def _build_prompt(request: ItineraryRequest) -> str:
    """Build the OpenAI prompt for itinerary generation.

    Accepts budget_tier and vibes list. Instructs the model to generate
    meals (Breakfast/Lunch/Dinner) within time blocks alongside activities.
    Targets 3-5 items per day, soft cap 6.

    Requirements: 2.6, 3.7, 5.5, 13.1, 13.2, 13.3, 13.4
    """
    tier_label = BUDGET_TIER_MAP.get(request.budget_tier, "Comfortable")
    guidance = BUDGET_TIER_GUIDANCE.get(request.budget_tier, BUDGET_TIER_GUIDANCE["$$$"])

    vibes_str = ", ".join(request.vibes)
    family_note = " The trip should be family-friendly." if request.family_friendly else ""

    prompt = f"""Generate a {request.num_days}-day travel itinerary for {request.destination}.

Budget tier: {request.budget_tier} ({tier_label})
  - Hotel budget: {guidance['hotel']}
  - Restaurant budget: {guidance['restaurant']}
  - Activity budget: {guidance['activity']}

Vibes: {vibes_str}
{family_note}

RULES:
- Each day has exactly 3 time blocks: Morning, Afternoon, Evening.
- MANDATORY: Each time block (Morning, Afternoon, Evening) MUST contain EXACTLY 1 activity. Use time_slot values "Morning", "Afternoon", or "Evening" for each activity.
- MANDATORY: Each day MUST contain EXACTLY 3 meals: Breakfast (in Morning block), Lunch (in Afternoon block), Dinner (in Evening block).
- This means each day has a MINIMUM of 6 items: 3 activities + 3 meals.
- For Breakfast: Include a highly-rated breakfast spot known for morning dining.
- For Lunch: Include a popular lunch restaurant with good midday options.
- For Dinner: Include a top-rated dinner restaurant with evening ambiance.
- Activities and meals should reflect ALL selected vibes: {vibes_str}.
- Costs should match the {tier_label} budget tier.
- All locations must be real places in {request.destination} with accurate coordinates.
- Travel time between consecutive items should be under {MAX_TRAVEL_TIME_MIN} minutes.
- Do NOT skip any time block. Every day must have Morning, Afternoon, and Evening activities.

Return ONLY valid JSON with this exact structure:
{{
  "reasoning_text": "Brief explanation of itinerary choices",
  "days": [
    {{
      "day_number": 1,
      "slots": [
        {{
          "time_slot": "Morning",
          "activity_name": "Place Name",
          "description": "Brief description",
          "latitude": 0.0,
          "longitude": 0.0,
          "estimated_duration_min": 90,
          "travel_time_to_next_min": 15,
          "estimated_cost_usd": 20.0,
          "tag": "Popular"
        }}
      ],
      "meals": [
        {{
          "meal_type": "Breakfast",
          "restaurant_name": "Restaurant Name",
          "cuisine": "Cuisine Type",
          "price_level": "{request.budget_tier}",
          "latitude": 0.0,
          "longitude": 0.0,
          "estimated_cost_usd": 15.0,
          "is_estimated": true
        }},
        {{
          "meal_type": "Lunch",
          "restaurant_name": "Restaurant Name",
          "cuisine": "Cuisine Type",
          "price_level": "{request.budget_tier}",
          "latitude": 0.0,
          "longitude": 0.0,
          "estimated_cost_usd": 25.0,
          "is_estimated": true
        }},
        {{
          "meal_type": "Dinner",
          "restaurant_name": "Restaurant Name",
          "cuisine": "Cuisine Type",
          "price_level": "{request.budget_tier}",
          "latitude": 0.0,
          "longitude": 0.0,
          "estimated_cost_usd": 40.0,
          "is_estimated": true
        }}
      ]
    }}
  ]
}}"""
    return prompt


def _parse_itinerary_response(raw_json: dict, request: ItineraryRequest) -> ItineraryResponse:
    """Parse the OpenAI JSON response into an ItineraryResponse.

    Extracts activity slots and meal slots from each day.
    Requirements: 5.4, 5.5, 13.3
    """
    days: list[ItineraryDay] = []

    for day_data in raw_json.get("days", []):
        # Parse activity slots
        slots: list[ActivitySlot] = []
        for slot_data in day_data.get("slots", []):
            slots.append(
                ActivitySlot(
                    time_slot=slot_data.get("time_slot", "Morning"),
                    activity_name=slot_data.get("activity_name", ""),
                    description=slot_data.get("description", ""),
                    latitude=float(slot_data.get("latitude", 0.0)),
                    longitude=float(slot_data.get("longitude", 0.0)),
                    estimated_duration_min=int(slot_data.get("estimated_duration_min", 60)),
                    travel_time_to_next_min=slot_data.get("travel_time_to_next_min"),
                    estimated_cost_usd=float(slot_data.get("estimated_cost_usd", 0.0)),
                    tag=slot_data.get("tag"),
                )
            )

        # Parse meal slots
        meals: list[MealSlot] = []
        for meal_data in day_data.get("meals", []):
            meals.append(
                MealSlot(
                    meal_type=meal_data.get("meal_type", "Lunch"),
                    restaurant_name=meal_data.get("restaurant_name", ""),
                    cuisine=meal_data.get("cuisine", ""),
                    price_level=meal_data.get("price_level", request.budget_tier),
                    latitude=float(meal_data.get("latitude", 0.0)),
                    longitude=float(meal_data.get("longitude", 0.0)),
                    estimated_cost_usd=float(meal_data.get("estimated_cost_usd", 0.0)),
                    place_id=meal_data.get("place_id"),
                    is_estimated=meal_data.get("is_estimated", True),
                )
            )

        days.append(
            ItineraryDay(
                day_number=day_data.get("day_number", len(days) + 1),
                slots=slots,
                meals=meals,
            )
        )

    return ItineraryResponse(
        destination=request.destination,
        num_days=request.num_days,
        vibes=request.vibes,
        budget_tier=request.budget_tier,
        days=days,
        reasoning_text=raw_json.get("reasoning_text"),
    )


async def _call_openai(prompt: str) -> dict:
    """Send a prompt to OpenAI and return the parsed JSON response."""
    async with httpx.AsyncClient(timeout=60.0) as client:
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
                        "content": (
                            "You are a travel itinerary planner. "
                            "Return only valid JSON, no markdown fences or extra text."
                        ),
                    },
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
    return json.loads(content)


async def generate_itinerary(request: ItineraryRequest) -> ItineraryResponse:
    """Generate a complete itinerary with activities and meals.

    Checks cache first, then calls OpenAI if needed.
    Returns ItineraryResponse with vibes list and budget_tier.

    Requirements: 1.3, 2.5, 2.6, 3.6, 3.7
    """
    cache_key = _build_cache_key(request)
    cached = get_cached(cache_key)

    if cached is not None:
        logger.info("Cache hit for itinerary: %s", cache_key)
        return ItineraryResponse(**cached)

    logger.info("Cache miss — generating itinerary for %s", request.destination)
    prompt = _build_prompt(request)

    try:
        raw_json = await _call_openai(prompt)
    except Exception as exc:
        logger.error("OpenAI itinerary generation failed: %s", exc)
        raise RuntimeError(f"Itinerary generation failed: {exc}") from exc

    itinerary = _parse_itinerary_response(raw_json, request)

    # Cache the result
    set_cached(cache_key, itinerary.model_dump(), ttl=CACHE_TTL)

    return itinerary


def _build_replace_prompt(request: ReplaceActivityRequest) -> str:
    """Build the OpenAI prompt for generating replacement suggestions.

    Accepts vibes list, budget_tier, item_type, and num_suggestions.
    Excludes items already in the itinerary.

    Requirements: 6.2, 14.1, 14.2, 14.3
    """
    vibes_str = ", ".join(request.vibes) if request.vibes else "General"
    tier_label = BUDGET_TIER_MAP.get(request.budget_tier, "Comfortable")

    excluded_str = ""
    if request.existing_activities:
        excluded_str = "\nDo NOT suggest any of these (already in itinerary): " + ", ".join(
            request.existing_activities
        )

    coords_str = ""
    if request.adjacent_activity_coords:
        coords_parts = [
            f"({c.get('lat', 0)}, {c.get('lng', 0)})"
            for c in request.adjacent_activity_coords
        ]
        coords_str = f"\nNearby activity coordinates: {', '.join(coords_parts)}. Keep suggestions within walking/short transit distance."

    if request.item_type == "meal":
        item_desc = "restaurant/meal"
        json_template = """[
    {{
      "meal_type": "{meal_type}",
      "restaurant_name": "Name",
      "cuisine": "Cuisine Type",
      "price_level": "{budget_tier}",
      "latitude": 0.0,
      "longitude": 0.0,
      "estimated_cost_usd": 25.0,
      "is_estimated": true
    }}
  ]""".format(meal_type=request.time_slot.replace("Morning", "Breakfast").replace("Afternoon", "Lunch").replace("Evening", "Dinner"), budget_tier=request.budget_tier)
    else:
        item_desc = "activity"
        json_template = """[
    {{
      "time_slot": "{time_slot}",
      "activity_name": "Name",
      "description": "Brief description",
      "latitude": 0.0,
      "longitude": 0.0,
      "estimated_duration_min": 90,
      "travel_time_to_next_min": 15,
      "estimated_cost_usd": 20.0,
      "tag": "Popular"
    }}
  ]""".format(time_slot=request.time_slot)

    prompt = f"""Suggest {request.num_suggestions} alternative {item_desc} options to replace "{request.current_item_name}" in {request.destination}.

Day {request.day_number}, Time block: {request.time_slot}
Budget tier: {request.budget_tier} ({tier_label})
Vibes: {vibes_str}
{excluded_str}
{coords_str}

Return ONLY a valid JSON array of {request.num_suggestions} suggestions:
{json_template}"""
    return prompt


async def replace_activity(request: ReplaceActivityRequest) -> ReplaceSuggestionsResponse:
    """Generate 3-5 replacement suggestions for an itinerary item.

    Returns ReplaceSuggestionsResponse with suggestions list.
    Requirements: 6.2, 14.1, 14.2, 14.3
    """
    prompt = _build_replace_prompt(request)

    try:
        raw_json = await _call_openai(prompt)
    except Exception as exc:
        logger.error("OpenAI replace generation failed: %s", exc)
        raise RuntimeError(f"Replace suggestion generation failed: {exc}") from exc

    # raw_json should be a list of suggestions
    suggestions_data = raw_json if isinstance(raw_json, list) else raw_json.get("suggestions", [])

    suggestions: list[Union[ActivitySlot, MealSlot]] = []
    for item in suggestions_data:
        if request.item_type == "meal":
            suggestions.append(
                MealSlot(
                    meal_type=item.get("meal_type", "Lunch"),
                    restaurant_name=item.get("restaurant_name", ""),
                    cuisine=item.get("cuisine", ""),
                    price_level=item.get("price_level", request.budget_tier),
                    latitude=float(item.get("latitude", 0.0)),
                    longitude=float(item.get("longitude", 0.0)),
                    estimated_cost_usd=float(item.get("estimated_cost_usd", 0.0)),
                    place_id=item.get("place_id"),
                    is_estimated=item.get("is_estimated", True),
                )
            )
        else:
            suggestions.append(
                ActivitySlot(
                    time_slot=item.get("time_slot", request.time_slot),
                    activity_name=item.get("activity_name", ""),
                    description=item.get("description", ""),
                    latitude=float(item.get("latitude", 0.0)),
                    longitude=float(item.get("longitude", 0.0)),
                    estimated_duration_min=int(item.get("estimated_duration_min", 60)),
                    travel_time_to_next_min=item.get("travel_time_to_next_min"),
                    estimated_cost_usd=float(item.get("estimated_cost_usd", 0.0)),
                    tag=item.get("tag"),
                )
            )

    return ReplaceSuggestionsResponse(suggestions=suggestions)
