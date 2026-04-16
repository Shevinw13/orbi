"""Pydantic models for itinerary generation request and response.

Covers the Itinerary_Engine data structures per the design doc.
Requirements: 2.5, 4.1, 5.1, 5.4, 13.1, 13.2, 13.3, 14.1, 14.2
"""

from __future__ import annotations

from typing import Union

from pydantic import BaseModel, Field


# --- Request Models ---


class ItineraryRequest(BaseModel):
    """POST /trips/generate request body."""

    destination: str = Field(..., description="City or destination name")
    latitude: float = Field(..., description="Destination latitude")
    longitude: float = Field(..., description="Destination longitude")
    num_days: int = Field(..., ge=1, le=14, description="Trip length in days (1-14)")
    budget_tier: str = Field(..., description="$, $$, $$$, $$$$, or $$$$$")
    vibes: list[str] = Field(..., min_length=1, description="One or more vibes")
    family_friendly: bool = Field(False, description="Enable family-friendly mode")


class ReplaceActivityRequest(BaseModel):
    """POST /trips/replace-item request body (Req 6.2, 14.1, 14.2)."""

    destination: str = Field(..., description="City or destination name")
    day_number: int = Field(..., ge=1, description="Day number in the itinerary")
    time_slot: str = Field(..., description="Time slot: Morning, Afternoon, or Evening")
    item_type: str = Field("activity", description="'activity' or 'meal'")
    current_item_name: str = Field(..., description="Name of the item being replaced")
    existing_activities: list[str] = Field(
        default_factory=list,
        description="List of activity/meal names already in the itinerary to avoid duplicates",
    )
    vibes: list[str] = Field(default_factory=list, description="Trip vibes")
    budget_tier: str = Field("", description="Budget tier ($-$$$$$)")
    adjacent_activity_coords: list[dict] | None = Field(
        None,
        description="Lat/lng coordinates of adjacent activities for proximity constraint",
    )
    num_suggestions: int = Field(5, ge=1, le=10, description="Number of suggestions to return")


# --- Slot / Meal Models ---


class ActivitySlot(BaseModel):
    """A single activity within a day's itinerary."""

    time_slot: str = Field(..., description="Morning, Afternoon, or Evening")
    activity_name: str
    description: str
    latitude: float
    longitude: float
    estimated_duration_min: int
    travel_time_to_next_min: int | None = Field(
        None, description="Travel time in minutes to the next activity"
    )
    estimated_cost_usd: float = 0.0
    tag: str | None = None


class MealSlot(BaseModel):
    """A meal entry within a day's itinerary (Req 5.4, 13.3)."""

    meal_type: str = Field(..., description="Breakfast, Lunch, or Dinner")
    restaurant_name: str
    cuisine: str
    price_level: str
    latitude: float
    longitude: float
    estimated_cost_usd: float = 0.0
    place_id: str | None = None
    is_estimated: bool = True


# --- Day / Response Models ---


class ItineraryDay(BaseModel):
    """One day of the itinerary."""

    day_number: int
    slots: list[ActivitySlot]
    meals: list[MealSlot] = Field(default_factory=list)


class ItineraryResponse(BaseModel):
    """Full itinerary returned by the Itinerary_Engine."""

    destination: str
    num_days: int
    vibes: list[str]
    budget_tier: str
    days: list[ItineraryDay]
    reasoning_text: str | None = None


class ReplaceSuggestionsResponse(BaseModel):
    """Response for replace-item endpoint with multiple suggestions (Req 14.1)."""

    suggestions: list[Union[ActivitySlot, MealSlot]]
