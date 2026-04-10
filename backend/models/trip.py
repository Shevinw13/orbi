"""Pydantic models for Trip CRUD endpoints.

Requirements: 9.1, 9.2, 9.3, 9.4, 9.5, 12.5
"""

from __future__ import annotations

from datetime import datetime
from typing import Any

from pydantic import BaseModel, Field


class TripCreate(BaseModel):
    """POST /trips request body — save a trip."""

    destination: str = Field(..., description="City or destination name")
    destination_lat_lng: str | None = Field(None, description="Lat/lng string for the destination")
    num_days: int = Field(..., ge=1, le=14, description="Trip length in days (1-14)")
    vibe: str | None = Field(None, description="Trip vibe: Foodie, Adventure, Relaxed, Nightlife")
    preferences: dict[str, Any] | None = Field(None, description="User preferences JSON")
    itinerary: dict[str, Any] | None = Field(None, description="Generated itinerary JSON")
    selected_hotel_id: str | None = Field(None, description="Selected hotel place ID")
    selected_restaurants: list[dict[str, Any]] | None = Field(None, description="Selected restaurants")
    cost_breakdown: dict[str, Any] | None = Field(None, description="Cost breakdown JSON")


class TripResponse(BaseModel):
    """Full trip object returned by GET /trips/{id} and POST /trips."""

    id: str
    user_id: str
    destination: str
    destination_lat_lng: str | None = None
    num_days: int
    vibe: str | None = None
    preferences: dict[str, Any] | None = None
    itinerary: dict[str, Any] | None = None
    selected_hotel_id: str | None = None
    selected_restaurants: list[dict[str, Any]] | None = None
    cost_breakdown: dict[str, Any] | None = None
    created_at: str
    updated_at: str


class TripListItem(BaseModel):
    """Lightweight trip summary for GET /trips list."""

    id: str
    destination: str
    num_days: int
    vibe: str | None = None
    created_at: str
