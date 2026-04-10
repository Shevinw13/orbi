"""Pydantic models for itinerary generation request and response.

Covers the Itinerary_Engine data structures per the design doc.
Requirements: 4.1, 4.2, 4.3, 4.5, 4.7
"""

from __future__ import annotations

from pydantic import BaseModel, Field


class ReplaceActivityRequest(BaseModel):
    """POST /trips/replace-item request body (Req 5.5)."""

    destination: str = Field(..., description="City or destination name")
    day_number: int = Field(..., ge=1, description="Day number in the itinerary")
    time_slot: str = Field(..., description="Time slot to replace: Morning, Afternoon, or Evening")
    current_activity_name: str = Field(..., description="Name of the activity being replaced")
    existing_activities: list[str] = Field(
        default_factory=list,
        description="List of activity names already in the itinerary to avoid duplicates",
    )
    vibe: str = Field(..., description="Trip vibe: Foodie, Adventure, Relaxed, Nightlife")


class ItineraryRequest(BaseModel):
    """POST /trips/generate request body."""

    destination: str = Field(..., description="City or destination name")
    latitude: float = Field(..., description="Destination latitude")
    longitude: float = Field(..., description="Destination longitude")
    num_days: int = Field(..., ge=1, le=14, description="Trip length in days (1-14)")
    hotel_price_range: str | None = Field(None, description="Hotel price range ($–$$$)")
    hotel_vibe: str | None = Field(None, description="Hotel vibe (luxury, boutique, budget)")
    restaurant_price_range: str | None = Field(None, description="Restaurant price range ($–$$$)")
    cuisine_type: str | None = Field(None, description="Preferred cuisine type")
    vibe: str = Field(..., description="Trip vibe: Foodie, Adventure, Relaxed, Nightlife")


class RestaurantRecommendation(BaseModel):
    """A restaurant recommendation for a given day."""

    name: str
    cuisine: str
    price_level: str
    rating: float
    latitude: float
    longitude: float
    image_url: str | None = None


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


class ItineraryDay(BaseModel):
    """One day of the itinerary."""

    day_number: int
    slots: list[ActivitySlot]
    restaurant: RestaurantRecommendation | None = None


class ItineraryResponse(BaseModel):
    """Full itinerary returned by the Itinerary_Engine."""

    destination: str
    num_days: int
    vibe: str
    days: list[ItineraryDay]
